import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/expenseSummary.dart';
import 'package:iter/Utils/dated.dart';
import 'package:iter/model/maintenance.dart';
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

Maintenance _maintenance({
  String id = 'm1',
  String date = '2026-08-06T10:00:00.000',
  double value = 2400,
}) {
  return Maintenance(id: id, value: value, date: date, createdAt: date);
}

final _start = DateTime(2026, 8, 1);
final _end = DateTime(2026, 8, 31);

void main() {
  group('inPeriodByDate', () {
    test('pega o que está dentro e descarta o que está fora', () {
      final dentro = inPeriodByDate([
        _supply(id: 'jul', date: '2026-07-31T23:00:00.000'),
        _supply(id: 'ago', date: '2026-08-15T10:00:00.000'),
        _supply(id: 'set', date: '2026-09-01T01:00:00.000'),
      ], start: _start, end: _end);

      expect(dentro.map((s) => s.id), ['ago']);
    });

    test('as duas pontas entram', () {
      final dentro = inPeriodByDate([
        _supply(id: 'primeiro', date: '2026-08-01T00:00:00.000'),
        _supply(id: 'ultimo', date: '2026-08-31T23:59:00.000'),
      ], start: _start, end: _end);

      expect(dentro.length, 2);
    });

    test('a hora não tira ninguém do último dia', () {
      // Abastecer às 23h do dia 31 é gasto de agosto. Comparar `DateTime`
      // inteiro cortaria tudo depois da meia-noite do último dia.
      final dentro = inPeriodByDate(
        [_supply(date: '2026-08-31T22:47:00.000')],
        start: _start,
        end: _end,
      );

      expect(dentro.length, 1);
    });

    test('data ilegível é descartada sem lançar', () {
      final dentro = inPeriodByDate([
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
      ], const []);

      expect(summary.fuel, closeTo(430.50, 1e-9));
      expect(summary.supplies, 2);
    });

    test('soma o valor das manutenções', () {
      final summary = expenseSummary(const [], [
        _maintenance(id: 'a', value: 2400),
        _maintenance(id: 'b', value: 200),
      ]);

      expect(summary.maintenance, closeTo(2600, 1e-9));
      expect(summary.maintenances, 2);
    });

    test('período sem manutenção é zero, e zero agora é afirmação', () {
      // Antes desta entrega o card dizia "em breve", porque o app não sabia.
      // Agora sabe: não gastou com peça no período.
      final summary = expenseSummary([_supply()], const []);

      expect(summary.maintenance, 0);
      expect(summary.maintenances, 0);
    });

    test('o total soma as duas frentes', () {
      final summary = expenseSummary(
        [_supply(value: 250)],
        [_maintenance(value: 2400)],
      );

      expect(summary.total, closeTo(2650, 1e-9));
    });

    test('manutenção não mexe nos litros nem no preço médio', () {
      // São grandezas de combustível; manutenção não tem litro.
      final summary = expenseSummary(
        [_supply(value: 300, liters: 50)],
        [_maintenance(value: 2400)],
      );

      expect(summary.liters, closeTo(50, 1e-9));
      expect(summary.averagePricePerLiter, closeTo(6.0, 1e-9));
    });

    test('só manutenção no período não é período vazio', () {
      final summary = expenseSummary(const [], [_maintenance()]);

      expect(summary.isEmpty, isFalse);
      expect(summary.fuel, 0);
    });

    test('período vazio devolve zero, não null', () {
      // Aqui zero é verdade: não gastar nada é um resultado, diferente de "não
      // dá para calcular".
      final summary = expenseSummary(const [], const []);

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
      ], const []);

      expect(summary.liters, closeTo(72.5, 1e-9));
    });

    test('ninguém informou litros devolve null, não zero', () {
      final summary = expenseSummary([_supply(liters: null)], const []);

      expect(summary.liters, isNull);
    });

    test('preço médio é ponderado, não a média dos preços', () {
      // R$ 300 a R$ 6,00/L e R$ 30 a R$ 7,00/L: ele pagou R$ 6,08 no mês.
      // A média simples daria R$ 6,50 — peso igual para um tanque cheio e uma
      // completada de trinta reais.
      final summary = expenseSummary([
        _supply(id: 'a', value: 300, liters: 50),
        _supply(id: 'b', value: 30, liters: 4.2857),
      ], const []);

      expect(summary.averagePricePerLiter, closeTo(6.0789, 0.001));
      expect(summary.averagePricePerLiter, isNot(closeTo(6.5, 0.01)));
    });

    test('sem litros não há preço médio', () {
      final summary = expenseSummary([_supply(liters: null)], const []);

      expect(summary.averagePricePerLiter, isNull);
    });

    test('abastecimento sem litros não entra no divisor do preço médio', () {
      // Se entrasse só no dividendo, o preço médio subiria sem motivo.
      final summary = expenseSummary([
        _supply(id: 'a', value: 300, liters: 50),
        _supply(id: 'b', value: 100, liters: null),
      ], const []);

      expect(summary.averagePricePerLiter, closeTo(6.0, 1e-9));
      // Mas o dinheiro gasto continua inteiro no total.
      expect(summary.fuel, closeTo(400, 1e-9));
    });
  });
}
