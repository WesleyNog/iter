import 'package:flutter_test/flutter_test.dart';
import 'package:iter/controller/stationController.dart';
import 'package:iter/controller/supplyController.dart';
import 'package:iter/model/supply.dart';

Supply _supply({
  String id = 's1',
  String date = '2026-08-05T21:00:00.000',
  double value = 250,
  double? liters = 40,
  FuelStation? station,
}) {
  return Supply(
    id: id,
    value: value,
    liters: liters,
    station: station,
    date: date,
    createdAt: date,
  );
}

const _fromSource = FuelStation(
  id: 'way-243218168',
  name: 'Posto Prainha',
  brand: 'Shell',
  lat: -3.7238,
  lng: -38.5197,
);

/// Posto digitado à mão: sem id, porque não veio do OpenStreetMap.
const _typedByHand = FuelStation(id: '', name: 'Posto do Zé', lat: 0, lng: 0);

void main() {
  group('sortByDate — do mais recente para o mais antigo', () {
    test('ordena pela data do abastecimento', () {
      final sorted = SupplyController.sortByDate([
        _supply(id: 'meio', date: '2026-08-03T10:00:00.000'),
        _supply(id: 'novo', date: '2026-08-05T10:00:00.000'),
        _supply(id: 'velho', date: '2026-08-01T10:00:00.000'),
      ]);

      expect(sorted.map((s) => s.id), ['novo', 'meio', 'velho']);
    });

    test('ISO ordena como texto na mesma ordem que como data', () {
      // É por isso que `date` é ISO e não `dd/MM/yyyy` — aquele formato põe
      // 02/01/2027 antes de 31/12/2026, a armadilha que a lista de rotas teve
      // de contornar ordenando em memória.
      final sorted = SupplyController.sortByDate([
        _supply(id: 'dez', date: '2026-12-31T10:00:00.000'),
        _supply(id: 'jan', date: '2027-01-02T10:00:00.000'),
      ]);

      expect(sorted.first.id, 'jan');
    });

    test('data vazia vai para o fim em vez de lançar', () {
      final sorted = SupplyController.sortByDate([
        _supply(id: 'corrompido', date: ''),
        _supply(id: 'ok', date: '2026-08-01T10:00:00.000'),
      ]);

      expect(sorted.map((s) => s.id), ['ok', 'corrompido']);
    });

    test('empate desempata pelo id, para a ordem não dançar', () {
      final a = SupplyController.sortByDate([
        _supply(id: 'z', date: '2026-08-01T10:00:00.000'),
        _supply(id: 'a', date: '2026-08-01T10:00:00.000'),
      ]);

      expect(a.map((s) => s.id), ['a', 'z']);
    });

    test('não altera a lista recebida', () {
      final original = [
        _supply(id: 'velho', date: '2026-08-01T10:00:00.000'),
        _supply(id: 'novo', date: '2026-08-05T10:00:00.000'),
      ];
      SupplyController.sortByDate(original);

      expect(original.map((s) => s.id), ['velho', 'novo']);
    });
  });

  group('canReport — o que pode sujar a coleção compartilhada', () {
    test('posto da fonte com preço calculável pode relatar', () {
      expect(
        StationController.canReport(_supply(station: _fromSource)),
        isTrue,
      );
    });

    test('sem posto nenhum não relata', () {
      expect(StationController.canReport(_supply()), isFalse);
    });

    test('posto digitado à mão não relata', () {
      // Sem id do OSM, "Posto do Zé" viraria dez documentos que ninguém
      // consegue reconciliar como sendo o mesmo lugar.
      expect(
        StationController.canReport(_supply(station: _typedByHand)),
        isFalse,
      );
    });

    test('sem litros não relata — não há preço do litro', () {
      expect(
        StationController.canReport(
          _supply(station: _fromSource, liters: null),
        ),
        isFalse,
      );
    });

    test('litros zero não relata, e não vira divisão por zero', () {
      expect(
        StationController.canReport(_supply(station: _fromSource, liters: 0)),
        isFalse,
      );
    });

    test('valor zero não relata', () {
      expect(
        StationController.canReport(_supply(station: _fromSource, value: 0)),
        isFalse,
      );
    });
  });
}
