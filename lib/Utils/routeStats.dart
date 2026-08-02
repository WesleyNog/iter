import 'package:iter/Utils/insucessoBairro.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';

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
    required this.packages,
    required this.failures,
    required this.pending,
    required this.received,
    required this.upcoming,
    required this.pendingCount,
    required this.receivedCount,
    required this.scheduledCount,
    required this.runningCount,
  });

  /// Soma de `value` de **todas** as rotas recebidas — o chamador decide se
  /// passa o período inteiro ou só as realizadas.
  final double total;

  final int count;

  /// Rodado e ainda não pago (`concluido`) — o que falta cair na conta.
  final double pending;

  /// Já pago (`pago`).
  final double received;

  /// Ainda não rodado (`agendado` + `andamento`) — estimativa.
  final double upcoming;

  final int pendingCount;
  final int receivedCount;
  final int scheduledCount;
  final int runningCount;

  int get upcomingCount => scheduledCount + runningCount;

  /// O que já aconteceu, em dinheiro: pago mais a receber.
  double get realizedTotal => received + pending;

  /// Pacotes somados **apenas** das rotas que informaram o campo.
  final int packages;

  /// Insucessos das mesmas rotas contadas em [packages], para os dois lados da
  /// taxa falarem da mesma amostra.
  final int failures;

  double get average => count == 0 ? 0 : total / count;

  /// Fração do que já aconteceu que foi paga.
  ///
  /// O denominador é [realizedTotal], e não [total]: rota agendada ainda nem
  /// podia ter sido paga, e contá-la faria a taxa cair sozinha toda vez que o
  /// usuário marcasse uma rota nova na agenda.
  double? get receivedRate {
    if (realizedTotal <= 0) return null;
    return (received / realizedTotal).clamp(0.0, 1.0);
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

List<NewRouteModal> receivedPayment(List<NewRouteModal> routes) =>
    routes.where((route) => route.status == StatusRoute.pago).toList();

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
  var packages = 0;
  var failures = 0;
  var pending = 0.0;
  var received = 0.0;
  var upcoming = 0.0;
  var pendingCount = 0;
  var receivedCount = 0;
  var scheduledCount = 0;
  var runningCount = 0;

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
    }

    // Pacotes e insucessos só contam de rota que aconteceu: uma agendada com
    // pacotes estimados inflaria o denominador e faria a taxa de entrega subir
    // sem ninguém ter entregue nada.
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
    count: routes.length,
    packages: packages,
    failures: failures,
    pending: pending,
    received: received,
    upcoming: upcoming,
    pendingCount: pendingCount,
    receivedCount: receivedCount,
    scheduledCount: scheduledCount,
    runningCount: runningCount,
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

/// Insucessos por empresa, em quantidade absoluta.
///
/// Empresa que rodou no período aparece mesmo zerada: são três empresas, e
/// "a Shopee não deu problema nenhum" é informação, não ruído.
List<RankEntry> failuresPerCompany(List<NewRouteModal> routes) =>
    _rankCompanies(routes, (route) => failuresOf(route).toDouble());

/// Índice de insucesso por empresa, em porcentagem sobre os pacotes.
///
/// "1 insucesso em 120 pacotes" e "1 em 8" não são o mesmo problema — daí a
/// taxa, e não a contagem.
///
/// Só entram rotas com `packages` preenchido. Empresa sem nenhuma rota
/// elegível fica **fora** do ranking em vez de aparecer como 0%, que afirmaria
/// um dado que não foi coletado.
List<RankEntry> failureRatePerCompany(List<NewRouteModal> routes) {
  final packages = <Company, int>{};
  final failures = <Company, int>{};

  for (final route in routes) {
    final routePackages = route.packages ?? 0;
    if (routePackages <= 0) continue;

    packages.update(
      route.company,
      (value) => value + routePackages,
      ifAbsent: () => routePackages,
    );
    failures.update(
      route.company,
      (value) => value + failuresOf(route),
      ifAbsent: () => failuresOf(route),
    );
  }

  return _sorted([
    for (final entry in packages.entries)
      RankEntry(
        companyLabel(entry.key),
        (failures[entry.key] ?? 0) / entry.value * 100,
      ),
  ]);
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

  void add(String bairro, double amount) {
    totals.update(bairro, (value) => value + amount, ifAbsent: () => amount);
  }

  for (final route in routes) {
    final failures = failuresOf(route);
    if (failures == 0) continue;

    final bairros = route.adress ?? const <String>[];
    if (bairros.isEmpty) continue;

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

  return _sorted([
    for (final entry in totals.entries)
      if (entry.value > 0) RankEntry(entry.key, entry.value),
  ]);
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

  return grouped
    ..sort((a, b) {
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
