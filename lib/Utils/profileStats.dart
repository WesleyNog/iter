import 'package:iter/Utils/routeStats.dart';
import 'package:iter/model/newRouteModal.dart';

/// Números de carreira do perfil — todas as rotas já rodadas, sem filtro de
/// período.
///
/// Fica separado de `routeStats.dart` de propósito: lá tudo é sobre **um
/// período** e as funções recebem uma lista já filtrada. Aqui é a carreira
/// inteira, e entram coisas que os gráficos não usam (paradas, duração média).
/// O que dá para reusar é importado, não copiado.

/// Empresa que o entregador mais rodou, com a fatia que ela representa.
typedef TopCompany = ({String label, double share});

/// Um `null` neste objeto significa **"não dá para calcular"**, nunca zero.
///
/// "Taxa de insucesso 0%" e "ninguém preencheu pacotes, então não há taxa" são
/// coisas diferentes — mostrar zero nas duas mentiria na primeira semana de
/// uso.
class ProfileStats {
  const ProfileStats({
    required this.routes,
    required this.deliveredPackages,
    required this.stops,
    this.failureRate,
    this.topCompany,
    this.averageDuration,
  });

  /// Rotas realizadas (`concluido` + `pago`).
  final int routes;

  /// Pacotes carregados menos os insucessos.
  final int deliveredPackages;

  final int stops;

  /// Percentual de insucesso sobre os pacotes. `null` sem pacotes informados.
  final double? failureRate;

  final TopCompany? topCompany;

  /// Média de `endAt - startAt`. `null` quando nenhuma rota tem hora de fim.
  final Duration? averageDuration;
}

ProfileStats profileStats(List<NewRouteModal> all) {
  // Rota agendada não entregou pacote nem passou por parada nenhuma.
  final done = realized(all);

  var packages = 0;
  var failures = 0;
  var stops = 0;
  var totalMinutes = 0;
  var timedRoutes = 0;

  for (final route in done) {
    // Rota sem pacotes fica fora dos dois lados: o insucesso dela não teria de
    // onde ser descontado, e entraria só puxando a taxa para baixo.
    final routePackages = route.packages ?? 0;
    if (routePackages > 0) {
      packages += routePackages;
      failures += failuresOf(route);
    }

    stops += route.stops ?? 0;

    final end = route.endAt;
    if (end != null) {
      final duration = end.difference(route.startAt);
      // Duração negativa é documento corrompido, não rota de madrugada:
      // `RouteTime.resolveEnd` já rola a virada do dia na gravação.
      if (duration > Duration.zero) {
        totalMinutes += duration.inMinutes;
        timedRoutes++;
      }
    }
  }

  return ProfileStats(
    routes: done.length,
    // Insucesso maior que o carregado só sai de dado corrompido, mas "-3
    // pacotes entregues" na tela é pior que arredondar para zero.
    deliveredPackages: (packages - failures).clamp(0, packages),
    stops: stops,
    failureRate: packages == 0 ? null : failures / packages * 100,
    topCompany: _topCompany(done),
    averageDuration: timedRoutes == 0
        ? null
        : Duration(minutes: totalMinutes ~/ timedRoutes),
  );
}

/// `countPerCompany` já ordena por quantidade e desempata pelo nome, então o
/// rótulo não muda entre dois rebuilds com os mesmos dados.
TopCompany? _topCompany(List<NewRouteModal> done) {
  if (done.isEmpty) return null;

  final ranking = countPerCompany(done);
  if (ranking.isEmpty) return null;

  final first = ranking.first;
  return (label: first.label, share: first.value / done.length * 100);
}
