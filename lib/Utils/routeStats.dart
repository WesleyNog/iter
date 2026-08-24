import 'package:iter/Utils/insucessoBairro.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/Utils/weather.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/services/openWeather.dart';

/// Agregações da tela de gráficos.
///
/// Tudo aqui é função pura sobre uma lista de rotas: sem Firestore, sem
/// `BuildContext`, sem widget. É de propósito — é neste arquivo que mora o erro
/// que ninguém vê (divisão por zero, rateio de insucesso, turno sem cobertura),
/// e função pura é a única coisa que dá para provar barato.
///
/// Convenção do arquivo: recebe a lista **já filtrada** por
/// [realizedInPeriod], nunca busca nada, e devolve lista ordenada em vez de
/// `Map` — a ordem é o produto.

/// Um degrau de ranking: rótulo já legível e o número que ordena a barra.
class RankEntry {
  const RankEntry(this.label, this.value);

  final String label;
  final double value;
}

/// Turnos do gráfico de faixa horária.
///
/// São quatro, e não os três de "manhã/tarde/noite", porque juntos precisam
/// cobrir as 24 horas: rota de entrega começa antes das 6h, e hora sem turno
/// sumiria do gráfico sem avisar.
enum Shift { madrugada, manha, tarde, noite }

extension ShiftRange on Shift {
  String get label => switch (this) {
    Shift.madrugada => 'Madrugada',
    Shift.manha => 'Manhã',
    Shift.tarde => 'Tarde',
    Shift.noite => 'Noite',
  };

  int get startHour => switch (this) {
    Shift.madrugada => 0,
    Shift.manha => 5,
    Shift.tarde => 12,
    Shift.noite => 18,
  };

  int get endHour => switch (this) {
    Shift.madrugada => 4,
    Shift.manha => 11,
    Shift.tarde => 17,
    Shift.noite => 23,
  };
}

/// Números do card de resumo, calculados numa passada só.
class PeriodSummary {
  const PeriodSummary({
    required this.total,
    required this.count,
    required this.routeTotal,
    required this.packages,
    required this.failures,
    required this.pending,
    required this.received,
    required this.upcoming,
    required this.noRoute,
    required this.pendingCount,
    required this.receivedCount,
    required this.scheduledCount,
    required this.runningCount,
    required this.noRouteCount,
  });

  /// Soma de `value` de **tudo** que veio no período, idas sem rota inclusas —
  /// o chamador decide se passa o período inteiro ou só as realizadas.
  ///
  /// É o denominador da barra de status, que tem uma fatia por status: um total
  /// que não incluísse a Sem Rota faria as fatias somarem mais de 100%.
  final double total;

  /// Quantas **rotas**. A ida sem rota não entra: ela não entregou pacote, não
  /// passou por bairro nenhum e não foi uma rota.
  final int count;

  /// O dinheiro só das rotas — [total] menos [noRoute].
  ///
  /// Existe por causa de [average]. Com o total incluindo a Sem Rota e a
  /// contagem excluindo-a, `total / count` dividiria o dinheiro de uma população
  /// pela contagem de outra, e o resultado subiria sozinho a cada ida
  /// registrada — erro para mais, que é o lado que engana.
  final double routeTotal;

  /// Rodado e ainda não pago (`concluido`) — o que falta cair na conta.
  final double pending;

  /// Já pago (`pago`), **sem** as idas sem rota. Quem soma as duas é
  /// [receivedTotal].
  ///
  /// A separação é o que mantém [average] honesta: aqui ficam só rotas, e
  /// [receivedCount] conta a mesma população.
  final double received;

  /// Ainda não rodado (`agendado` + `andamento`) — estimativa.
  final double upcoming;

  /// As idas que não viraram rota (`semRota`), já com o percentual aplicado.
  final double noRoute;

  final int pendingCount;
  final int receivedCount;
  final int scheduledCount;
  final int runningCount;
  final int noRouteCount;

  int get upcomingCount => scheduledCount + runningCount;

  /// O que caiu na conta: o pago mais as idas sem rota.
  ///
  /// É o número do card "Pago no período" — e o denominador dele, senão as
  /// fatias (que vêm de [receivedPayment], já com a Sem Rota) passam de 100% e,
  /// num mês só de idas, o card apaga inteiro dizendo "Nada foi pago".
  double get receivedTotal => received + noRoute;

  /// O que já aconteceu, em dinheiro: o que caiu mais o que falta cair.
  double get realizedTotal => receivedTotal + pending;

  /// Pacotes somados **apenas** das rotas que informaram o campo.
  final int packages;

  /// Insucessos das mesmas rotas contadas em [packages], para os dois lados da
  /// taxa falarem da mesma amostra.
  final int failures;

  /// Quanto rendeu **uma rota**, em média. [routeTotal] e [count] falam da mesma
  /// população de propósito — ver [routeTotal].
  double get average => count == 0 ? 0 : routeTotal / count;

  /// Fração do que já aconteceu que foi paga.
  ///
  /// O denominador é [realizedTotal], e não [total]: rota agendada ainda nem
  /// podia ter sido paga, e contá-la faria a taxa cair sozinha toda vez que o
  /// usuário marcasse uma rota nova na agenda.
  ///
  /// [receivedTotal] nos **dois** lados. Com a Sem Rota só no denominador, cada
  /// ida registrada derrubaria a taxa de recebimento — e ela já nasceu paga.
  double? get receivedRate {
    if (realizedTotal <= 0) return null;
    return (receivedTotal / realizedTotal).clamp(0.0, 1.0);
  }

  /// Fração entregue: `(pacotes - insucessos) / pacotes`.
  ///
  /// `null` quando ninguém informou pacotes no período — sem denominador não
  /// existe taxa, e devolver 0 ou 1 seria inventar.
  double? get deliveryRate {
    if (packages == 0) return null;
    return ((packages - failures) / packages).clamp(0.0, 1.0);
  }
}

/// Insucessos da rota. O switch desligado manda, mesmo com quantidade gravada;
/// ligado sem quantidade vale 1, que é o mínimo que o formulário permite.
int failuresOf(NewRouteModal route) {
  if (route.isInsucesso != true) return 0;
  return route.insucessoQnt ?? 1;
}

/// Rotas com início dentro do período, **em qualquer status**.
///
/// A comparação é por data, com as duas pontas inclusive: a hora que vier em
/// [start]/[end] é ignorada, senão uma rota das 22h sumiria do último dia do
/// filtro.
List<NewRouteModal> inPeriod(
  List<NewRouteModal> routes, {
  required DateTime start,
  required DateTime end,
}) {
  final from = _dateOnly(start);
  final to = _dateOnly(end);

  return routes.where((route) {
    final day = _dateOnly(route.startAt);
    return !day.isBefore(from) && !day.isAfter(to);
  }).toList();
}

/// Rotas que de fato aconteceram (`concluido` ou `pago`).
///
/// É o recorte dos gráficos de análise — empresa, bairro, dia e hora. Bairro
/// "rodado" numa rota que ainda não saiu não é verdade, e insucesso de rota
/// que não aconteceu não existe. Os cards de dinheiro do topo trabalham com o
/// período inteiro, de propósito: lá interessa quanto ainda vai entrar.
///
/// **`semRota` fica de fora, e esta função não muda por causa dela.** É de
/// propósito: `monthStats`, `profileStats`, `companySummary` e os carrosséis de
/// análise leem daqui, e é assim que a ida ao CD fica fora da contagem de rotas,
/// do ranking dos amigos e dos rankings de bairro sem uma linha de código nova
/// em nenhum deles. Quem precisa do dinheiro dela usa [noRouteTrips].
List<NewRouteModal> realized(List<NewRouteModal> routes) => routes
    .where(
      (route) =>
          route.status == StatusRoute.concluido ||
          route.status == StatusRoute.pago,
    )
    .toList();

/// Atalho para o recorte de análise: dentro do período **e** realizada.
List<NewRouteModal> realizedInPeriod(
  List<NewRouteModal> routes, {
  required DateTime start,
  required DateTime end,
}) => realized(inPeriod(routes, start: start, end: end));

/// Rotas rodadas que ainda não foram pagas.
///
/// `concluido` é exatamente esse estado: o serviço acabou e o pagamento não
/// entrou. `agendado` e `andamento` não entram — a rota nem aconteceu, e
/// prometer esse dinheiro como "a receber" seria contar com o ovo.
List<NewRouteModal> pendingPayment(List<NewRouteModal> routes) =>
    routes.where((route) => route.status == StatusRoute.concluido).toList();

/// O que já caiu na conta: `pago` **e** as idas que não viraram rota.
///
/// A Sem Rota nasce paga — a empresa credita a fração assim que a rota some do
/// aplicativo dela —, então perguntar "o que eu já recebi" e não incluí-la seria
/// esconder dinheiro que está no extrato.
List<NewRouteModal> receivedPayment(List<NewRouteModal> routes) => routes
    .where(
      (route) =>
          route.status == StatusRoute.pago ||
          route.status == StatusRoute.semRota,
    )
    .toList();

/// As idas que não viraram rota (`semRota`).
///
/// A segunda régua do arquivo, e ela existe porque a Sem Rota é **dinheiro e
/// quilômetro rodado, mas não é uma rota**: entra no valor, no lucro e no custo
/// por km, e fica fora da contagem, das médias, dos pacotes e dos bairros.
///
/// [realized] continua sendo `concluido + pago` e não foi tocada — é dela que
/// `monthStats`, `profileStats` e todos os carrosséis de análise herdam a
/// exclusão, sem nenhum deles precisar saber que este status existe.
List<NewRouteModal> noRouteTrips(List<NewRouteModal> routes) =>
    routes.where((route) => route.status == StatusRoute.semRota).toList();

/// Rotas que ainda não aconteceram: `agendado` e `andamento`.
///
/// É estimativa, não faturamento — mas é o número que responde "já bati minha
/// meta ou pego mais uma rota?", que só dá para decidir vendo o que está
/// marcado para acontecer.
List<NewRouteModal> notRunYet(List<NewRouteModal> routes) => routes
    .where(
      (route) =>
          route.status == StatusRoute.agendado ||
          route.status == StatusRoute.andamento,
    )
    .toList();

/// Soma de `value` por status, **na ordem do ciclo** (agendado → pago) e não
/// por tamanho: a barra do resumo é lida como uma esteira, não como ranking.
/// Status sem rota vem com zero; quem desenha é que filtra.
List<({StatusRoute status, double value})> valueByStatus(
  List<NewRouteModal> routes,
) {
  final totals = {for (final status in StatusRoute.values) status: 0.0};

  for (final route in routes) {
    totals[route.status] = (totals[route.status] ?? 0) + route.value;
  }

  return [
    for (final status in StatusRoute.values)
      (status: status, value: totals[status] ?? 0),
  ];
}

PeriodSummary summarize(List<NewRouteModal> routes) {
  var total = 0.0;
  var routeTotal = 0.0;
  var count = 0;
  var packages = 0;
  var failures = 0;
  var pending = 0.0;
  var received = 0.0;
  var upcoming = 0.0;
  var noRoute = 0.0;
  var pendingCount = 0;
  var receivedCount = 0;
  var scheduledCount = 0;
  var runningCount = 0;
  var noRouteCount = 0;

  for (final route in routes) {
    total += route.value;

    switch (route.status) {
      case StatusRoute.concluido:
        pending += route.value;
        pendingCount++;
      case StatusRoute.pago:
        received += route.value;
        receivedCount++;
      case StatusRoute.agendado:
        upcoming += route.value;
        scheduledCount++;
      case StatusRoute.andamento:
        upcoming += route.value;
        runningCount++;
      // Não cai em `received`: o card soma as duas por `receivedTotal`, e
      // misturar aqui faria `average` dividir dinheiro de duas populações pela
      // contagem de uma.
      case StatusRoute.semRota:
        noRoute += route.value;
        noRouteCount++;
    }

    // Acumulado, e não `total - noRoute` no fim: subtrair dois `double` que
    // vieram de somas diferentes introduz erro onde a conta deveria ser exata.
    if (route.status != StatusRoute.semRota) {
      routeTotal += route.value;
      count++;
    }

    // Pacotes e insucessos só contam de rota que aconteceu: uma agendada com
    // pacotes estimados inflaria o denominador e faria a taxa de entrega subir
    // sem ninguém ter entregue nada.
    //
    // A guarda é por **inclusão** de propósito. Escrita por exclusão ("pula
    // agendado e andamento"), a Sem Rota entraria — e uma rota editada de
    // `concluido` para `semRota` mantém `packages` e o insucesso gravados, que
    // voltariam para a taxa de entrega sem ninguém ter entregado nada.
    if (route.status != StatusRoute.concluido &&
        route.status != StatusRoute.pago) {
      continue;
    }

    // Rota sem pacotes fica fora dos dois lados da taxa: entrar só com os
    // insucessos puxaria a taxa para baixo com um denominador que não existe.
    final routePackages = route.packages ?? 0;
    if (routePackages > 0) {
      packages += routePackages;
      failures += failuresOf(route);
    }
  }

  return PeriodSummary(
    total: total,
    // `count` e não `routes.length`: a lista carrega as idas sem rota, e elas
    // não são rotas. Deixar `routes.length` aqui é a regressão mais barata de
    // cometer — compila, e toda média e todo "ROTAS" da tela voltam a contá-las.
    count: count,
    routeTotal: routeTotal,
    packages: packages,
    failures: failures,
    pending: pending,
    received: received,
    upcoming: upcoming,
    noRoute: noRoute,
    pendingCount: pendingCount,
    receivedCount: receivedCount,
    scheduledCount: scheduledCount,
    runningCount: runningCount,
    noRouteCount: noRouteCount,
  );
}

/// Soma de `value` por empresa, **preservando o enum**.
///
/// A barra de proporção do card de resumo precisa da cor da empresa, e cor sai
/// de `companyColor(Company)` — não de um rótulo em texto.
List<({Company company, double value})> valueByCompany(
  List<NewRouteModal> routes,
) => _groupByCompany(routes, (route) => route.value);

/// Soma de `value` por empresa.
List<RankEntry> valuePerCompany(List<NewRouteModal> routes) =>
    _rankCompanies(routes, (route) => route.value);

/// Quantidade de rotas por empresa.
List<RankEntry> countPerCompany(List<NewRouteModal> routes) =>
    _rankCompanies(routes, (_) => 1);

/// Pacotes por empresa.
///
/// Rota sem `packages` informado soma **zero**, e não fica de fora: a empresa
/// continua no ranking com o que ela de fato declarou. Tirá-la mudaria o eixo
/// de "quantos pacotes rodei por empresa" para "quantos pacotes rodei nas
/// rotas em que me lembrei de anotar", que é outra pergunta.
List<RankEntry> packagesPerCompany(List<NewRouteModal> routes) =>
    _rankCompanies(routes, (route) => (route.packages ?? 0).toDouble());

/// Paradas por empresa. Mesma regra de [packagesPerCompany].
List<RankEntry> stopsPerCompany(List<NewRouteModal> routes) =>
    _rankCompanies(routes, (route) => (route.stops ?? 0).toDouble());

/// Insucessos por empresa, em quantidade absoluta.
///
/// Empresa que rodou no período aparece mesmo zerada: são três empresas, e
/// "a Shopee não deu problema nenhum" é informação, não ruído.
List<RankEntry> failuresPerCompany(List<NewRouteModal> routes) =>
    _rankCompanies(routes, (route) => failuresOf(route).toDouble());

/// Um índice de insucesso com os dois números que o formam.
///
/// Carrega [failures] e [packages] além da [rate] porque o card mostra a conta
/// junto ("6,3% — 3 de 48 pacotes"): a taxa sozinha não distingue 1 em 8 de
/// 125 em 1000, e é essa diferença que decide se vale agir.
///
/// São `double` por causa do bairro, cujos dois lados são rateados.
class FailureRate {
  const FailureRate({
    required this.label,
    required this.failures,
    required this.packages,
  });

  final String label;
  final double failures;
  final double packages;

  double get rate => packages <= 0 ? 0 : failures / packages * 100;
}

/// Índice de insucesso por empresa, em porcentagem sobre os pacotes.
///
/// "1 insucesso em 120 pacotes" e "1 em 8" não são o mesmo problema — daí a
/// taxa, e não a contagem.
///
/// Só entram rotas com `packages` preenchido. Empresa sem nenhuma rota
/// elegível fica **fora** do ranking em vez de aparecer como 0%, que afirmaria
/// um dado que não foi coletado.
List<FailureRate> failureRatePerCompany(List<NewRouteModal> routes) {
  final packages = <String, double>{};
  final failures = <String, double>{};

  for (final route in routes) {
    final routePackages = (route.packages ?? 0).toDouble();
    if (routePackages <= 0) continue;

    final label = companyLabel(route.company);
    _add(packages, label, routePackages);
    _add(failures, label, failuresOf(route).toDouble());
  }

  return _rates(packages, failures);
}

/// Índice de insucesso por bairro.
///
/// **É estimativa, não medição**, e o card diz isso: `packages` é da rota
/// inteira, não existe "pacotes do Aeroporto". Os pacotes são divididos por
/// igual entre os bairros da rota, então uma rota de 48 pacotes em 2 bairros
/// vira 24 para cada, mesmo que na prática tenham sido 40 e 8.
///
/// O numerador é melhor que o denominador: usa a distribuição de insucesso que
/// o usuário informou, e rateia só o resto — a mesma regra de
/// [failuresPerBairro].
///
/// Bairro com pacotes e sem insucesso aparece com 0%, como as outras duas
/// funções de índice: aqui o dado **foi** coletado, e "esse bairro não deu
/// problema" é resposta.
List<FailureRate> failureRatePerBairro(List<NewRouteModal> routes) {
  final packages = <String, double>{};
  final failures = <String, double>{};

  for (final route in routes) {
    final routePackages = (route.packages ?? 0).toDouble();
    if (routePackages <= 0) continue;

    final bairros = route.adress ?? const <String>[];
    if (bairros.isEmpty) continue;

    final share = routePackages / bairros.length;
    for (final bairro in bairros) {
      _add(packages, bairro, share);
      // Garante o bairro no mapa de insucesso, para 0 insucesso virar 0% em
      // vez de sumir do ranking.
      _add(failures, bairro, 0);
    }

    _attributeFailures(
      route,
      (bairro, amount) => _add(failures, bairro, amount),
    );
  }

  return _rates(packages, failures);
}

/// Quantas rotas passaram por cada bairro. Rota sem bairro não entra.
List<RankEntry> routesPerBairro(List<NewRouteModal> routes) =>
    _rankBairros(routes, (route, _) => 1);

/// Insucessos por bairro.
///
/// Usa a distribuição que o usuário informou (`insucessoPorBairro`) e **rateia
/// só o que sobrou**. A decisão é por rota:
///
/// | A rota tem | Como conta |
/// |---|---|
/// | distribuição cobrindo tudo | exato |
/// | distribuição parcial | exato + rateio do restante |
/// | nada (documento antigo) | rateio inteiro, como antes |
///
/// O rateio não morreu: é o fallback de todo documento gravado antes de existir
/// distribuição, e de quem só quis detalhar parte. Em qualquer um dos casos a
/// soma do ranking bate com o total de insucessos.
///
/// A distribuição gravada passa por [reconcileDistribution] antes de somar — o
/// que está no banco pode citar bairro que a rota não tem mais, ou passar do
/// total, e nenhum dos dois pode virar ranking.
///
/// Diferente de [failuresPerCompany], bairro sem insucesso **não** aparece:
/// são três empresas contra mais de cem bairros, e uma lista de zeros esconde
/// o que importa.
List<RankEntry> failuresPerBairro(List<NewRouteModal> routes) {
  final totals = <String, double>{};

  for (final route in routes) {
    _attributeFailures(route, (bairro, amount) {
      totals.update(bairro, (value) => value + amount, ifAbsent: () => amount);
    });
  }

  return _sorted([
    for (final entry in totals.entries)
      if (entry.value > 0) RankEntry(entry.key, entry.value),
  ]);
}

/// Distribui os insucessos de [route] pelos bairros dela, chamando [add] para
/// cada pedaço. Ver [failuresPerBairro] para a regra.
///
/// Está separado porque o índice por bairro precisa exatamente da mesma
/// atribuição — duas cópias divergiriam no primeiro ajuste do rateio.
void _attributeFailures(
  NewRouteModal route,
  void Function(String bairro, double amount) add,
) {
  final failures = failuresOf(route);
  if (failures == 0) return;

  final bairros = route.adress ?? const <String>[];
  if (bairros.isEmpty) return;

  final exact = reconcileDistribution(
    distribution: route.insucessoPorBairro,
    bairros: bairros,
    total: failures,
  );

  var attributed = 0;
  exact.forEach((bairro, qnt) {
    add(bairro, qnt.toDouble());
    attributed += qnt;
  });

  final leftover = failures - attributed;
  if (leftover > 0) {
    final share = leftover / bairros.length;
    for (final bairro in bairros) {
      add(bairro, share);
    }
  }
}

/// Insucessos por clima, em quantidade absoluta.
///
/// Sem rateio, ao contrário de [failuresPerBairro]: uma rota tem **um** clima,
/// então o insucesso dela é inteiro daquele tempo — não existe ambiguidade a
/// dividir. Rota sem clima informado fica de fora; atribuir a algum seria
/// inventar o dado.
///
/// Clima que rodou no período sem insucesso vem zerado, como em
/// [failuresPerCompany]: são poucos, e "no sol não deu problema nenhum" é
/// informação. Bairro é que fica de fora quando zerado — são mais de cem.
List<RankEntry> failuresPerWeather(List<NewRouteModal> routes) {
  final totals = <String, double>{};

  for (final route in routes) {
    final label = _weatherLabelOf(route);
    if (label == null) continue;

    final failures = failuresOf(route).toDouble();
    totals.update(label, (value) => value + failures, ifAbsent: () => failures);
  }

  return _sorted([
    for (final entry in totals.entries) RankEntry(entry.key, entry.value),
  ]);
}

/// Índice de insucesso por clima, em porcentagem sobre os pacotes.
///
/// Mesma régua de [failureRatePerCompany]: só entra rota com `packages`
/// preenchido, e clima sem nenhuma rota elegível fica **fora** em vez de
/// aparecer como 0% — que afirmaria um dado que não foi coletado.
List<FailureRate> failureRatePerWeather(List<NewRouteModal> routes) {
  final packages = <String, double>{};
  final failures = <String, double>{};

  for (final route in routes) {
    final label = _weatherLabelOf(route);
    if (label == null) continue;

    final routePackages = (route.packages ?? 0).toDouble();
    if (routePackages <= 0) continue;

    _add(packages, label, routePackages);
    _add(failures, label, failuresOf(route).toDouble());
  }

  return _rates(packages, failures);
}

void _add(Map<String, double> totals, String key, double amount) {
  totals.update(key, (value) => value + amount, ifAbsent: () => amount);
}

/// Monta os índices na ordem do pior para o melhor. Empate resolve pelo rótulo,
/// para a ordem não dançar entre dois rebuilds com os mesmos dados.
List<FailureRate> _rates(
  Map<String, double> packages,
  Map<String, double> failures,
) {
  final rates = [
    for (final entry in packages.entries)
      FailureRate(
        label: entry.key,
        failures: failures[entry.key] ?? 0,
        packages: entry.value,
      ),
  ];

  return rates..sort((a, b) {
    final byRate = b.rate.compareTo(a.rate);
    return byRate != 0 ? byRate : a.label.compareTo(b.label);
  });
}

/// Rótulo do clima da rota, ou `null` quando ela não informou.
///
/// Agrupa pelo **rótulo**, e não pelo valor do enum, de propósito: `mist` e
/// `fog` são os dois "Neblina", e por enum virariam duas barras com o mesmo
/// nome no gráfico.
String? _weatherLabelOf(NewRouteModal route) {
  final weather = route.weather;
  if (weather == null || weather.isEmpty) return null;

  // `daytimeOf`: o eixo deste gráfico é o **céu**, não a hora. "Nublado" e
  // "Noite nublada" são a mesma condição física, e separá-los partiria uma
  // população em dois degraus — metade das rotas noturnas está gravada como
  // `clouds` porque foi cadastrada antes de o app saber distinguir noite, e o
  // clima gravado nunca é reinterpretado. Com `maxBars: 4` aqui e só o
  // primeiro colocado no card de índice, o pior clima podia sair da tela por
  // ter sido dividido.
  return weatherLabel(daytimeOf(WeatherType.fromString(weather)));
}

/// Soma de `value` por dia da semana, sempre com os 7 dias.
///
/// Índice 0 é segunda e 6 é domingo, acompanhando `DateTime.weekday` (1–7) e
/// `weekdayLabel`. Os zerados ficam: buraco no gráfico de linha lê pior que
/// um vale.
List<double> valuePerWeekday(List<NewRouteModal> routes) {
  final totals = List<double>.filled(7, 0);

  for (final route in routes) {
    totals[route.startAt.weekday - 1] += route.value;
  }

  return totals;
}

/// Soma de `value` por hora de início, dentro do turno escolhido.
///
/// Devolve todas as horas do turno, inclusive as zeradas, para o eixo do
/// gráfico não mudar de tamanho conforme o movimento do dia.
List<({int hour, double value})> valuePerHour(
  List<NewRouteModal> routes,
  Shift shift,
) {
  final totals = <int, double>{
    for (var hour = shift.startHour; hour <= shift.endHour; hour++) hour: 0,
  };

  for (final route in routes) {
    final hour = route.startAt.hour;
    if (hour < shift.startHour || hour > shift.endHour) continue;

    totals[hour] = (totals[hour] ?? 0) + route.value;
  }

  return [
    for (var hour = shift.startHour; hour <= shift.endHour; hour++)
      (hour: hour, value: totals[hour] ?? 0),
  ];
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Agrupa por empresa somando [amountOf]. Empresa que aparece na lista entra
/// no resultado mesmo somando zero.
List<({Company company, double value})> _groupByCompany(
  List<NewRouteModal> routes,
  double Function(NewRouteModal route) amountOf,
) {
  final totals = <Company, double>{};

  for (final route in routes) {
    final amount = amountOf(route);
    totals.update(
      route.company,
      (value) => value + amount,
      ifAbsent: () => amount,
    );
  }

  final grouped = [
    for (final entry in totals.entries)
      (company: entry.key, value: entry.value),
  ];

  return grouped..sort((a, b) {
    final byValue = b.value.compareTo(a.value);
    return byValue != 0
        ? byValue
        : companyLabel(a.company).compareTo(companyLabel(b.company));
  });
}

List<RankEntry> _rankCompanies(
  List<NewRouteModal> routes,
  double Function(NewRouteModal route) amountOf,
) => [
  for (final entry in _groupByCompany(routes, amountOf))
    RankEntry(companyLabel(entry.company), entry.value),
];

/// Agrupa por bairro. [amountOf] recebe quantos bairros a rota tem, para quem
/// precisa ratear.
List<RankEntry> _rankBairros(
  List<NewRouteModal> routes,
  double Function(NewRouteModal route, int bairroCount) amountOf,
) {
  final totals = <String, double>{};

  for (final route in routes) {
    final bairros = route.adress ?? const <String>[];
    if (bairros.isEmpty) continue;

    final amount = amountOf(route, bairros.length);
    for (final bairro in bairros) {
      totals.update(bairro, (value) => value + amount, ifAbsent: () => amount);
    }
  }

  return _sorted([
    for (final entry in totals.entries) RankEntry(entry.key, entry.value),
  ]);
}

/// Do maior para o menor; empate resolve pelo rótulo, para a ordem não dançar
/// entre dois rebuilds com os mesmos dados.
List<RankEntry> _sorted(List<RankEntry> entries) {
  return entries..sort((a, b) {
    final byValue = b.value.compareTo(a.value);
    return byValue != 0 ? byValue : a.label.compareTo(b.label);
  });
}
