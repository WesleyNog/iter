import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/expenseSummary.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/supply.dart';

Supply _supply({
  String id = 's1',
  String date = '2026-08-05T21:00:00.000',
  double value = 250,
  double? liters = 39.75,
  SupplyFuel fuel = SupplyFuel.gasolina,
  FuelStation? station,
}) {
  return Supply(
    id: id,
    value: value,
    liters: liters,
    fuel: fuel,
    station: station,
    date: date,
    createdAt: date,
  );
}

Maintenance _maintenance({
  String id = 'm1',
  String date = '2026-08-06T10:00:00.000',
  double value = 2400,
  MaintenanceItem item = MaintenanceItem.pneu,
  MaintenanceAction action = MaintenanceAction.substituicao,
  String? workshop = 'Auto Center do Zé',
}) {
  return Maintenance(
    id: id,
    item: item,
    action: action,
    value: value,
    workshop: workshop,
    date: date,
    createdAt: date,
  );
}

const _posto = FuelStation(
  id: 'way-1',
  name: 'Posto Apiguana',
  lat: 0,
  lng: 0,
);

void main() {
  group('a lista mista', () {
    test('junta os dois tipos numa lista só', () {
      final rows = expenseRows([_supply()], [_maintenance()]);

      expect(rows.length, 2);
      expect(
        rows.map((r) => r.kind),
        containsAll([ExpenseKind.abastecimento, ExpenseKind.manutencao]),
      );
    });

    test('ordena por data, do mais recente para o mais antigo', () {
      // A manutenção é do dia 06 e o abastecimento do dia 05: intercalar por
      // data é o ponto de as duas listas virarem uma.
      final rows = expenseRows([_supply()], [_maintenance()]);

      expect(rows.first.kind, ExpenseKind.manutencao);
      expect(rows.last.kind, ExpenseKind.abastecimento);
    });

    test('intercala de verdade, não concatena', () {
      final rows = expenseRows(
        [
          _supply(id: 's-novo', date: '2026-08-10T10:00:00.000'),
          _supply(id: 's-velho', date: '2026-08-01T10:00:00.000'),
        ],
        [_maintenance(id: 'm-meio', date: '2026-08-05T10:00:00.000')],
      );

      expect(rows.map((r) => r.id), ['s-novo', 'm-meio', 's-velho']);
    });

    test('listas vazias devolvem lista vazia, sem lançar', () {
      expect(expenseRows(const [], const []), isEmpty);
    });

    test('data vazia vai para o fim', () {
      final rows = expenseRows(
        [_supply(id: 'ok')],
        [_maintenance(id: 'corrompida', date: '')],
      );

      expect(rows.last.id, 'corrompida');
    });

    test('empate de data desempata pelo id, para a ordem não dançar', () {
      const data = '2026-08-05T10:00:00.000';
      final rows = expenseRows(
        [_supply(id: 'z', date: data)],
        [_maintenance(id: 'a', date: data)],
      );

      expect(rows.map((r) => r.id), ['a', 'z']);
    });
  });

  group('como cada linha se apresenta', () {
    test('abastecimento mostra o posto e os detalhes da bomba', () {
      final row = expenseRows([_supply(station: _posto)], const []).single;

      expect(row.title, 'Posto Apiguana');
      expect(row.subtitle, 'Gasolina · 39,8 L · R\$ 6,2893/L');
      expect(row.value, 250);
    });

    test('abastecimento sem posto não fica sem título', () {
      final row = expenseRows([_supply()], const []).single;

      expect(row.title, 'Posto não informado');
    });

    test('abastecimento sem litros omite litros e preço', () {
      final row = expenseRows([_supply(liters: null)], const []).single;

      expect(row.subtitle, 'Gasolina');
    });

    test('manutenção mostra a peça e o que foi feito', () {
      final row = expenseRows(const [], [_maintenance()]).single;

      expect(row.title, 'Pneu');
      expect(row.subtitle, 'Substituição · Auto Center do Zé');
      expect(row.value, 2400);
    });

    test('manutenção sem oficina não deixa um separador solto', () {
      final row = expenseRows(const [], [_maintenance(workshop: null)]).single;

      expect(row.subtitle, 'Substituição');
    });

    test('oficina em branco conta como ausente', () {
      final row = expenseRows(const [], [_maintenance(workshop: '   ')]).single;

      expect(row.subtitle, 'Substituição');
    });

    test('reparo aparece como reparo — a distinção é visível no extrato', () {
      final row = expenseRows(const [], [
        _maintenance(action: MaintenanceAction.reparo, workshop: null),
      ]).single;

      expect(row.subtitle, 'Reparo');
    });
  });
}
