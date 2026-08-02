import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/insucessoBairro.dart';

void main() {
  group('remainingFailures', () {
    test('sem distribuição, resta o total', () {
      expect(remainingFailures(5, const {}), 5);
    });

    test('desconta o que já foi distribuído', () {
      expect(remainingFailures(5, const {'Aldeota': 2, 'Centro': 1}), 2);
    });

    test('distribuição completa não deixa resto', () {
      expect(remainingFailures(3, const {'Aldeota': 3}), 0);
    });

    test('nunca devolve negativo', () {
      expect(remainingFailures(2, const {'Aldeota': 5}), 0);
    });
  });

  group('reconcileDistribution', () {
    test('distribuição válida passa intacta', () {
      final result = reconcileDistribution(
        distribution: const {'Aldeota': 2, 'Centro': 1},
        bairros: const ['Aldeota', 'Centro', 'Cocó'],
        total: 5,
      );

      expect(result, {'Aldeota': 2, 'Centro': 1});
    });

    test('bairro que saiu da rota é descartado', () {
      final result = reconcileDistribution(
        distribution: const {'Aldeota': 2, 'Centro': 1},
        // A Aldeota foi removida de "Bairros" depois da distribuição.
        bairros: const ['Centro', 'Cocó'],
        total: 5,
      );

      // Os 2 da Aldeota voltam a ser "não distribuídos" e caem no rateio.
      expect(result, {'Centro': 1});
      expect(remainingFailures(5, result), 4);
    });

    test('bairro zerado não vira registro', () {
      final result = reconcileDistribution(
        distribution: const {'Aldeota': 0, 'Centro': 2},
        bairros: const ['Aldeota', 'Centro'],
        total: 5,
      );

      expect(result, {'Centro': 2});
    });

    test('total menor que o distribuído corta do fim', () {
      final result = reconcileDistribution(
        distribution: const {'Aldeota': 2, 'Centro': 2, 'Cocó': 1},
        bairros: const ['Aldeota', 'Centro', 'Cocó'],
        // Ele distribuiu 5 e depois baixou o total para 3.
        total: 3,
      );

      // Corta a partir do último: Cocó some inteiro, Centro perde 1.
      expect(result, {'Aldeota': 2, 'Centro': 1});
    });

    test('corte do fim atravessa mais de um bairro', () {
      final result = reconcileDistribution(
        distribution: const {'Aldeota': 1, 'Centro': 2, 'Cocó': 3},
        bairros: const ['Aldeota', 'Centro', 'Cocó'],
        total: 1,
      );

      expect(result, {'Aldeota': 1});
    });

    test('total zero limpa a distribuição', () {
      final result = reconcileDistribution(
        distribution: const {'Aldeota': 2},
        bairros: const ['Aldeota'],
        total: 0,
      );

      expect(result, isEmpty);
    });

    test('sem bairro nenhum, não há o que distribuir', () {
      final result = reconcileDistribution(
        distribution: const {'Aldeota': 2},
        bairros: const [],
        total: 5,
      );

      expect(result, isEmpty);
    });

    test('a ordem segue a lista de bairros da rota', () {
      final result = reconcileDistribution(
        distribution: const {'Cocó': 1, 'Aldeota': 1},
        bairros: const ['Aldeota', 'Centro', 'Cocó'],
        total: 5,
      );

      expect(result.keys, ['Aldeota', 'Cocó']);
    });
  });

  group('serialização', () {
    test('vira array de map, só com quantidade positiva', () {
      final list = distributionToList(const {'Aldeota': 2, 'Centro': 0});

      expect(list, [
        {'bairro': 'Aldeota', 'qnt': 2},
      ]);
    });

    test('ida e volta preserva a distribuição', () {
      const original = {'Aldeota': 2, 'Centro': 1};

      expect(distributionFromList(distributionToList(original)), original);
    });

    test('campo ausente vira distribuição vazia', () {
      expect(distributionFromList(null), isEmpty);
    });

    test('formato inesperado não derruba a leitura', () {
      // Documento gravado por versão futura, ou corrompido.
      final result = distributionFromList([
        {'bairro': 'Aldeota', 'qnt': 2},
        {'bairro': 'Centro'},
        {'qnt': 3},
        {'bairro': 'Cocó', 'qnt': 'três'},
        {'bairro': '', 'qnt': 1},
        {'bairro': 'Barra do Ceará', 'qnt': 0},
        'texto solto',
      ]);

      expect(result, {'Aldeota': 2});
    });

    test('bairro repetido soma em vez de sobrescrever', () {
      final result = distributionFromList([
        {'bairro': 'Aldeota', 'qnt': 2},
        {'bairro': 'Aldeota', 'qnt': 3},
      ]);

      expect(result, {'Aldeota': 5});
    });

    test('mapa vazio vira lista vazia', () {
      expect(distributionToList(const {}), isEmpty);
    });
  });
}
