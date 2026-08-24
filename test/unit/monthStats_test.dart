import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/monthStats.dart';
import 'package:iter/model/newRouteModal.dart';

NewRouteModal _route({
  required String startAt,
  String? endAt,
  StatusRoute status = StatusRoute.concluido,
  int? packages,
  int? stops,
  bool? isInsucesso,
  int? insucessoQnt,
}) {
  final start = DateTime.parse(startAt);
  return NewRouteModal(
    id: startAt,
    company: Company.mercadolivre,
    dateRoute:
        '${start.day.toString().padLeft(2, '0')}/'
        '${start.month.toString().padLeft(2, '0')}/${start.year}',
    weekday: start.weekday,
    status: status,
    value: 200,
    packages: packages,
    stops: stops,
    startAt: start,
    endAt: endAt == null ? null : DateTime.parse(endAt),
    isInsucesso: isInsucesso,
    insucessoQnt: insucessoQnt,
    createdAt: startAt,
  );
}

void main() {
  group('monthKey', () {
    test('formata com dois dígitos, como a regra exige', () {
      expect(monthKey(DateTime(2026, 8, 7)), '2026-08');
      expect(monthKey(DateTime(2026, 12, 31)), '2026-12');
      expect(monthKey(DateTime(2026, 1, 1)), '2026-01');
    });
  });

  group('monthStatsOf — o balde de um mês', () {
    test('conta só as rotas do mês pedido', () {
      final rotas = [
        _route(startAt: '2026-08-01T08:00:00'),
        _route(startAt: '2026-08-31T08:00:00'),
        _route(startAt: '2026-07-31T08:00:00'),
        _route(startAt: '2026-09-01T08:00:00'),
      ];

      expect(monthStatsOf(rotas, DateTime(2026, 8)).routes, 2);
    });

    test('a ida sem rota não entra nos números públicos', () {
      // Este arquivo é o balde que os **amigos** leem em
      // `profiles/{uid}/stats/{yyyy-MM}`, e nenhuma linha dele mudou por causa
      // da Sem Rota — o filtro é `realized`, que continua sendo `concluido` +
      // `pago`. O teste existe para que "consertar" `monthStatsOf` para usar
      // `receivedPayment` fique vermelho aqui, e não errado na tela de outra
      // pessoa.
      final rotas = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T16:00:00',
          stops: 60,
        ),
        _route(
          startAt: '2026-08-02T08:00:00',
          // Uma ida curta, e é justamente a duração que ela distorceria: 40
          // minutos entrando na média puxaria "tempo médio por rota" para
          // baixo e faria parecer que as rotas ficaram mais rápidas. No ritmo
          // seria pior ainda: 400 paradas que ninguém fez em 40 minutos dariam
          // 0,1 min/parada, e o campeão do mês seria a rota que não houve.
          endAt: '2026-08-02T08:40:00',
          status: StatusRoute.semRota,
          packages: 500,
          stops: 400,
          isInsucesso: true,
          insucessoQnt: 60,
        ),
      ];

      final stats = monthStatsOf(rotas, DateTime(2026, 8));

      expect(stats.routes, 1);
      expect(stats.packages, 0);
      expect(stats.failures, 0);
      expect(stats.pacedRoutes, 1);
      expect(stats.pacedMinutes, 480);
      expect(stats.pacedStops, 60);
      expect(stats.minutesPerStop, 8);
    });

    test('só rota realizada entra', () {
      // Uma agendada com pacotes estimados inflaria o denominador sem ninguém
      // ter entregado nada — a mesma régua de `realized`.
      final rotas = [
        _route(startAt: '2026-08-01T08:00:00', status: StatusRoute.concluido),
        _route(startAt: '2026-08-02T08:00:00', status: StatusRoute.pago),
        _route(startAt: '2026-08-03T08:00:00', status: StatusRoute.agendado),
        _route(startAt: '2026-08-04T08:00:00', status: StatusRoute.andamento),
      ];

      expect(monthStatsOf(rotas, DateTime(2026, 8)).routes, 2);
    });

    test('rota sem pacotes fica fora dos dois lados da taxa', () {
      final rotas = [
        _route(
          startAt: '2026-08-01T08:00:00',
          packages: 100,
          isInsucesso: true,
          insucessoQnt: 3,
        ),
        _route(startAt: '2026-08-02T08:00:00', isInsucesso: true),
      ];

      final balde = monthStatsOf(rotas, DateTime(2026, 8));
      expect(balde.routes, 2);
      expect(balde.packages, 100);
      expect(balde.failures, 3);
      expect(balde.failureRate, 3);
      // E a amostra da taxa é uma rota, não duas: é ela que o mínimo do
      // ranking cobra desde que parou de contar as rotas do mês.
      expect(balde.packagedRoutes, 1);
    });

    test('rota sem hora de fim não entra no tempo', () {
      final rotas = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T16:00:00',
          packages: 80,
          stops: 60,
        ),
        _route(startAt: '2026-08-02T08:00:00', packages: 120, stops: 90),
      ];

      final balde = monthStatsOf(rotas, DateTime(2026, 8));
      expect(balde.routes, 2);
      // Os pacotes das duas contam para a taxa...
      expect(balde.packages, 200);
      expect(balde.packagedRoutes, 2);
      // ...e só as paradas da rota cronometrada contam para o ritmo. As 90
      // paradas da outra não têm tempo medido para dividir.
      expect(balde.pacedRoutes, 1);
      expect(balde.pacedStops, 60);
      expect(balde.minutesPerStop, 8);
    });

    test('o ritmo é o que torna rota grande e rota curta comparáveis', () {
      // O caso que motivou a troca: 200 pacotes em 8h contra 30 em 2h. Por
      // duração média, a rota pequena ganha por larga margem; por ritmo,
      // perde — que é o que aconteceu de verdade.
      final rotas = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T16:00:00',
          packages: 200,
          stops: 150,
        ),
      ];
      final pequena = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T10:00:00',
          packages: 30,
          stops: 25,
        ),
      ];

      final grande = monthStatsOf(rotas, DateTime(2026, 8));
      final curta = monthStatsOf(pequena, DateTime(2026, 8));

      // Pela duração — 480 minutos contra 120 — a curta liderava com folga...
      expect(grande.pacedMinutes, 480);
      expect(curta.pacedMinutes, 120);
      // ...e pelo ritmo a ordem se inverte.
      expect(grande.minutesPerStop, 3.2);
      expect(curta.minutesPerStop, 4.8);
    });

    test('minutos e paradas do ritmo saem da mesma rota', () {
      // O defeito que o par separado existe para impedir: uma rota
      // cronometrada **sem** paradas informadas tem duração e não tem
      // denominador. Somando os 240 minutos dela, o mês daria 720/100 = 7,2
      // min/parada — um ritmo que não é o de nenhuma das duas rotas, e pior
      // que o verdadeiro.
      final rotas = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T16:00:00',
          stops: 100,
        ),
        _route(startAt: '2026-08-02T08:00:00', endAt: '2026-08-02T12:00:00'),
      ];

      final balde = monthStatsOf(rotas, DateTime(2026, 8));

      expect(balde.routes, 2);
      expect(balde.pacedRoutes, 1);
      expect(balde.pacedMinutes, 480);
      expect(balde.pacedStops, 100);
      expect(balde.minutesPerStop, 4.8);
    });

    test('rota de menos de um minuto não leva as paradas dela', () {
      // Duração positiva, `inMinutes` zero: sem a guarda, as 30 paradas
      // entrariam no denominador sem um minuto sequer no numerador, e o mês
      // inteiro ficaria mais rápido do que foi.
      final rotas = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T16:00:00',
          stops: 100,
        ),
        _route(
          startAt: '2026-08-02T08:00:00',
          endAt: '2026-08-02T08:00:30',
          stops: 30,
        ),
      ];

      final balde = monthStatsOf(rotas, DateTime(2026, 8));

      expect(balde.pacedRoutes, 1);
      expect(balde.pacedStops, 100);
      expect(balde.minutesPerStop, 4.8);
    });

    test('rota que virou o dia tem duração real', () {
      final rotas = [
        _route(
          startAt: '2026-08-01T22:00:00',
          endAt: '2026-08-02T02:00:00',
          packages: 40,
          stops: 30,
        ),
      ];

      final balde = monthStatsOf(rotas, DateTime(2026, 8));
      expect(balde.pacedMinutes, 240);
      expect(balde.minutesPerStop, 8);
    });

    test('duração não positiva é descartada, não somada negativa', () {
      final rotas = [
        _route(
          startAt: '2026-08-01T10:00:00',
          endAt: '2026-08-01T08:00:00',
          packages: 40,
          stops: 30,
        ),
      ];

      final balde = monthStatsOf(rotas, DateTime(2026, 8));
      expect(balde.pacedRoutes, 0);
      expect(balde.pacedMinutes, 0);
      expect(balde.pacedStops, 0);
      expect(balde.minutesPerStop, isNull);
    });

    test('mês sem rota é zero, e as taxas são nulas', () {
      final balde = monthStatsOf([], DateTime(2026, 8));

      expect(balde.routes, 0);
      // Zero rotas é resposta; taxa de zero pacotes não é.
      expect(balde.failureRate, isNull);
      expect(balde.minutesPerStop, isNull);
    });
  });

  group('monthlyStats — a janela', () {
    test('devolve a janela inteira, zeros incluídos', () {
      final baldes = monthlyStats([
        _route(startAt: '2026-08-01T08:00:00'),
      ], reference: DateTime(2026, 8, 7));

      expect(baldes.length, 12);
      expect(baldes['2026-08']!.routes, 1);
      expect(baldes['2026-03']!.routes, 0);
    });

    test('a janela vira o ano sozinha', () {
      final baldes = monthlyStats(
        [_route(startAt: '2025-10-05T08:00:00')],
        reference: DateTime(2026, 2, 15),
        months: 6,
      );

      expect(baldes.keys.toList(), [
        '2025-09',
        '2025-10',
        '2025-11',
        '2025-12',
        '2026-01',
        '2026-02',
      ]);
      expect(baldes['2025-10']!.routes, 1);
    });

    test('rota fora da janela não entra em balde nenhum', () {
      final baldes = monthlyStats([
        _route(startAt: '2024-01-05T08:00:00'),
      ], reference: DateTime(2026, 8, 7));

      expect(baldes.values.every((balde) => balde.routes == 0), isTrue);
    });
  });

  group('MonthStats — a travessia', () {
    test('ida e volta preserva os sete contadores', () {
      const original = MonthStats(
        routes: 22,
        packages: 3400,
        failures: 41,
        packagedRoutes: 20,
        pacedRoutes: 18,
        pacedMinutes: 8640,
        pacedStops: 1440,
      );

      final volta = MonthStats.fromMap(original.toMap());

      expect(volta.routes, 22);
      expect(volta.packages, 3400);
      expect(volta.failures, 41);
      expect(volta.packagedRoutes, 20);
      expect(volta.pacedRoutes, 18);
      expect(volta.pacedMinutes, 8640);
      expect(volta.pacedStops, 1440);
      expect(volta.minutesPerStop, 6);
    });

    test('o documento não carrega mais a média por rota', () {
      // `timedRoutes` e `totalMinutes` saíram quando o Ranking parou de
      // ordenar por eles: campo público sem leitor é número que um dia
      // discorda da origem sem ninguém perceber. A duração que as telas
      // mostram vem da própria rota e de `stats/all`.
      final gravado = const MonthStats(routes: 5).toMap();

      expect(gravado.containsKey('timedRoutes'), isFalse);
      expect(gravado.containsKey('totalMinutes'), isFalse);
      expect(gravado.containsKey('timedPackages'), isFalse);
      expect(gravado.keys, hasLength(7));
    });

    test('documento vazio vira mês parado, não mês quebrado', () {
      final volta = MonthStats.fromMap({});

      expect(volta.routes, 0);
      expect(volta.failureRate, isNull);
      expect(volta.minutesPerStop, isNull);
    });

    test('balde antigo não tem ritmo, e não inventa um', () {
      // O documento que o amigo publicou antes desta versão: tem os campos de
      // tempo, não tem os de ritmo. `null` é a resposta certa — ele vai para o
      // rodapé "ainda sem amostra" até reabrir o app, e não para o topo com um
      // número tirado de duas populações diferentes.
      final volta = MonthStats.fromMap(const {
        'routes': 17,
        'packages': 573,
        'failures': 22,
        'timedRoutes': 17,
        'totalMinutes': 2873,
        'timedPackages': 573,
      });

      // Os campos que saíram são ignorados na leitura, sem lançar...
      expect(volta.routes, 17);
      expect(volta.failureRate, closeTo(3.84, 0.01));
      // ...e o ritmo é `null`, que é a verdade: este documento não tem de onde
      // tirar o número.
      expect(volta.minutesPerStop, isNull);
      expect(volta.pacedRoutes, 0);
    });

    test('balde antigo cai na régua antiga do insucesso, não em zero', () {
      // `packagedRoutes` ausente é "documento velho", não "nenhuma rota com
      // pacotes": cair em zero jogaria para o rodapé quem tem 17 rotas com
      // pacotes preenchidos, e a tela pareceria quebrada.
      final volta = MonthStats.fromMap(const {
        'routes': 17,
        'packages': 573,
        'failures': 22,
      });

      expect(volta.packagedRoutes, 17);

      // E zero escrito de propósito continua sendo zero.
      final zerado = MonthStats.fromMap(const {
        'routes': 17,
        'packages': 0,
        'failures': 0,
        'packagedRoutes': 0,
      });
      expect(zerado.packagedRoutes, 0);
    });
  });
}
