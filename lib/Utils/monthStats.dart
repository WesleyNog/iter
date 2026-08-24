/// O balde mensal publicado em `profiles/{uid}/stats/{yyyy-MM}`.
///
/// É o que o Ranking lê dos amigos, porque as rotas deles são ilegíveis por
/// regra — tem dinheiro dentro. Fica separado de [ProfileStats], que é a
/// carreira inteira e responde outra pergunta: "quanto esse entregador já
/// rodou" contra "como foi o mês dele".
library;

import 'package:iter/Utils/mapRead.dart';
import 'package:iter/Utils/routePace.dart';
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
///
/// **Cada média carrega a própria população, e as duas não coincidem:** rotas
/// com pacotes informados de um lado, rotas com hora de fim **e** paradas do
/// outro. Um par de contadores por média é o que impede a conta que mistura as
/// duas — dividir os minutos de todas as rotas cronometradas pelas paradas de
/// algumas produz um ritmo que não é o de ninguém, e era o defeito do
/// `minutesPerPackage` que estes campos aposentam.
class MonthStats {
  const MonthStats({
    this.routes = 0,
    this.packages = 0,
    this.failures = 0,
    this.packagedRoutes = 0,
    this.pacedRoutes = 0,
    this.pacedMinutes = 0,
    this.pacedStops = 0,
  });

  /// Rotas realizadas (`concluido` + `pago`) no mês.
  final int routes;

  /// Só de rotas com `packages > 0` — rota sem pacotes informado fica fora
  /// dos **dois** lados da taxa.
  final int packages;

  /// `failuresOf` somado sobre a mesma população de [packages].
  final int failures;

  /// Quantas rotas formam [failureRate] — a amostra que o ranking cobra.
  ///
  /// Sem ele o mínimo do ranking media a coisa errada: a taxa sai das rotas
  /// com pacotes, e a porta olhava [routes]. Quem tinha 40 rotas no mês e
  /// pacotes preenchidos em **uma** disputava com amostra de uma rota, e a
  /// linha ainda dizia "40 rotas" embaixo do número.
  final int packagedRoutes;

  /// Rotas com hora de fim **e** paradas informadas — a população do ritmo, e
  /// a amostra que o mínimo do ranking cobra.
  ///
  /// Uma rota cronometrada sem paradas informadas **não** entra aqui, e é essa
  /// recusa que mantém numerador e denominador descrevendo o mesmo conjunto.
  /// Ver `pacedOf` em `Utils/routePace.dart`, que é onde a regra mora.
  final int pacedRoutes;

  /// Minutos das rotas de [pacedRoutes].
  final int pacedMinutes;

  /// Paradas das rotas de [pacedRoutes].
  final int pacedStops;

  /// **O ritmo: minutos por parada.** É o que o Ranking ordena.
  ///
  /// A média por rota premiava a rota pequena: quem pega 30 pacotes em 2h
  /// aparecia na frente de quem pega 200 em 8h, tendo sido menos produtivo.
  /// Dividir pela quantidade de paradas é o que torna comparável quem pegou
  /// rota grande com quem pegou rota curta. Ver `Utils/routePace.dart`.
  ///
  /// O balde **não guarda mais** `timedRoutes`/`totalMinutes`, que eram a média
  /// por rota. Eles ficaram sem leitor no instante em que o Ranking deixou de
  /// ordenar por eles — a duração que as telas mostram vem da própria rota (o
  /// card) e de `stats/all` (o dialog de perfil), não daqui. Voltam em uma
  /// linha no dia em que alguma tela pedir a duração média do mês *de um
  /// amigo*: a janela de doze meses é reescrita a cada abertura do app, então
  /// campo novo se preenche sozinho e não há migração de que fugir.
  double? get minutesPerStop => paceFrom(pacedMinutes, pacedStops);

  /// Percentual de insucesso sobre os pacotes. `null` sem pacotes informados.
  double? get failureRate => packages == 0 ? null : failures / packages * 100;

  Map<String, dynamic> toMap() {
    return {
      'routes': routes,
      'packages': packages,
      'failures': failures,
      'packagedRoutes': packagedRoutes,
      'pacedRoutes': pacedRoutes,
      'pacedMinutes': pacedMinutes,
      'pacedStops': pacedStops,
    };
  }

  factory MonthStats.fromMap(Map<String, dynamic> map) {
    final routes = readInt(map['routes']) ?? 0;

    return MonthStats(
      routes: routes,
      packages: readInt(map['packages']) ?? 0,
      failures: readInt(map['failures']) ?? 0,
      // **Ausente é documento velho, não zero.** O balde escrito antes deste
      // campo existir não sabia quantas rotas tinham pacotes; cair em [routes]
      // é a régua com que ele foi escrito, e ela volta sozinha à régua nova na
      // próxima vez que o dono abrir o app. Cair em zero jogaria todo mundo
      // para o rodapé "ainda sem amostra" — que parece defeito, e não é o que
      // o documento diz.
      packagedRoutes: readInt(map['packagedRoutes']) ?? routes,
      // Aqui **não** há régua antiga em que cair: o documento velho não tem de
      // onde tirar quantas paradas foram feitas nas rotas cronometradas. Zero
      // vira `minutesPerStop == null`, que é a verdade — "não dá para
      // calcular" — e o amigo aparece no rodapé até reabrir o app dele.
      pacedRoutes: readInt(map['pacedRoutes']) ?? 0,
      pacedMinutes: readInt(map['pacedMinutes']) ?? 0,
      pacedStops: readInt(map['pacedStops']) ?? 0,
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
  var packagedRoutes = 0;
  var pacedRoutes = 0;
  var pacedMinutes = 0;
  var pacedStops = 0;

  // `realized` é a mesma régua dos gráficos: uma rota agendada com pacotes
  // estimados inflaria o denominador sem ninguém ter entregado nada.
  for (final route in realized(all)) {
    if (monthKey(route.startAt) != key) continue;

    routes++;

    final routePackages = route.packages ?? 0;
    if (routePackages > 0) {
      packagedRoutes++;
      packages += routePackages;
      failures += failuresOf(route);
    }

    // Quem decide se a rota tem ritmo é `pacedOf`, e não este laço: a mesma
    // regra vale para o card da rota e para a carreira, e uma cópia aqui
    // divergiria no dia em que uma das três mudasse.
    final paced = pacedOf(route);
    if (paced == null) continue;

    pacedRoutes++;
    pacedMinutes += paced.minutes;
    pacedStops += paced.stops;
  }

  return MonthStats(
    routes: routes,
    packages: packages,
    failures: failures,
    packagedRoutes: packagedRoutes,
    pacedRoutes: pacedRoutes,
    pacedMinutes: pacedMinutes,
    pacedStops: pacedStops,
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
