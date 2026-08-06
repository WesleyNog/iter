import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/vehicleCost.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/vehicle.dart';

/// A Fiorino da planilha: R$ 7,00/L, 10 km/l e as cinco peças padrão.
///
/// Cadastrar um veículo sem tocar em nada tem de dar exatamente isto.
Vehicle _fiorino({
  double? fuelPrice = 7.0,
  double? consumption = 10.0,
  List<MaintenancePart>? parts,
}) {
  return Vehicle(
    id: 'v1',
    type: VehicleType.carro,
    brandCode: '21',
    brandName: 'Fiat',
    modelCode: '4828',
    modelName: 'Fiorino Endurance 1.4',
    fuel: FuelType.flex,
    fuelPrice: fuelPrice,
    consumption: consumption,
    parts: parts ?? Vehicle.defaultParts(VehicleType.carro),
    createdAt: '2026-08-05T10:00:00.000',
  );
}

NewRouteModal _route({
  double value = 152.50,
  double? kmInitial = 1000,
  double? kmFinal = 1046.9,
  StatusRoute status = StatusRoute.concluido,
}) {
  return NewRouteModal(
    id: 'r1',
    company: Company.amazon,
    dateRoute: '01/07/2026',
    weekday: 3,
    status: status,
    value: value,
    kmInitial: kmInitial,
    kmFinal: kmFinal,
    startAt: DateTime(2026, 7, 1, 8),
    createdAt: '2026-07-01T08:00:00.000',
  );
}

void main() {
  group('taxa por peça — preço ÷ vida útil', () {
    test('óleo: R\$ 200 a cada 10.000 km dá R\$ 0,02/km', () {
      const part = MaintenancePart(name: 'Óleo', price: 200, lifeKm: 10000);
      expect(partRatePerKm(part), closeTo(0.02, 1e-9));
    });

    test('pneu com quantidade 4 dá 0,040 e não 0,010', () {
      // O `*4` que a planilha esconde na fórmula `=(X11/Y11)*4`. Sem a
      // quantidade, provisionaria um quarto do que deve.
      const part = MaintenancePart(
        name: 'Pneu',
        price: 500,
        lifeKm: 50000,
        quantity: 4,
      );
      expect(partRatePerKm(part), closeTo(0.04, 1e-9));
    });

    test('freio com quantidade 4 dá 0,016', () {
      const part = MaintenancePart(
        name: 'Freio',
        price: 200,
        lifeKm: 50000,
        quantity: 4,
      );
      expect(partRatePerKm(part), closeTo(0.016, 1e-9));
    });

    test('a "Geral" usa a taxa direta e ignora preço e vida', () {
      const part = MaintenancePart(
        name: 'Geral',
        price: 999,
        lifeKm: 1,
        fixedRate: 0.03,
      );
      expect(partRatePerKm(part), 0.03);
    });

    test('vida útil zero devolve null, nunca infinito', () {
      const part = MaintenancePart(name: 'Óleo', price: 200, lifeKm: 0);
      expect(partRatePerKm(part), isNull);
    });

    test('vida útil negativa devolve null', () {
      const part = MaintenancePart(name: 'Óleo', price: 200, lifeKm: -10);
      expect(partRatePerKm(part), isNull);
    });

    test('peça sem preço ou sem vida devolve null', () {
      expect(partRatePerKm(const MaintenancePart(name: 'X', lifeKm: 100)), isNull);
      expect(partRatePerKm(const MaintenancePart(name: 'X', price: 100)), isNull);
    });
  });

  group('taxa do combustível — preço do litro ÷ km por litro', () {
    test('R\$ 7,00 e 10 km/l dão R\$ 0,70/km', () {
      expect(fuelRatePerKm(_fiorino()), closeTo(0.7, 1e-9));
    });

    test('consumo zero devolve null, não infinito', () {
      expect(fuelRatePerKm(_fiorino(consumption: 0)), isNull);
    });

    test('consumo ou preço ausente devolve null', () {
      expect(fuelRatePerKm(_fiorino(consumption: null)), isNull);
      expect(fuelRatePerKm(_fiorino(fuelPrice: null)), isNull);
    });
  });

  group('somas do veículo', () {
    test('peças somam R\$ 0,1193/km — sem a gasolina', () {
      expect(partsRatePerKm(_fiorino()), closeTo(0.1193333333, 1e-9));
    });

    test('total soma gasolina e peças: R\$ 0,8193/km', () {
      expect(totalRatePerKm(_fiorino()), closeTo(0.8193333333, 1e-9));
    });

    test('peça incalculável fica de fora da soma e é denunciada', () {
      final vehicle = _fiorino(
        parts: const [
          MaintenancePart(name: 'Óleo', price: 200, lifeKm: 10000),
          MaintenancePart(name: 'Correia', price: 300), // sem vida útil
        ],
      );

      expect(partsRatePerKm(vehicle), closeTo(0.02, 1e-9));
      // Sem isto, a peça sumiria da conta sem ninguém perceber.
      expect(unpricedParts(vehicle), ['Correia']);
    });

    test('veículo sem peça nenhuma tem só a taxa do combustível', () {
      final vehicle = _fiorino(parts: const []);
      expect(partsRatePerKm(vehicle), 0);
      expect(totalRatePerKm(vehicle), closeTo(0.7, 1e-9));
    });

    test('total é null quando o combustível não dá para calcular', () {
      // Devolver só as peças aqui mostraria R$ 0,119/km como "custo total" de
      // um carro que gasta R$ 0,819 — erra por sete vezes para menos.
      expect(totalRatePerKm(_fiorino(consumption: null)), isNull);
    });
  });

  group('KM rodado da rota', () {
    test('é a diferença entre o final e o inicial', () {
      expect(kmOf(_route(kmInitial: 1000, kmFinal: 1046.9)), closeTo(46.9, 1e-9));
    });

    test('diferença zero ou negativa é dado incompleto, devolve null', () {
      expect(kmOf(_route(kmInitial: 1000, kmFinal: 1000)), isNull);
      expect(kmOf(_route(kmInitial: 1000, kmFinal: 900)), isNull);
    });

    test('sem km informado devolve null', () {
      expect(kmOf(_route(kmInitial: null)), isNull);
      expect(kmOf(_route(kmFinal: null)), isNull);
    });
  });

  group('provisão da rota', () {
    test('reproduz a linha 3 de JUL da planilha, coluna por coluna', () {
      // A3=01/07/2026 · C3=152,50 · D3=46,9 km
      final p = provisionFor(_fiorino(), _route())!;

      expect(p.km, closeTo(46.9, 1e-9));
      expect(p.fuel, closeTo(32.83, 0.001)); // F3
      expect(p.parts['Óleo'], closeTo(0.938, 0.001)); // G3
      expect(p.parts['Pneu'], closeTo(1.876, 0.001)); // H3
      expect(p.parts['Bateria'], closeTo(0.6253333, 0.001)); // I3
      expect(p.parts['Freio'], closeTo(0.7504, 0.001)); // J3
      expect(p.parts['Geral'], closeTo(1.407, 0.001)); // K3
      expect(p.totalParts, closeTo(5.596733, 0.001)); // L3
      expect(p.profitFrom(152.50), closeTo(114.0732667, 0.001)); // O3
    });

    test('O TESTE ÂNCORA: 898,1 km dão R\$ 735,84 de custo total', () {
      // `X15` da planilha, a soma do mês inteiro. Se este teste passa, o app
      // reproduz a conta que o Wesley faz hoje no Excel.
      final p = provisionFor(
        _fiorino(),
        _route(value: 5000, kmInitial: 0, kmFinal: 898.1),
      )!;

      expect(p.total, closeTo(735.8432667, 0.01));
      expect(p.fuel, closeTo(628.67, 0.01)); // Z9
      expect(p.totalParts, closeTo(107.1732667, 0.01)); // Z10..Z14
    });

    test('totalParts não inclui a gasolina', () {
      final p = provisionFor(_fiorino(), _route())!;

      // A planilha soma `=SUM(G3:K3)`, de Óleo a Geral — a coluna F fica fora.
      expect(p.totalParts, lessThan(p.fuel));
      expect(p.totalParts, closeTo(p.parts.values.reduce((a, b) => a + b), 1e-9));
    });

    test('guarda o id do veículo que rodou', () {
      expect(provisionFor(_fiorino(), _route())!.vehicleId, 'v1');
    });

    test('sem KM rodado não há provisão', () {
      // `IF(AND($C3>0,$D3>0), …)` da planilha: linha 7 de JUL, o domingo parado.
      expect(provisionFor(_fiorino(), _route(kmInitial: null)), isNull);
      expect(provisionFor(_fiorino(), _route(kmFinal: 1000)), isNull);
    });

    test('sem valor não há provisão', () {
      expect(provisionFor(_fiorino(), _route(value: 0)), isNull);
      expect(provisionFor(_fiorino(), _route(value: -10)), isNull);
    });

    test('sem consumo informado não há provisão', () {
      // Um lucro que ignora 85% do custo é pior que lucro nenhum.
      expect(provisionFor(_fiorino(consumption: null), _route()), isNull);
    });

    test('peça incalculável não entra e não derruba a provisão', () {
      final vehicle = _fiorino(
        parts: const [
          MaintenancePart(name: 'Óleo', price: 200, lifeKm: 10000),
          MaintenancePart(name: 'Correia', price: 300),
        ],
      );
      final p = provisionFor(vehicle, _route())!;

      expect(p.parts.containsKey('Correia'), isFalse);
      expect(p.totalParts, closeTo(0.938, 0.001));
    });
  });

  group('RouteProvision — o retrato gravado', () {
    test('ida e volta preserva os valores em reais', () {
      final p = provisionFor(_fiorino(), _route())!;
      final back = RouteProvision.fromMap(p.toMap());

      expect(back.vehicleId, p.vehicleId);
      expect(back.km, closeTo(p.km, 1e-9));
      expect(back.fuel, closeTo(p.fuel, 1e-9));
      expect(back.totalParts, closeTo(p.totalParts, 1e-9));
      expect(back.parts.length, p.parts.length);
      expect(back.parts['Pneu'], closeTo(1.876, 0.001));
      expect(back.calculatedAt, p.calculatedAt);
    });

    test('guarda valores em reais, não a taxa', () {
      // É o que torna o retrato imune: taxa guardada é taxa que alguém edita.
      final map = provisionFor(_fiorino(), _route())!.toMap();

      expect(map.containsKey('ratePerKm'), isFalse);
      expect(map['fuel'], closeTo(32.83, 0.001));
    });

    test('lucro é derivado, não gravado', () {
      final map = provisionFor(_fiorino(), _route())!.toMap();
      expect(map.containsKey('profit'), isFalse);
    });

    test('mapa vindo com números inteiros do Firestore não lança', () {
      final back = RouteProvision.fromMap(const {
        'vehicleId': 'v1',
        'km': 40,
        'fuel': 28,
        'parts': {'Óleo': 1},
        'totalParts': 5,
        'calculatedAt': '2026-07-01T20:00:00.000',
      });

      expect(back.km, 40.0);
      expect(back.parts['Óleo'], 1.0);
    });

    test('mapa vazio não lança', () {
      expect(() => RouteProvision.fromMap(const {}), returnsNormally);
    });
  });
}
