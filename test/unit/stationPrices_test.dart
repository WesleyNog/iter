import 'package:flutter_test/flutter_test.dart';
import 'package:iter/controller/stationController.dart';
import 'package:iter/model/stationPrices.dart';
import 'package:iter/model/supply.dart';

void main() {
  group('leitura de gastop/{id}', () {
    test('preço e data por combustível', () {
      final prices = StationPrices.fromMap({
        'prices': {'gasolina': 6.14, 'etanol': 4.24},
        'pricedAt': {
          'gasolina': '2026-10-04T08:30:00.000',
          'etanol': '2026-10-02T12:00:00.000',
        },
      });

      expect(prices.of(SupplyFuel.gasolina)!.price, 6.14);
      expect(prices.of(SupplyFuel.gasolina)!.at, DateTime(2026, 10, 4, 8, 30));
      expect(prices.of(SupplyFuel.etanol)!.at, DateTime(2026, 10, 2, 12));
    });

    test('combustível nunca relatado é null — a tela desenha "—"', () {
      final prices = StationPrices.fromMap({
        'prices': {'gasolina': 6.14},
      });

      expect(prices.of(SupplyFuel.diesel), isNull);
    });

    test('documento anterior ao pricedAt: preço sem data, sem lançar', () {
      // Gravado antes de 06/10/2026. Se corrige no próximo relato daquele
      // combustível naquele posto.
      final prices = StationPrices.fromMap({
        'prices': {'gasolina': 6.29},
        'updatedAt': '2026-08-06T10:00:00.000',
      });

      expect(prices.of(SupplyFuel.gasolina)!.price, 6.29);
      expect(prices.of(SupplyFuel.gasolina)!.at, isNull);
    });

    test('não empresta o updatedAt do posto para o combustível', () {
      // `updatedAt` muda quando **qualquer** combustível é relatado. Usá-lo
      // daria à gasolina de agosto a idade do etanol de ontem.
      final prices = StationPrices.fromMap({
        'prices': {'gasolina': 6.29},
        'updatedAt': '2026-10-05T10:00:00.000',
      });

      expect(prices.of(SupplyFuel.gasolina)!.at, isNull);
    });

    test('inteiro do Firestore vira double', () {
      final prices = StationPrices.fromMap({
        'prices': {'diesel': 6},
      });

      expect(prices.of(SupplyFuel.diesel)!.price, 6.0);
    });

    test('lixo é ignorado sem derrubar o resto do posto', () {
      final prices = StationPrices.fromMap({
        'prices': {
          'gasolina': 'seis reais',
          'etanol': 4.24,
          'querosene': 9.9,
          'diesel': 0,
        },
        'pricedAt': {'etanol': 'ontem'},
      });

      expect(prices.of(SupplyFuel.gasolina), isNull);
      expect(prices.of(SupplyFuel.etanol)!.price, 4.24);
      expect(prices.of(SupplyFuel.etanol)!.at, isNull);
      // Preço zero não é preço: seria "R\$ 0,00" num posto que não dá nada.
      expect(prices.of(SupplyFuel.diesel), isNull);
    });

    test('documento sem prices é um posto sem relato nenhum', () {
      final prices = StationPrices.fromMap({'name': 'Posto X'});

      for (final fuel in SupplyFuel.values) {
        expect(prices.of(fuel), isNull);
      }
    });

    test('prices que não é mapa não lança', () {
      expect(
        () => StationPrices.fromMap({'prices': 6.29, 'pricedAt': 'x'}),
        returnsNormally,
      );
    });
  });

  test('as colunas do card são os três líquidos da bomba', () {
    // Elétrico não sai de bomba de posto de combustível.
    expect(pumpFuels, [
      SupplyFuel.gasolina,
      SupplyFuel.etanol,
      SupplyFuel.diesel,
    ]);
  });

  group('blocos do whereIn', () {
    test('no máximo 30 ids por consulta — o limite do in', () {
      final ids = [for (var i = 0; i < 61; i++) 'node-$i'];
      final chunks = idChunks(ids);

      expect(chunks.length, 3);
      expect(chunks.map((c) => c.length), [30, 30, 1]);
      expect(chunks.expand((c) => c), ids);
    });

    test('ids vazios e repetidos não viram consulta', () {
      // Posto digitado à mão tem id vazio; o mesmo posto pode aparecer duas
      // vezes se a lista for montada de duas buscas.
      expect(idChunks(['', 'way-1', 'way-1', '']), [
        ['way-1'],
      ]);
      expect(idChunks(const []), isEmpty);
    });
  });
}
