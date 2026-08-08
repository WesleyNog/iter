import 'package:iter/Utils/mapRead.dart';
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

  /// Vira `profiles/{uid}/stats/all`, para outro entregador poder ler.
  ///
  /// A travessia **não é simétrica**, e é de propósito: `topCompany` é um
  /// record e vira dois campos, `averageDuration` vira minutos. Mexer no
  /// construtor para espelhar o documento custaria cinco usos e um teste, e o
  /// documento não é o modelo.
  ///
  /// `updatedAt` não sai daqui: quem grava é que carimba. Uma instância
  /// calculada não tem de onde tirar a hora da escrita.
  Map<String, dynamic> toMap() {
    return {
      'routes': routes,
      'deliveredPackages': deliveredPackages,
      'stops': stops,
      'failureRate': failureRate,
      'topCompanyLabel': topCompany?.label,
      'topCompanyShare': topCompany?.share,
      'averageMinutes': averageDuration?.inMinutes,
    };
  }

  /// **Campo ausente volta `null`, nunca `0`.**
  ///
  /// É a mesma regra do construtor, e é na travessia que ela corre risco:
  /// gravar ou ler `0` faria "taxa de insucesso zero" e "ninguém preencheu
  /// pacotes" virarem a mesma coisa — justamente onde o número fica público e
  /// alguém compara com o próprio.
  ///
  /// As contagens caem para `0` porque lá zero é resposta: conta nova rodou
  /// zero rotas mesmo.
  factory ProfileStats.fromMap(Map<String, dynamic> map) {
    final label = map['topCompanyLabel'] as String?;
    final share = readDouble(map['topCompanyShare']);
    final minutes = readInt(map['averageMinutes']);

    return ProfileStats(
      routes: readInt(map['routes']) ?? 0,
      deliveredPackages: readInt(map['deliveredPackages']) ?? 0,
      stops: readInt(map['stops']) ?? 0,
      failureRate: readDouble(map['failureRate']),
      // Meia empresa não é empresa: sem os dois campos não há o que mostrar.
      topCompany: label == null || share == null
          ? null
          : (label: label, share: share),
      averageDuration: minutes == null ? null : Duration(minutes: minutes),
    );
  }
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
