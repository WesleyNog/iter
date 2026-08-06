import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/vehicle.dart';

/// Um veículo completo, para os testes declararem só o que estão examinando.
Vehicle _vehicle({
  VehicleType type = VehicleType.carro,
  String? nickname = 'Fiorino do trabalho',
  FuelType fuel = FuelType.flex,
  double? fuelPrice = 7.0,
  double? consumption = 10.0,
  String? imageUrl,
  String? photoBase64,
  List<MaintenancePart>? parts,
}) {
  return Vehicle(
    id: 'v1',
    type: type,
    brandCode: '21',
    brandName: 'Fiat',
    modelCode: '4828',
    modelName: 'Fiorino Endurance 1.4 Flex 8V',
    yearCode: '2020-1',
    year: 2020,
    nickname: nickname,
    fuel: fuel,
    fuelPrice: fuelPrice,
    consumption: consumption,
    imageUrl: imageUrl,
    photoBase64: photoBase64,
    parts: parts ?? Vehicle.defaultParts(type),
    createdAt: '2026-08-05T10:00:00.000',
  );
}

void main() {
  group('MaintenancePart', () {
    test('ida e volta preserva todos os campos', () {
      const part = MaintenancePart(
        name: 'Pneu',
        price: 500,
        lifeKm: 50000,
        quantity: 4,
      );

      final back = MaintenancePart.fromMap(part.toMap());

      expect(back.name, 'Pneu');
      expect(back.price, 500);
      expect(back.lifeKm, 50000);
      expect(back.quantity, 4);
      expect(back.fixedRate, isNull);
    });

    test('peça de taxa direta preserva o fixedRate', () {
      const part = MaintenancePart(name: 'Geral', fixedRate: 0.03);
      final back = MaintenancePart.fromMap(part.toMap());

      expect(back.fixedRate, 0.03);
      expect(back.price, isNull);
      expect(back.lifeKm, isNull);
    });

    test('documento sem quantity assume 1', () {
      final part = MaintenancePart.fromMap({
        'name': 'Óleo',
        'price': 200,
        'lifeKm': 10000,
      });

      expect(part.quantity, 1);
    });

    test('números inteiros do Firestore viram double', () {
      // O Firestore devolve `int` quando o valor gravado não tem casa decimal;
      // um cast direto para double lançaria.
      final part = MaintenancePart.fromMap({
        'name': 'Pneu',
        'price': 500,
        'lifeKm': 50000,
        'quantity': 4,
      });

      expect(part.price, isA<double>());
      expect(part.lifeKm, isA<double>());
    });

    test('mapa sem nome não lança, vira peça sem nome', () {
      expect(() => MaintenancePart.fromMap(const {}), returnsNormally);
      expect(MaintenancePart.fromMap(const {}).name, '');
    });
  });

  group('Vehicle', () {
    test('ida e volta preserva todos os campos', () {
      final vehicle = _vehicle(imageUrl: 'https://cdn/x.webp');
      final back = Vehicle.fromMap(vehicle.toMap());

      expect(back.id, vehicle.id);
      expect(back.type, VehicleType.carro);
      expect(back.brandName, 'Fiat');
      expect(back.modelName, 'Fiorino Endurance 1.4 Flex 8V');
      expect(back.year, 2020);
      expect(back.nickname, 'Fiorino do trabalho');
      expect(back.fuel, FuelType.flex);
      expect(back.fuelPrice, 7.0);
      expect(back.consumption, 10.0);
      expect(back.imageUrl, 'https://cdn/x.webp');
      expect(back.parts.length, vehicle.parts.length);
      expect(back.createdAt, vehicle.createdAt);
    });

    test('enum é gravado como string bare, sem o nome do tipo', () {
      final map = _vehicle(type: VehicleType.moto, fuel: FuelType.diesel).toMap();

      expect(map['type'], 'moto');
      expect(map['fuel'], 'diesel');
    });

    test('documento sem parts vira lista vazia, não lança', () {
      final vehicle = Vehicle.fromMap({
        'id': 'v1',
        'type': 'carro',
        'brandName': 'Fiat',
        'modelName': 'Fiorino',
        'createdAt': '2026-08-05T10:00:00.000',
      });

      expect(vehicle.parts, isEmpty);
    });

    test('enum desconhecido cai no padrão em vez de lançar', () {
      // Documento gravado por uma versão futura, ou corrompido: não pode
      // derrubar a lista inteira de veículos.
      final vehicle = Vehicle.fromMap({
        'id': 'v1',
        'type': 'caminhao',
        'fuel': 'hidrogenio',
        'brandName': 'Fiat',
        'modelName': 'Fiorino',
        'createdAt': '2026-08-05T10:00:00.000',
      });

      expect(vehicle.type, VehicleType.carro);
      expect(vehicle.fuel, FuelType.flex);
    });

    test('mapa praticamente vazio não lança', () {
      expect(() => Vehicle.fromMap(const {}), returnsNormally);
    });

    test('brandLabel tira o prefixo que a FIPE usa', () {
      expect(Vehicle.brandLabel('VW - VolksWagen'), 'VolksWagen');
      expect(Vehicle.brandLabel('GM - Chevrolet'), 'Chevrolet');
      expect(Vehicle.brandLabel('Fiat'), 'Fiat');
    });

    test('displayName usa o apelido e cai no modelo quando não há', () {
      expect(_vehicle().displayName, 'Fiorino do trabalho');
      expect(_vehicle(nickname: null).displayName, 'Fiorino Endurance 1.4 Flex 8V');
      expect(_vehicle(nickname: '  ').displayName, 'Fiorino Endurance 1.4 Flex 8V');
    });
  });

  group('Vehicle.defaultParts — os valores da planilha', () {
    test('carro traz as cinco peças com os números do Wesley', () {
      final parts = Vehicle.defaultParts(VehicleType.carro);
      final byName = {for (final p in parts) p.name: p};

      expect(byName.keys, containsAll(['Óleo', 'Pneu', 'Bateria', 'Freio', 'Geral']));

      expect(byName['Óleo']!.price, 200);
      expect(byName['Óleo']!.lifeKm, 10000);
      expect(byName['Óleo']!.quantity, 1);

      expect(byName['Pneu']!.price, 500);
      expect(byName['Pneu']!.lifeKm, 50000);
      expect(byName['Pneu']!.quantity, 4);

      expect(byName['Bateria']!.price, 800);
      expect(byName['Bateria']!.lifeKm, 60000);
      expect(byName['Bateria']!.quantity, 1);

      expect(byName['Freio']!.price, 200);
      expect(byName['Freio']!.lifeKm, 50000);
      expect(byName['Freio']!.quantity, 4);

      // A "Geral" da planilha é taxa digitada direto, sem preço nem vida útil.
      expect(byName['Geral']!.fixedRate, 0.03);
      expect(byName['Geral']!.price, isNull);
      expect(byName['Geral']!.lifeKm, isNull);
    });

    test('moto usa 2 pneus e 2 freios', () {
      final byName = {
        for (final p in Vehicle.defaultParts(VehicleType.moto)) p.name: p,
      };

      expect(byName['Pneu']!.quantity, 2);
      expect(byName['Freio']!.quantity, 2);
      expect(byName['Óleo']!.quantity, 1);
    });
  });
}
