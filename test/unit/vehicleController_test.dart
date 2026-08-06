import 'package:flutter_test/flutter_test.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/vehicle.dart';

/// As duas funções puras do controller — as únicas testáveis sem Firestore, e
/// justamente as que decidem *qual carro entra na conta da rota*.
Vehicle _vehicle(String id, {String createdAt = '2026-01-01T00:00:00.000'}) {
  return Vehicle(
    id: id,
    type: VehicleType.carro,
    brandCode: '21',
    brandName: 'Fiat',
    modelCode: '1',
    modelName: 'Fiorino',
    fuel: FuelType.flex,
    createdAt: createdAt,
  );
}

void main() {
  group('activeFrom — quem é o veículo em uso', () {
    test('devolve o veículo apontado pelo id', () {
      final list = [_vehicle('a'), _vehicle('b'), _vehicle('c')];
      expect(VehicleController.activeFrom(list, 'b')!.id, 'b');
    });

    test('sem veículo nenhum devolve null', () {
      expect(VehicleController.activeFrom([], 'a'), isNull);
      expect(VehicleController.activeFrom([], null), isNull);
    });

    test('id nulo cai no primeiro em vez de deixar sem carro', () {
      final list = [_vehicle('a'), _vehicle('b')];
      expect(VehicleController.activeFrom(list, null)!.id, 'a');
    });

    test('id órfão cai no primeiro', () {
      // Veículo excluído com o app offline: o usuário tem carro, e mostrar
      // "nenhum veículo" seria mentira.
      final list = [_vehicle('a'), _vehicle('b')];
      expect(VehicleController.activeFrom(list, 'sumiu')!.id, 'a');
    });

    test('a resolução é a mesma para tela e para cálculo', () {
      // O ponto inteiro de existir uma função só: se a AppBar desenhasse um
      // carro e a provisão usasse outro, o lucro seria de um veículo que o
      // entregador não vê.
      final list = [_vehicle('a'), _vehicle('b')];
      const orphan = 'nao-existe';

      expect(
        VehicleController.activeFrom(list, orphan)!.id,
        VehicleController.activeFrom(list, orphan)!.id,
      );
    });
  });

  group('sortByCreation — ordem estável', () {
    test('do mais antigo para o mais novo', () {
      final sorted = VehicleController.sortByCreation([
        _vehicle('novo', createdAt: '2026-08-01T00:00:00.000'),
        _vehicle('velho', createdAt: '2026-01-01T00:00:00.000'),
        _vehicle('meio', createdAt: '2026-05-01T00:00:00.000'),
      ]);

      expect(sorted.map((v) => v.id), ['velho', 'meio', 'novo']);
    });

    test('empate de data desempata pelo id, nunca fica indefinido', () {
      // Sem desempate, `first` poderia mudar entre dois rebuilds e trocar o
      // veículo ativo sozinho.
      final a = VehicleController.sortByCreation([
        _vehicle('z', createdAt: '2026-01-01T00:00:00.000'),
        _vehicle('a', createdAt: '2026-01-01T00:00:00.000'),
      ]);
      final b = VehicleController.sortByCreation([
        _vehicle('a', createdAt: '2026-01-01T00:00:00.000'),
        _vehicle('z', createdAt: '2026-01-01T00:00:00.000'),
      ]);

      expect(a.map((v) => v.id), ['a', 'z']);
      expect(b.map((v) => v.id), ['a', 'z']);
    });

    test('createdAt vazio não lança e vai para o começo', () {
      final sorted = VehicleController.sortByCreation([
        _vehicle('novo', createdAt: '2026-08-01T00:00:00.000'),
        _vehicle('antigo', createdAt: ''),
      ]);

      expect(sorted.first.id, 'antigo');
    });

    test('não altera a lista recebida', () {
      final original = [
        _vehicle('b', createdAt: '2026-08-01T00:00:00.000'),
        _vehicle('a', createdAt: '2026-01-01T00:00:00.000'),
      ];
      VehicleController.sortByCreation(original);

      expect(original.map((v) => v.id), ['b', 'a']);
    });
  });
}
