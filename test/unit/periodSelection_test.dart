import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/periodSelection.dart';

/// Domingo, 11/10/2026 — o dia em que esta spec foi escrita. Domingo de
/// propósito: é o dia em que a conta errada de semana devolve a seguinte.
final _hoje = DateTime(2026, 10, 11, 14, 30);

void main() {
  group('o passo', () {
    test('mês atual, anterior e a virada de ano', () {
      final atual = PeriodSelection.month(0, _hoje);
      expect(atual.range, (
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      ));

      final dezAtras = PeriodSelection.month(-10, _hoje);
      expect(dezAtras.range, (
        start: DateTime(2025, 12, 1),
        end: DateTime(2025, 12, 31),
      ));
    });

    test('semana de segunda a domingo, e a anterior', () {
      expect(PeriodSelection.week(0, _hoje).range, (
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 11),
      ));
      expect(PeriodSelection.week(-1, _hoje).range, (
        start: DateTime(2026, 9, 28),
        end: DateTime(2026, 10, 4),
      ));
    });

    test('a seta › para no período atual', () {
      final atual = PeriodSelection.month(0, _hoje);
      expect(atual.canGoForward, isFalse);
      expect(atual.step(1, _hoje).offset, 0);

      final anterior = atual.step(-1, _hoje);
      expect(anterior.offset, -1);
      expect(anterior.canGoForward, isTrue);

      // Mesmo pedindo o futuro direto, o construtor prende no zero.
      expect(PeriodSelection.week(3, _hoje).offset, 0);
    });

    test('a seta ‹ não tem limite', () {
      var semana = PeriodSelection.week(0, _hoje);
      for (var i = 0; i < 60; i++) {
        semana = semana.step(-1, _hoje);
      }
      expect(semana.offset, -60);
      expect(semana.range.start.weekday, DateTime.monday);
    });

    test('o Personalizado não tem passo', () {
      final livre = PeriodSelection.custom((
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 12),
      ));
      expect(livre.hasSteps, isFalse);
      expect(livre.canGoForward, isFalse);
      expect(identical(livre.step(-1, _hoje), livre), isTrue);
    });
  });

  group('trocar de aba sem perder o lugar — a tabela da regra 4', () {
    test(
      'mês atual → semana: a semana atual, porque o fim do mês é futuro',
      () {
        final semana = PeriodSelection.month(
          0,
          _hoje,
        ).switchTo(PeriodKind.semana, _hoje);
        expect(semana.kind, PeriodKind.semana);
        expect(semana.offset, 0);
      },
    );

    test('agosto → semana: a última semana de agosto', () {
      final semana = PeriodSelection.month(
        -2,
        _hoje,
      ).switchTo(PeriodKind.semana, _hoje);
      // 31/08/2026 é segunda-feira: a semana que o contém começa nele.
      expect(semana.range.start, DateTime(2026, 8, 31));
      expect(semana.range.end, DateTime(2026, 9, 6));
    });

    test('semana atual → mês: o mês atual', () {
      final mes = PeriodSelection.week(
        0,
        _hoje,
      ).switchTo(PeriodKind.mes, _hoje);
      expect(mes.offset, 0);
    });

    test('semana que atravessa o mês → o mês do último dia', () {
      final mes = PeriodSelection.week(
        -1, // 28/09 a 04/10
        _hoje,
      ).switchTo(PeriodKind.mes, _hoje);
      expect(mes.range.start, DateTime(2026, 10, 1));
    });

    test('personalizado → mês ou semana: o que contém o fim, até hoje', () {
      final agosto = PeriodSelection.custom((
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 12, 9, 45), // as roletas devolvem hora junto
      ));
      expect(
        agosto.switchTo(PeriodKind.mes, _hoje).range.start,
        DateTime(2026, 8, 1),
      );
      expect(
        agosto.switchTo(PeriodKind.semana, _hoje).range.start,
        DateTime(2026, 8, 10),
      );

      final ateOFuturo = PeriodSelection.custom((
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 12, 20),
      ));
      expect(ateOFuturo.switchTo(PeriodKind.mes, _hoje).offset, 0);
    });

    test('qualquer um → personalizado: as mesmas datas da tela', () {
      final agosto = PeriodSelection.month(-2, _hoje);
      final livre = agosto.switchTo(PeriodKind.personalizado, _hoje);
      expect(livre.kind, PeriodKind.personalizado);
      expect(livre.range, agosto.range);
    });

    test('tocar na aba acesa não muda nada', () {
      final agosto = PeriodSelection.month(-2, _hoje);
      expect(identical(agosto.switchTo(PeriodKind.mes, _hoje), agosto), isTrue);
    });
  });

  group('o rótulo entre as setas', () {
    test('mês: o mesmo do Ranking', () {
      expect(
        periodSelectionLabel(PeriodSelection.month(0, _hoje)),
        'OUTUBRO 2026',
      );
    });

    test('semana no mesmo ano: o ano uma vez', () {
      expect(
        periodSelectionLabel(PeriodSelection.week(0, _hoje)),
        '05/10 – 11/10/2026',
      );
    });

    test('semana que atravessa a virada: o ano nas duas pontas', () {
      // 29/12/2025 a 04/01/2026. Com o ano uma vez, dezembro seria de 2026.
      final virada = PeriodSelection.week(0, DateTime(2026, 1, 2));
      expect(periodSelectionLabel(virada), '29/12/2025 – 04/01/2026');
    });
  });
}
