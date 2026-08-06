import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/model/vehicle.dart';

Supply _supply({
  String? vehicleId = 'v1',
  double value = 250,
  double? liters = 39.75,
  SupplyFuel fuel = SupplyFuel.gasolina,
  double? odometer = 128500,
  FuelStation? station,
  double? lat,
  double? lng,
}) {
  return Supply(
    id: 's1',
    vehicleId: vehicleId,
    value: value,
    liters: liters,
    fuel: fuel,
    odometer: odometer,
    station: station,
    lat: lat,
    lng: lng,
    date: '2026-08-05T21:00:00.000',
    createdAt: '2026-08-05T21:05:00.000',
  );
}

const _station = FuelStation(
  id: 'way-123456',
  name: 'Posto Apiguana',
  brand: 'Ipiranga',
  lat: -3.7319,
  lng: -38.5267,
);

void main() {
  group('preço do litro — o número que ele confere com a bomba', () {
    test('é o valor dividido pelos litros', () {
      expect(_supply(value: 250, liters: 39.75).pricePerLiter, closeTo(6.2893, 0.0001));
    });

    test('sem litros informados é null, não zero', () {
      // Litros é opcional: quem não anotou não "pagou zero por litro".
      expect(_supply(liters: null).pricePerLiter, isNull);
    });

    test('litros zero é null, nunca infinito', () {
      expect(_supply(liters: 0).pricePerLiter, isNull);
      expect(_supply(liters: -1).pricePerLiter, isNull);
    });

    test('não é gravado — é derivado em uma linha', () {
      // Valor derivado que se grava um dia discorda da origem. Mesma decisão de
      // `RouteProvision.profitFrom`.
      expect(_supply().toMap().containsKey('pricePerLiter'), isFalse);
    });
  });

  group('ida e volta', () {
    test('preserva todos os campos', () {
      final supply = _supply(station: _station, lat: -3.73, lng: -38.52);
      final back = Supply.fromMap(supply.toMap());

      expect(back.id, 's1');
      expect(back.vehicleId, 'v1');
      expect(back.value, 250);
      expect(back.liters, 39.75);
      expect(back.fuel, SupplyFuel.gasolina);
      expect(back.odometer, 128500);
      expect(back.lat, -3.73);
      expect(back.lng, -38.52);
      expect(back.date, supply.date);
      expect(back.createdAt, supply.createdAt);
    });

    test('preserva o posto aninhado', () {
      final back = Supply.fromMap(_supply(station: _station).toMap());

      expect(back.station!.id, 'way-123456');
      expect(back.station!.name, 'Posto Apiguana');
      expect(back.station!.brand, 'Ipiranga');
      expect(back.station!.lat, closeTo(-3.7319, 1e-9));
      expect(back.station!.lng, closeTo(-38.5267, 1e-9));
    });

    test('sem posto, o campo fica nulo e não lança', () {
      final back = Supply.fromMap(_supply().toMap());
      expect(back.station, isNull);
    });

    test('enum vai como string bare', () {
      expect(_supply(fuel: SupplyFuel.etanol).toMap()['fuel'], 'etanol');
    });
  });

  group('leitura defensiva', () {
    test('mapa praticamente vazio não lança', () {
      expect(() => Supply.fromMap(const {}), returnsNormally);
      expect(Supply.fromMap(const {}).value, 0);
    });

    test('combustível desconhecido cai no padrão em vez de derrubar a lista', () {
      final supply = Supply.fromMap(const {
        'id': 's1',
        'value': 100,
        'fuel': 'querosene',
        'date': '2026-08-05T21:00:00.000',
      });

      expect(supply.fuel, SupplyFuel.gasolina);
    });

    test('posto corrompido vira null sem derrubar o abastecimento', () {
      final supply = Supply.fromMap({
        ..._supply().toMap(),
        'station': 'lixo',
      });

      expect(supply.station, isNull);
      expect(supply.value, 250);
    });

    test('inteiro do Firestore vira double', () {
      // O Firestore devolve `int` quando o valor não tem casa decimal.
      final supply = Supply.fromMap(const {
        'id': 's1',
        'value': 250,
        'liters': 40,
        'odometer': 128500,
        'date': '2026-08-05T21:00:00.000',
      });

      expect(supply.value, isA<double>());
      expect(supply.liters, isA<double>());
      expect(supply.pricePerLiter, closeTo(6.25, 1e-9));
    });
  });

  group('SupplyFuel.fromVehicle — de onde vem o combustível', () {
    test('veículo de combustível único não precisa perguntar', () {
      expect(SupplyFuel.fromVehicle(FuelType.gasolina), SupplyFuel.gasolina);
      expect(SupplyFuel.fromVehicle(FuelType.etanol), SupplyFuel.etanol);
      expect(SupplyFuel.fromVehicle(FuelType.diesel), SupplyFuel.diesel);
      expect(SupplyFuel.fromVehicle(FuelType.eletrico), SupplyFuel.eletrico);
    });

    test('flex devolve null — só o motorista sabe qual bomba usou', () {
      // É o tipo dizendo "pergunte": o seletor da tela existe por causa deste
      // `null`, e não de um `if` espalhado no formulário.
      expect(SupplyFuel.fromVehicle(FuelType.flex), isNull);
    });

    test('sem veículo também devolve null', () {
      expect(SupplyFuel.fromVehicle(null), isNull);
    });
  });

  group('FuelStation.label — nome e bandeira', () {
    FuelStation station({String name = '', String? brand}) =>
        FuelStation(id: 'node-1', name: name, brand: brand, lat: 0, lng: 0);

    test('com os dois, junta com barra', () {
      // A bandeira vem de graça na resposta da Overpass — mostrar não custa
      // requisição nenhuma, ao contrário do logo de verdade.
      expect(
        station(name: 'Posto Vila III', brand: 'BR').label,
        'Posto Vila III | BR',
      );
    });

    test('só nome fica só o nome', () {
      expect(station(name: 'Posto Apiguana').label, 'Posto Apiguana');
    });

    test('só bandeira vira o rótulo', () {
      expect(station(brand: 'Ipiranga').label, 'Ipiranga');
    });

    test('sem nada, "Posto sem nome"', () {
      expect(station().label, 'Posto sem nome');
    });

    test('nome que já cita a bandeira não repete', () {
      // Muito posto do OSM já vem assim da fonte.
      expect(
        station(name: 'Posto Cidade Jardim | Shell', brand: 'Shell').label,
        'Posto Cidade Jardim | Shell',
      );
    });

    test('a comparação ignora acento e caixa', () {
      expect(
        station(name: 'Auto Posto IPIRANGA', brand: 'Ipiranga').label,
        'Auto Posto IPIRANGA',
      );
    });

    test('bandeira curta não some dentro de outra palavra', () {
      // Com `contains`, "BR" casaria dentro de "Brasil" e a bandeira sumiria
      // justamente onde ela acrescentava informação.
      expect(
        station(name: 'Posto Brasil', brand: 'BR').label,
        'Posto Brasil | BR',
      );
      expect(
        station(name: 'Posto Alegre', brand: 'Ale').label,
        'Posto Alegre | Ale',
      );
    });

    test('bandeira como palavra inteira é reconhecida', () {
      expect(station(name: 'BR Aldeota', brand: 'BR').label, 'BR Aldeota');
    });

    test('espaços em branco não viram rótulo', () {
      expect(station(name: '   ', brand: '  ').label, 'Posto sem nome');
      expect(station(name: '  Posto X  ').label, 'Posto X');
    });
  });
}
