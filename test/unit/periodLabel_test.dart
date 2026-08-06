import 'package:flutter_test/flutter_test.dart';
import 'package:iter/screens/summaryScreen.dart';

void main() {
  group('periodLabel', () {
    test('mês inteiro vira o nome do mês', () {
      expect(
        periodLabel(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
        'AGOSTO 2026',
      );
    });

    test('fevereiro de ano bissexto fecha no dia 29', () {
      expect(
        periodLabel(DateTime(2028, 2, 1), DateTime(2028, 2, 29)),
        'FEVEREIRO 2028',
      );
    });

    test('a hora que a roleta devolve não estraga o mês', () {
      // As roletas de data trazem horário junto; `==` entre `DateTime` faria
      // 01/08 às 00:00 e 01/08 às 14:30 serem meses diferentes.
      expect(
        periodLabel(
          DateTime(2026, 8, 1, 14, 30),
          DateTime(2026, 8, 31, 23, 59),
        ),
        'AGOSTO 2026',
      );
    });

    test('um dia a menos no fim não é o mês inteiro', () {
      // O erro que a versão anterior cometia: `difference().inDays == 0`
      // também dava zero para meio dia a menos.
      expect(
        periodLabel(DateTime(2026, 8, 1), DateTime(2026, 8, 30)),
        '01/08/2026 a 30/08/2026',
      );
    });

    test('um dia a mais no começo não é o mês inteiro', () {
      expect(
        periodLabel(DateTime(2026, 8, 2), DateTime(2026, 8, 31)),
        '02/08/2026 a 31/08/2026',
      );
    });

    test('período atravessando meses mostra as duas datas', () {
      expect(
        periodLabel(DateTime(2026, 7, 15), DateTime(2026, 8, 15)),
        '15/07/2026 a 15/08/2026',
      );
    });

    test('um dia só mostra a data duas vezes, sem inventar mês', () {
      expect(
        periodLabel(DateTime(2026, 8, 5), DateTime(2026, 8, 5)),
        '05/08/2026 a 05/08/2026',
      );
    });
  });
}
