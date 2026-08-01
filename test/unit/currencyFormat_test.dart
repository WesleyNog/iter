import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/currencyFormat.dart';

void main() {
  group('parseMoneyToDouble', () {
    test('lê o texto formatado do campo de valor', () {
      expect(CurrencyFormatterHelper.parseMoneyToDouble('R\$ 150,50'), 150.5);
      expect(CurrencyFormatterHelper.parseMoneyToDouble('R\$ 1.234,56'), 1234.56);
      expect(CurrencyFormatterHelper.parseMoneyToDouble('R\$ 0,00'), 0.0);
    });

    test('devolve 0 para texto vazio ou inválido', () {
      expect(CurrencyFormatterHelper.parseMoneyToDouble(''), 0.0);
      expect(CurrencyFormatterHelper.parseMoneyToDouble('abc'), 0.0);
    });
  });

  test('o que o campo formata volta como o mesmo número', () {
    // Foi aqui que o valor virava 0: o texto do campo é "R$ 150,50", e um
    // `double.tryParse` direto não dá conta do símbolo nem do milhar.
    for (final amount in [150.5, 1234.56, 99.99, 1000000.0]) {
      final text = CurrencyFormatterHelper.formatDoubleToMoney(amount);
      expect(
        CurrencyFormatterHelper.parseMoneyToDouble(text),
        amount,
        reason: 'falhou para $amount (texto: "$text")',
      );
      expect(double.tryParse(text.replaceAll(',', '.')), isNull);
    }
  });
}
