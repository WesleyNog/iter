import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/expenseSummary.dart';
import 'package:iter/model/supply.dart';

Supply _supply({
  String id = 's1',
  String date = '2026-08-05T21:00:00.000',
  double value = 250,
  double? liters = 40,
}) {
  return Supply(
    id: id,
    value: value,
    liters: liters,
    date: date,
    createdAt: date,
  );
}

final _start = DateTime(2026, 8, 1);
final _end = DateTime(2026, 8, 31);

void main() {
  group('suppliesInPeriod', () {
    test('pega o que está dentro e descarta o que está fora', () {
      final dentro = suppliesInPeriod([
        _supply(id: 'jul', date: '2026-07-31T23:00:00.000'),
        _supply(id: 'ago', date: '2026-08-15T10:00:00.000'),
        _supply(id: 'set', date: '2026-09-01T01:00:00.000'),
      ], start: _start, end: _end);

      expect(dentro.map((s) => s.id), ['ago']);
    });

    test('as duas pontas entram', () {
      final dentro = suppliesInPeriod([
        _supply(id: 'primeiro', date: '2026-08-01T00:00:00.000'),
        _supply(id: 'ultimo', date: '2026-08-31T23:59:00.000'),
      ], start: _start, end: _end);

      expect(dentro.length, 2);
    });

    test('a hora não tira ninguém do último dia', () {
      // Abastecer às 23h do dia 31 é gasto de agosto. Comparar `DateTime`
      // inteiro cortaria tudo depois da meia-noite do último dia.
      final dentro = suppliesInPeriod(
        [_supply(date: '2026-08-31T22:47:00.000')],
        start: _start,
        end: _end,
      );

      expect(dentro.length, 1);
    });

    test('data ilegível é descartada sem lançar', () {
      final dentro = suppliesInPeriod([
        _supply(id: 'ok', date: '2026-08-10T10:00:00.000'),
        _supply(id: 'corrompido', date: 'não é data'),
        _supply(id: 'vazio', date: ''),
      ], start: _start, end: _end);

      expect(dentro.map((s) => s.id), ['ok']);
    });
  });

  group('expenseSummary', () {
    test('soma o valor dos abastecimentos', () {
      final summary = expenseSummary([
        _supply(id: 'a', value: 250),
        _supply(id: 'b', value: 180.50),
      ]);

      expect(summary.fuel, closeTo(430.50, 1e-9));
      expect(summary.supplies, 2);
    });

    test('manutenção fica reservada em zero até existir a tela', () {
      final summary = expenseSummary([_supply()]);

      expect(summary.maintenance, 0);
      // O card mostra a linha marcada "em breve": zero aqui é reserva de
      // espaço, não afirmação de que ele não gastou com manutenção.
      expect(summary.hasMaintenance, isFalse);
    });

    test('o total soma as duas frentes', () {
      final summary = expenseSummary([_supply(value: 250)]);

      expect(summary.total, closeTo(250, 1e-9));
    });

    test('período vazio devolve zero, não null', () {
      // Aqui zero é verdade: não gastar nada é um resultado, diferente de "não
      // dá para calcular".
      final summary = expenseSummary(const []);

      expect(summary.fuel, 0);
      expect(summary.maintenance, 0);
      expect(summary.total, 0);
      expect(summary.supplies, 0);
      expect(summary.isEmpty, isTrue);
    });

    test('litros somam só os informados', () {
      final summary = expenseSummary([
        _supply(id: 'a', liters: 40),
        _supply(id: 'b', liters: 32.5),
        _supply(id: 'c', liters: null),
      ]);

      expect(summary.liters, closeTo(72.5, 1e-9));
    });

    test('ninguém informou litros devolve null, não zero', () {
      final summary = expenseSummary([_supply(liters: null)]);

      expect(summary.liters, isNull);
    });

    test('preço médio é ponderado, não a média dos preços', () {
      // R$ 300 a R$ 6,00/L e R$ 30 a R$ 7,00/L: ele pagou R$ 6,08 no mês.
      // A média simples daria R$ 6,50 — peso igual para um tanque cheio e uma
      // completada de trinta reais.
      final summary = expenseSummary([
        _supply(id: 'a', value: 300, liters: 50),
        _supply(id: 'b', value: 30, liters: 4.2857),
      ]);

      expect(summary.averagePricePerLiter, closeTo(6.0789, 0.001));
      expect(summary.averagePricePerLiter, isNot(closeTo(6.5, 0.01)));
    });

    test('sem litros não há preço médio', () {
      final summary = expenseSummary([_supply(liters: null)]);

      expect(summary.averagePricePerLiter, isNull);
    });

    test('abastecimento sem litros não entra no divisor do preço médio', () {
      // Se entrasse só no dividendo, o preço médio subiria sem motivo.
      final summary = expenseSummary([
        _supply(id: 'a', value: 300, liters: 50),
        _supply(id: 'b', value: 100, liters: null),
      ]);

      expect(summary.averagePricePerLiter, closeTo(6.0, 1e-9));
      // Mas o dinheiro gasto continua inteiro no total.
      expect(summary.fuel, closeTo(400, 1e-9));
    });
  });
}
