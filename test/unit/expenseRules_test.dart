import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/expenseRules.dart';
import 'package:iter/Utils/fuelEconomy.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/model/vehicle.dart';

Vehicle _flexFit({double? consumption = 10, FuelType fuel = FuelType.flex}) {
  return Vehicle(
    id: 'v1',
    type: VehicleType.carro,
    brandCode: '25',
    brandName: 'Honda',
    modelCode: '1',
    modelName: 'Fit EXL 1.5',
    nickname: 'Fit',
    fuel: fuel,
    fuelPrice: 7,
    consumption: consumption,
    parts: Vehicle.defaultParts(VehicleType.carro),
    createdAt: '2026-01-01T00:00:00.000',
  );
}

FuelEconomy _economy({
  SupplyFuel fuel = SupplyFuel.gasolina,
  double kmPerLiter = 10.96,
  int fills = 3,
}) {
  return (
    fuel: fuel,
    kmPerLiter: kmPerLiter,
    km: 800,
    liters: 800 / kmPerLiter,
    fills: fills,
  );
}

Vehicle _fit({List<MaintenancePart>? parts}) {
  return Vehicle(
    id: 'v1',
    type: VehicleType.carro,
    brandCode: '25',
    brandName: 'Honda',
    modelCode: '1',
    modelName: 'Fit EXL 1.5',
    nickname: 'Fit',
    fuel: FuelType.flex,
    fuelPrice: 7,
    consumption: 10,
    parts: parts ?? Vehicle.defaultParts(VehicleType.carro),
    createdAt: '2026-01-01T00:00:00.000',
  );
}

Maintenance _m({
  MaintenanceItem item = MaintenanceItem.pneu,
  MaintenanceAction action = MaintenanceAction.substituicao,
  double value = 2400,
}) {
  return Maintenance(
    id: 'm1',
    item: item,
    action: action,
    value: value,
    date: '2026-08-06T10:00:00.000',
    createdAt: '2026-08-06T10:00:00.000',
  );
}

void main() {
  group('matchingPart — achar a peça do cadastro', () {
    test('acha pelo nome exato', () {
      expect(matchingPart(_fit(), MaintenanceItem.pneu)!.name, 'Pneu');
      expect(matchingPart(_fit(), MaintenanceItem.oleoMotor)!.name, 'Óleo');
      expect(matchingPart(_fit(), MaintenanceItem.pastilhaFreio)!.name, 'Freio');
      expect(matchingPart(_fit(), MaintenanceItem.bateria)!.name, 'Bateria');
    });

    test('ignora acento e caixa — a lista de peças é editável', () {
      // Quem criou a peça digitando "OLEO" continua sendo entendido.
      final v = _fit(
        parts: const [MaintenancePart(name: 'OLEO', price: 200, lifeKm: 10000)],
      );

      expect(matchingPart(v, MaintenanceItem.oleoMotor)!.price, 200);
    });

    test('item sem peça correspondente devolve null', () {
      expect(matchingPart(_fit(), MaintenanceItem.funilaria), isNull);
      expect(matchingPart(_fit(), MaintenanceItem.revisao), isNull);
      expect(matchingPart(_fit(), MaintenanceItem.outros), isNull);
    });

    test('peça renomeada quebra o vínculo, e é o certo', () {
      // "Freio" virou "Pastilha": são nomes diferentes, e adivinhar seria pior
      // do que não oferecer nada.
      final v = _fit(
        parts: const [MaintenancePart(name: 'Pastilha', price: 200, lifeKm: 50000)],
      );

      expect(matchingPart(v, MaintenanceItem.pastilhaFreio), isNull);
    });

    test('veículo sem peça nenhuma devolve null', () {
      expect(matchingPart(_fit(parts: const []), MaintenanceItem.pneu), isNull);
    });
  });

  group('unitPriceFor — o valor dividido pela quantidade', () {
    test('R\$ 2.400 de pneu num carro de 4 rodas dá R\$ 600 cada', () {
      expect(unitPriceFor(_fit(), _m())!, closeTo(600, 1e-9));
    });

    test('peça de quantidade 1 não divide', () {
      expect(
        unitPriceFor(_fit(), _m(item: MaintenanceItem.bateria, value: 900))!,
        closeTo(900, 1e-9),
      );
    });

    test('moto divide por 2', () {
      final moto = _fit(parts: Vehicle.defaultParts(VehicleType.moto));
      expect(unitPriceFor(moto, _m(value: 800))!, closeTo(400, 1e-9));
    });

    test('sem peça correspondente devolve null', () {
      expect(unitPriceFor(_fit(), _m(item: MaintenanceItem.funilaria)), isNull);
    });

    test('valor zero devolve null', () {
      expect(unitPriceFor(_fit(), _m(value: 0)), isNull);
    });
  });

  group('shouldOfferPartUpdate — quando vale perguntar', () {
    test('substituição com preço diferente, oferece', () {
      // Pneu do cadastro está em R$ 500; a troca saiu a R$ 600 por unidade.
      expect(shouldOfferPartUpdate(_fit(), _m()), isTrue);
    });

    test('REPARO nunca oferece', () {
      // O motivo do toggle existir: consertar um pneu por R$ 80 não é o preço
      // de um pneu novo, e aceitar isso destruiria a provisão.
      expect(
        shouldOfferPartUpdate(
          _fit(),
          _m(action: MaintenanceAction.reparo, value: 80),
        ),
        isFalse,
      );
    });

    test('reparo caro também não oferece', () {
      expect(
        shouldOfferPartUpdate(
          _fit(),
          _m(action: MaintenanceAction.reparo, value: 5000),
        ),
        isFalse,
      );
    });

    test('item sem peça correspondente não oferece', () {
      expect(
        shouldOfferPartUpdate(_fit(), _m(item: MaintenanceItem.funilaria)),
        isFalse,
      );
      expect(
        shouldOfferPartUpdate(_fit(), _m(item: MaintenanceItem.revisao)),
        isFalse,
      );
    });

    test('sem veículo não oferece', () {
      expect(shouldOfferPartUpdate(null, _m()), isFalse);
    });

    test('preço praticamente igual não incomoda', () {
      // R$ 2.000 ÷ 4 = R$ 500, que é exatamente o que está no cadastro.
      expect(shouldOfferPartUpdate(_fit(), _m(value: 2000)), isFalse);
    });

    test('peça sem preço no cadastro, oferece', () {
      final v = _fit(
        parts: const [MaintenancePart(name: 'Pneu', lifeKm: 50000, quantity: 4)],
      );

      expect(shouldOfferPartUpdate(v, _m()), isTrue);
    });

    test('valor zero não oferece', () {
      expect(shouldOfferPartUpdate(_fit(), _m(value: 0)), isFalse);
    });
  });

  group('shouldOfferConsumptionUpdate — a terceira das três', () {
    test('com três abastecimentos e valor diferente, oferece', () {
      expect(shouldOfferConsumptionUpdate(_flexFit(), _economy()), isTrue);
    });

    test('com dois abastecimentos ainda não oferece', () {
      // O número já **aparece** na tela com dois; mudar a provisão de toda
      // rota futura com uma leitura só seria decidir no ruído.
      expect(
        shouldOfferConsumptionUpdate(_flexFit(), _economy(fills: 2)),
        isFalse,
      );
    });

    test('veículo sem consumo cadastrado, oferece', () {
      expect(
        shouldOfferConsumptionUpdate(_flexFit(consumption: null), _economy()),
        isTrue,
      );
    });

    test('valor praticamente igual não incomoda', () {
      // O medido varia na terceira casa a cada abastecimento; sem a folga o
      // app perguntaria sempre.
      expect(
        shouldOfferConsumptionUpdate(
          _flexFit(consumption: 10.98),
          _economy(kmPerLiter: 10.96),
        ),
        isFalse,
      );
    });

    test('flex oferece para gasolina e para etanol', () {
      // Só o motorista sabe qual dos dois o consumo do cadastro representa.
      final flex = _flexFit();

      expect(shouldOfferConsumptionUpdate(flex, _economy()), isTrue);
      expect(
        shouldOfferConsumptionUpdate(
          flex,
          _economy(fuel: SupplyFuel.etanol, kmPerLiter: 8),
        ),
        isTrue,
      );
    });

    test('combustível único não aceita medição de outro líquido', () {
      // O consumo com etanol não descreve um carro que roda a gasolina.
      expect(
        shouldOfferConsumptionUpdate(
          _flexFit(fuel: FuelType.gasolina),
          _economy(fuel: SupplyFuel.etanol, kmPerLiter: 8),
        ),
        isFalse,
      );
    });

    test('combustível único aceita a medição do próprio líquido', () {
      expect(
        shouldOfferConsumptionUpdate(
          _flexFit(fuel: FuelType.gasolina),
          _economy(),
        ),
        isTrue,
      );
    });

    test('sem veículo não oferece', () {
      expect(shouldOfferConsumptionUpdate(null, _economy()), isFalse);
    });

    test('consumo zerado não oferece', () {
      expect(
        shouldOfferConsumptionUpdate(_flexFit(), _economy(kmPerLiter: 0)),
        isFalse,
      );
    });
  });
}
