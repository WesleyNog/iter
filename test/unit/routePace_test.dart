import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routePace.dart';
import 'package:iter/model/newRouteModal.dart';

NewRouteModal _route({
  required DateTime startAt,
  DateTime? endAt,
  int? stops,
  StatusRoute status = StatusRoute.concluido,
}) {
  return NewRouteModal(
    id: 'r1',
    company: Company.mercadolivre,
    dateRoute:
        '${startAt.day.toString().padLeft(2, '0')}/'
        '${startAt.month.toString().padLeft(2, '0')}/${startAt.year}',
    weekday: startAt.weekday,
    status: status,
    value: 121,
    stops: stops,
    startAt: startAt,
    endAt: endAt,
    createdAt: startAt.toIso8601String(),
  );
}

void main() {
  group('paceFrom — a divisão, e o que ela recusa', () {
    test('minutos por parada', () {
      expect(paceFrom(245, 28), closeTo(8.75, 0.001));
      expect(paceFrom(480, 100), 4.8);
    });

    test('sem parada não há ritmo — e ritmo não é zero', () {
      // Zero coroaria campeão quem não preencheu nada: o ranking ordena do
      // menor para o maior.
      expect(paceFrom(480, 0), isNull);
      expect(paceFrom(480, -3), isNull);
    });

    test('sem minutos não há ritmo', () {
      expect(paceFrom(0, 100), isNull);
      expect(paceFrom(-60, 100), isNull);
    });
  });

  group('paceOf — o ritmo de uma rota', () {
    test('a rota da tela: 12:21 às 16:26 com 28 paradas', () {
      final pace = paceOf(
        _route(
          startAt: DateTime(2026, 8, 7, 12, 21),
          endAt: DateTime(2026, 8, 7, 16, 26),
          stops: 28,
        ),
      );

      // 4h05 = 245 minutos.
      expect(pace, closeTo(8.75, 0.001));
      expect(formatPace(pace!), '8,8 min/parada');
    });

    test('rota que virou o dia tem ritmo real, não negativo', () {
      // `RouteTime.resolveEnd` já rolou o fim para o dia seguinte na gravação;
      // aqui a conta só não pode desfazer isso.
      final pace = paceOf(
        _route(
          startAt: DateTime(2026, 8, 1, 22),
          endAt: DateTime(2026, 8, 2, 2),
          stops: 40,
        ),
      );

      expect(pace, 6);
    });

    test('rota sem hora de fim não tem ritmo', () {
      expect(
        paceOf(_route(startAt: DateTime(2026, 8, 7, 12, 21), stops: 28)),
        isNull,
      );
    });

    test('rota sem paradas informadas não tem ritmo', () {
      expect(
        paceOf(
          _route(
            startAt: DateTime(2026, 8, 7, 12, 21),
            endAt: DateTime(2026, 8, 7, 16, 26),
          ),
        ),
        isNull,
      );
    });

    test(
      'duração não positiva é documento corrompido, não ritmo instantâneo',
      () {
        expect(
          paceOf(
            _route(
              startAt: DateTime(2026, 8, 7, 16),
              endAt: DateTime(2026, 8, 7, 16),
              stops: 28,
            ),
          ),
          isNull,
        );
      },
    );
  });

  group('formatPaceShort — a forma curta', () {
    test('mesmo número, menos letra', () {
      expect(formatPaceShort(6), '6,0 m/p');
      expect(formatPaceShort(5.7), '5,7 m/p');
      expect(formatPaceShort(120), '120,0 m/p');
    });

    test('as duas formas arredondam igual', () {
      // A razão de existir uma função e não uma segunda interpolação: o
      // número é o mesmo, e é o arredondamento que não pode divergir. Sem o
      // primitivo compartilhado, o card diria `5,8 min/parada` e o dialog
      // `5,7 m/p` para o mesmo entregador no dia em que alguém mexesse numa só.
      for (final valor in [5.75, 0.44, 12.44, 6.0, 99.95]) {
        final longo = formatPace(valor).split(' ').first;
        final curto = formatPaceShort(valor).split(' ').first;
        expect(curto, longo, reason: 'divergiram em $valor');
      }
    });
  });

  group('formatPace — o mesmo texto nas três telas', () {
    test('vírgula decimal, uma casa, sempre', () {
      expect(formatPace(5.7), '5,7 min/parada');
      expect(formatPace(6), '6,0 min/parada');
      expect(formatPace(12.44), '12,4 min/parada');
    });

    test('arredonda para a casa mostrada', () {
      expect(formatPace(5.75), '5,8 min/parada');
      expect(formatPace(0.44), '0,4 min/parada');
    });
  });
}
