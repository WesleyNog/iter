import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeTime.dart';

void main() {
  final dia = DateTime(2026, 8, 1);

  group('parseTime', () {
    test('lê HH:mm', () {
      expect(RouteTime.parseTime('08:30'), (hour: 8, minute: 30));
      expect(RouteTime.parseTime('00:00'), (hour: 0, minute: 0));
      expect(RouteTime.parseTime('23:59'), (hour: 23, minute: 59));
    });

    test('recusa formato ou intervalo inválido', () {
      expect(RouteTime.parseTime('8h30'), isNull);
      expect(RouteTime.parseTime('24:00'), isNull);
      expect(RouteTime.parseTime('10:60'), isNull);
      expect(RouteTime.parseTime(''), isNull);
    });
  });

  group('combine', () {
    test('junta a data da rota com o horário', () {
      expect(RouteTime.combine(dia, '08:30'), DateTime(2026, 8, 1, 8, 30));
    });

    test('devolve null quando o horário não é legível', () {
      expect(RouteTime.combine(dia, 'depois'), isNull);
    });
  });

  group('resolveEnd', () {
    final inicio = DateTime(2026, 8, 1, 22);

    test('rota que vira o dia termina no dia seguinte', () {
      // Sem isso, 22:00 às 02:00 daria duração negativa de 20 horas.
      expect(
        RouteTime.resolveEnd(inicio, '02:00'),
        DateTime(2026, 8, 2, 2),
      );
    });

    test('fim no mesmo dia fica no mesmo dia', () {
      expect(
        RouteTime.resolveEnd(DateTime(2026, 8, 1, 8), '17:30'),
        DateTime(2026, 8, 1, 17, 30),
      );
    });

    test('fim igual ao início conta como volta completa', () {
      expect(RouteTime.resolveEnd(inicio, '22:00'), DateTime(2026, 8, 2, 22));
    });

    test('sem hora de fim devolve null', () {
      expect(RouteTime.resolveEnd(inicio, null), isNull);
      expect(RouteTime.resolveEnd(inicio, ''), isNull);
      expect(RouteTime.resolveEnd(inicio, 'qualquer coisa'), isNull);
    });
  });

  group('formatDuration', () {
    test('horas e minutos', () {
      expect(
        RouteTime.formatDuration(
          DateTime(2026, 8, 1, 8),
          DateTime(2026, 8, 1, 17, 30),
        ),
        '9h30',
      );
    });

    test('só horas ou só minutos', () {
      expect(
        RouteTime.formatDuration(
          DateTime(2026, 8, 1, 22),
          DateTime(2026, 8, 2, 2),
        ),
        '4h',
      );
      expect(
        RouteTime.formatDuration(
          DateTime(2026, 8, 1, 8),
          DateTime(2026, 8, 1, 8, 45),
        ),
        '45min',
      );
    });

    test('sem fim, ou fim que não faz sentido, não gera duração', () {
      expect(RouteTime.formatDuration(DateTime(2026, 8, 1, 8), null), isNull);
      expect(
        RouteTime.formatDuration(
          DateTime(2026, 8, 1, 8),
          DateTime(2026, 8, 1, 7),
        ),
        isNull,
      );
    });
  });

  group('formatTime', () {
    test('sempre com dois dígitos', () {
      expect(RouteTime.formatTime(DateTime(2026, 8, 1, 8, 5)), '08:05');
      expect(RouteTime.formatTime(DateTime(2026, 8, 1, 0, 0)), '00:00');
    });
  });
}
