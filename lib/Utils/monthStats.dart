/// O balde mensal publicado em `profiles/{uid}/stats/{yyyy-MM}`.
///
/// É o que o Ranking lê dos amigos, porque as rotas deles são ilegíveis por
/// regra — tem dinheiro dentro. Fica separado de [ProfileStats], que é a
/// carreira inteira e responde outra pergunta: "quanto esse entregador já
/// rodou" contra "como foi o mês dele".
library;

import 'package:iter/Utils/mapRead.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/model/newRouteModal.dart';

/// `2026-08` — a chave do documento, e o que a regra valida com
/// `^[0-9]{4}-[0-9]{2}$`.
String monthKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}

/// Os números de um mês.
///
/// **Numerador e denominador, nunca a taxa.** `1 insucesso em 8 pacotes` e
/// `125 em 1000` dão a mesma porcentagem e não são o mesmo problema — é a
/// mesma razão de `FailureRate` carregar os dois números em vez do quociente.
class MonthStats {
  const MonthStats({
    this.routes = 0,
    this.packages = 0,
    this.failures = 0,
    this.timedRoutes = 0,
    this.totalMinutes = 0,
    this.timedPackages = 0,
  });

  /// Rotas realizadas (`concluido` + `pago`) no mês.
  final int routes;

  /// Só de rotas com `packages > 0` — rota sem pacotes informado fica fora
  /// dos **dois** lados da taxa.
  final int packages;

  /// `failuresOf` somado sobre a mesma população de [packages].
  final int failures;

  /// Quantas rotas têm hora de fim e duração positiva.
  final int timedRoutes;

  final int totalMinutes;

  /// Pacotes das rotas que entram em [timedRoutes] **e** têm `packages > 0`.
  ///
  /// Existe porque [packages] e [totalMinutes] contam populações diferentes —
  /// um é sobre rotas com pacotes informados, o outro sobre rotas com hora de
  /// fim. Sem um terceiro campo cruzando os dois, "minutos por pacote" seria
  /// incomputável, e o ranking de velocidade premiaria quem pega rota de 30
  /// pacotes contra quem pega de 200.
  final int timedPackages;

  /// Minutos por rota. `null` quando nenhuma rota do mês tem hora de fim —
  /// **nunca** zero, que significaria "terminou instantaneamente".
  double? get minutesPerRoute =>
      timedRoutes == 0 ? null : totalMinutes / timedRoutes;

  /// Minutos por pacote: o ritmo, e a comparação justa entre rotas de
  /// tamanhos diferentes. `null` quando não dá para calcular.
  double? get minutesPerPackage =>
      timedPackages == 0 ? null : totalMinutes / timedPackages;

  /// Percentual de insucesso sobre os pacotes. `null` sem pacotes informados.
  double? get failureRate =>
      packages == 0 ? null : failures / packages * 100;

  Map<String, dynamic> toMap() {
    return {
      'routes': routes,
      'packages': packages,
      'failures': failures,
      'timedRoutes': timedRoutes,
      'totalMinutes': totalMinutes,
      'timedPackages': timedPackages,
    };
  }

  factory MonthStats.fromMap(Map<String, dynamic> map) {
    return MonthStats(
      routes: readInt(map['routes']) ?? 0,
      packages: readInt(map['packages']) ?? 0,
      failures: readInt(map['failures']) ?? 0,
      timedRoutes: readInt(map['timedRoutes']) ?? 0,
      totalMinutes: readInt(map['totalMinutes']) ?? 0,
      timedPackages: readInt(map['timedPackages']) ?? 0,
    );
  }
}

/// O balde de **um** mês, a partir da lista inteira de rotas.
///
/// Recalculado, nunca incrementado: `FieldValue.increment` derivaria na
/// primeira rota editada ou apagada, e um número público que discorda da
/// origem, sem ninguém conseguir auditar, é pior do que número nenhum. O
/// cliente já tem a coleção toda em memória, então a passada é de graça.
MonthStats monthStatsOf(List<NewRouteModal> all, DateTime month) {
  final key = monthKey(month);

  var routes = 0;
  var packages = 0;
  var failures = 0;
  var timedRoutes = 0;
  var totalMinutes = 0;
  var timedPackages = 0;

  // `realized` é a mesma régua dos gráficos: uma rota agendada com pacotes
  // estimados inflaria o denominador sem ninguém ter entregado nada.
  for (final route in realized(all)) {
    if (monthKey(route.startAt) != key) continue;

    routes++;

    final routePackages = route.packages ?? 0;
    if (routePackages > 0) {
      packages += routePackages;
      failures += failuresOf(route);
    }

    final end = route.endAt;
    if (end == null) continue;

    // Duração negativa é documento corrompido, não rota de madrugada:
    // `RouteTime.resolveEnd` já rola a virada do dia na gravação.
    final duration = end.difference(route.startAt);
    if (duration <= Duration.zero) continue;

    timedRoutes++;
    totalMinutes += duration.inMinutes;
    if (routePackages > 0) timedPackages += routePackages;
  }

  return MonthStats(
    routes: routes,
    packages: packages,
    failures: failures,
    timedRoutes: timedRoutes,
    totalMinutes: totalMinutes,
    timedPackages: timedPackages,
  );
}

/// Os baldes da janela que termina em [reference], do mais antigo ao mais
/// recente, chaveados por `yyyy-MM`.
///
/// Devolve a janela **inteira**, inclusive os meses zerados. Escrever o zero
/// custa um documento e evita dois problemas: um mês que esvaziou (todas as
/// rotas apagadas) deixaria documento velho para sempre, e o Ranking de um mês
/// parado mostraria "sem dados" em vez de "zero rotas", que são coisas
/// diferentes.
Map<String, MonthStats> monthlyStats(
  List<NewRouteModal> all, {
  required DateTime reference,
  int months = 12,
}) {
  final buckets = <String, MonthStats>{};

  for (var back = months - 1; back >= 0; back--) {
    // `DateTime(ano, mês - n)` normaliza a virada do ano sozinho.
    final month = DateTime(reference.year, reference.month - back);
    buckets[monthKey(month)] = monthStatsOf(all, month);
  }

  return buckets;
}
