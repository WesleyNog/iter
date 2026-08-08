import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/monthStats.dart';
import 'package:iter/model/newRouteModal.dart';

NewRouteModal _route({
  required String startAt,
  String? endAt,
  StatusRoute status = StatusRoute.concluido,
  int? packages,
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
    });

    test('rota sem hora de fim não entra no tempo', () {
      final rotas = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T16:00:00',
          packages: 80,
        ),
        _route(startAt: '2026-08-02T08:00:00', packages: 120),
      ];

      final balde = monthStatsOf(rotas, DateTime(2026, 8));
      expect(balde.routes, 2);
      expect(balde.timedRoutes, 1);
      expect(balde.totalMinutes, 480);
      // Os pacotes das duas contam para a taxa...
      expect(balde.packages, 200);
      // ...mas só os da rota cronometrada contam para o ritmo.
      expect(balde.timedPackages, 80);
    });

    test('timedPackages é o que torna o ritmo comparável', () {
      // O caso que o campo existe para resolver: 200 pacotes em 8h contra 30
      // em 2h. Por duração média, a rota pequena ganha; por ritmo, perde.
      final rotas = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T16:00:00',
          packages: 200,
        ),
      ];
      final pequena = [
        _route(
          startAt: '2026-08-01T08:00:00',
          endAt: '2026-08-01T10:00:00',
          packages: 30,
        ),
      ];

      final grande = monthStatsOf(rotas, DateTime(2026, 8));
      final curta = monthStatsOf(pequena, DateTime(2026, 8));

      expect(grande.minutesPerRoute, 480);
      expect(curta.minutesPerRoute, 120);
      expect(grande.minutesPerPackage, 2.4);
      expect(curta.minutesPerPackage, 4);
    });

    test('rota que virou o dia tem duração real', () {
      final rotas = [
        _route(
          startAt: '2026-08-01T22:00:00',
          endAt: '2026-08-02T02:00:00',
          packages: 40,
        ),
      ];

      expect(monthStatsOf(rotas, DateTime(2026, 8)).totalMinutes, 240);
    });

    test('duração não positiva é descartada, não somada negativa', () {
      final rotas = [
        _route(
          startAt: '2026-08-01T10:00:00',
          endAt: '2026-08-01T08:00:00',
          packages: 40,
        ),
      ];

      final balde = monthStatsOf(rotas, DateTime(2026, 8));
      expect(balde.timedRoutes, 0);
      expect(balde.totalMinutes, 0);
      expect(balde.timedPackages, 0);
    });

    test('mês sem rota é zero, e as taxas são nulas', () {
      final balde = monthStatsOf([], DateTime(2026, 8));

      expect(balde.routes, 0);
      // Zero rotas é resposta; taxa de zero pacotes não é.
      expect(balde.failureRate, isNull);
      expect(balde.minutesPerRoute, isNull);
      expect(balde.minutesPerPackage, isNull);
    });
  });

  group('monthlyStats — a janela', () {
    test('devolve a janela inteira, zeros incluídos', () {
      final baldes = monthlyStats(
        [_route(startAt: '2026-08-01T08:00:00')],
        reference: DateTime(2026, 8, 7),
      );

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
      final baldes = monthlyStats(
        [_route(startAt: '2024-01-05T08:00:00')],
        reference: DateTime(2026, 8, 7),
      );

      expect(baldes.values.every((balde) => balde.routes == 0), isTrue);
    });
  });

  group('MonthStats — a travessia', () {
    test('ida e volta preserva os seis contadores', () {
      const original = MonthStats(
        routes: 22,
        packages: 3400,
        failures: 41,
        timedRoutes: 19,
        totalMinutes: 9120,
        timedPackages: 2980,
      );

      final volta = MonthStats.fromMap(original.toMap());

      expect(volta.routes, 22);
      expect(volta.packages, 3400);
      expect(volta.failures, 41);
      expect(volta.timedRoutes, 19);
      expect(volta.totalMinutes, 9120);
      expect(volta.timedPackages, 2980);
    });

    test('documento vazio vira mês parado, não mês quebrado', () {
      final volta = MonthStats.fromMap({});

      expect(volta.routes, 0);
      expect(volta.failureRate, isNull);
      expect(volta.minutesPerPackage, isNull);
    });
  });
}
