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
  });

  /// Soma de `value` das rotas do período.
  final double total;

  final int count;

  /// Pacotes somados **apenas** das rotas que informaram o campo.
  final int packages;

  /// Insucessos das mesmas rotas contadas em [packages], para os dois lados da
  /// taxa falarem da mesma amostra.
  final int failures;

  double get average => count == 0 ? 0 : total / count;

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

/// Rotas realizadas (`concluido` ou `pago`) com início dentro do período.
///
/// A comparação é por data, com as duas pontas inclusive: a hora que vier em
/// [start]/[end] é ignorada, senão uma rota das 22h sumiria do último dia do
/// filtro.
///
/// O recorte de status vale para a tela inteira, e não só para os números de
/// dinheiro: rota agendada é previsão, e bairro "rodado" numa rota que ainda
/// não aconteceu também não é verdade.
List<NewRouteModal> realizedInPeriod(
  List<NewRouteModal> routes, {
  required DateTime start,
  required DateTime end,
}) {
  final from = _dateOnly(start);
  final to = _dateOnly(end);

  return routes.where((route) {
    if (route.status != StatusRoute.concluido &&
        route.status != StatusRoute.pago) {
      return false;
    }

    final day = _dateOnly(route.startAt);
    return !day.isBefore(from) && !day.isAfter(to);
  }).toList();
}

PeriodSummary summarize(List<NewRouteModal> routes) {
  var total = 0.0;
  var packages = 0;
  var failures = 0;

  for (final route in routes) {
    total += route.value;

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

/// Insucessos por bairro, **rateados** entre os bairros da rota.
///
/// O dado de qual bairro falhou não existe: a rota tem vários bairros e um
/// único `insucessoQnt`. Ratear (3 insucessos em 3 bairros = 1,0 para cada)
/// mantém o total do ranking igual ao total real e não premia rota com muitos
/// bairros — ao custo de número fracionado.
///
/// Diferente de [failuresPerCompany], bairro sem insucesso **não** aparece:
/// são três empresas contra mais de cem bairros, e uma lista de zeros esconde
/// o que importa.
List<RankEntry> failuresPerBairro(List<NewRouteModal> routes) {
  final ranking = _rankBairros(
    routes,
    (route, bairroCount) => failuresOf(route) / bairroCount,
  );

  return ranking.where((entry) => entry.value > 0).toList();
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
