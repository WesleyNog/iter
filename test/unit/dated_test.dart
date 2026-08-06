import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/dated.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/supply.dart';

Supply _supply(String id, String date) =>
    Supply(id: id, value: 100, date: date, createdAt: date);

Maintenance _maintenance(String id, String date) =>
    Maintenance(id: id, value: 100, date: date, createdAt: date);

void main() {
  group('sortByDateDesc — a ordenação compartilhada', () {
    test('do mais recente para o mais antigo', () {
      final sorted = sortByDateDesc([
        _supply('meio', '2026-08-03T10:00:00.000'),
        _supply('novo', '2026-08-05T10:00:00.000'),
        _supply('velho', '2026-08-01T10:00:00.000'),
      ]);

      expect(sorted.map((s) => s.id), ['novo', 'meio', 'velho']);
    });

    test('vale igual para manutenção — é o ponto de ser genérica', () {
      final sorted = sortByDateDesc([
        _maintenance('velho', '2026-07-01T10:00:00.000'),
        _maintenance('novo', '2026-08-05T10:00:00.000'),
      ]);

      expect(sorted.map((m) => m.id), ['novo', 'velho']);
    });

    test('ISO ordena como texto na mesma ordem que como data', () {
      // É por isso que `date` é ISO e não `dd/MM/yyyy`, que poria 02/01/2027
      // antes de 31/12/2026.
      final sorted = sortByDateDesc([
        _supply('dez', '2026-12-31T10:00:00.000'),
        _supply('jan', '2027-01-02T10:00:00.000'),
      ]);

      expect(sorted.first.id, 'jan');
    });

    test('data vazia vai para o fim em vez de lançar', () {
      final sorted = sortByDateDesc([
        _supply('corrompido', ''),
        _supply('ok', '2026-08-01T10:00:00.000'),
      ]);

      expect(sorted.map((s) => s.id), ['ok', 'corrompido']);
    });

    test('empate desempata pelo id, para a ordem não dançar', () {
      const data = '2026-08-01T10:00:00.000';

      expect(
        sortByDateDesc([_supply('z', data), _supply('a', data)]).map((s) => s.id),
        ['a', 'z'],
      );
      expect(
        sortByDateDesc([_supply('a', data), _supply('z', data)]).map((s) => s.id),
        ['a', 'z'],
      );
    });

    test('não altera a lista recebida', () {
      final original = [
        _supply('velho', '2026-08-01T10:00:00.000'),
        _supply('novo', '2026-08-05T10:00:00.000'),
      ];
      sortByDateDesc(original);

      expect(original.map((s) => s.id), ['velho', 'novo']);
    });
  });
}
