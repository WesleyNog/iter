import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/fuelEconomy.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/widget/vehicleCard.dart';
import 'package:iter/widget/vehicleThumb.dart';

Vehicle _vehicle({
  VehicleType type = VehicleType.carro,
  String brandName = 'Fiat',
  String modelName = 'Fiorino Endurance 1.3',
  String? nickname = 'Fiorino do trabalho',
  int? year = 2020,
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
    brandName: brandName,
    modelCode: '1',
    modelName: modelName,
    year: year,
    nickname: nickname,
    fuel: FuelType.flex,
    fuelPrice: fuelPrice,
    consumption: consumption,
    imageUrl: imageUrl,
    photoBase64: photoBase64,
    parts: parts ?? Vehicle.defaultParts(type),
    createdAt: '2026-01-01T00:00:00.000',
  );
}

Future<void> _pump(
  WidgetTester tester,
  Vehicle vehicle, {
  bool isActive = false,
  VoidCallback? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VehicleCard(
          vehicle: vehicle,
          isActive: isActive,
          onTap: onTap,
        ),
      ),
    ),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('mostra apelido, ficha e taxa', (tester) async {
    await _pump(tester, _vehicle());

    expect(_text(tester, 'vehicle-card-name'), 'Fiorino do trabalho');
    expect(
      _text(tester, 'vehicle-card-subtitle'),
      'Fiat Fiorino Endurance 1.3 · 2020',
    );
    expect(_text(tester, 'vehicle-card-rate'), 'R\$ 0,8193 /km');
  });

  testWidgets('sem apelido cai no modelo', (tester) async {
    await _pump(tester, _vehicle(nickname: null));

    expect(_text(tester, 'vehicle-card-name'), 'Fiorino Endurance 1.3');
  });

  testWidgets('a sigla da FIPE não aparece para o usuário', (tester) async {
    // A FIPE devolve "VW - VolksWagen"; ninguém chama o carro assim.
    await _pump(
      tester,
      _vehicle(brandName: 'VW - VolksWagen', modelName: 'Saveiro 1.6'),
    );

    expect(
      _text(tester, 'vehicle-card-subtitle'),
      'VolksWagen Saveiro 1.6 · 2020',
    );
  });

  testWidgets('sem ano não deixa um " · " solto', (tester) async {
    await _pump(tester, _vehicle(year: null));

    expect(
      _text(tester, 'vehicle-card-subtitle'),
      'Fiat Fiorino Endurance 1.3',
    );
  });

  testWidgets('taxa incalculável mostra — e não um custo menor', (tester) async {
    await _pump(tester, _vehicle(consumption: null));

    expect(_text(tester, 'vehicle-card-rate'), '—');
  });

  testWidgets('selo EM USO só aparece no ativo', (tester) async {
    await _pump(tester, _vehicle(), isActive: true);
    expect(find.byKey(const Key('vehicle-card-active')), findsOneWidget);

    await _pump(tester, _vehicle());
    expect(find.byKey(const Key('vehicle-card-active')), findsNothing);
  });

  testWidgets('toque avisa quem montou o card', (tester) async {
    var tapped = 0;
    await _pump(tester, _vehicle(), onTap: () => tapped++);

    await tester.tap(find.byType(VehicleCard));
    await tester.pump();

    expect(tapped, 1);
  });

  group('VehicleThumb — a precedência da imagem', () {
    testWidgets('sem imagem nenhuma desenha a silhueta do tipo certo', (
      tester,
    ) async {
      await _pump(tester, _vehicle());
      expect(find.byIcon(Icons.directions_car_outlined), findsOneWidget);

      await _pump(tester, _vehicle(type: VehicleType.moto));
      expect(find.byIcon(Icons.two_wheeler_outlined), findsOneWidget);
    });

    testWidgets('a foto do dono ganha do render da CDN', (tester) async {
      // 1x1 PNG transparente.
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

      await _pump(
        tester,
        _vehicle(imageUrl: 'https://cdn/x.webp', photoBase64: png),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(base64Decode(png).isNotEmpty, isTrue);
      // Se o render tivesse ganho, a silhueta apareceria no lugar da foto,
      // porque em teste a rede devolve erro.
      expect(find.byIcon(Icons.directions_car_outlined), findsNothing);
    });

    testWidgets('base64 corrompido cai na silhueta em vez de quebrar', (
      tester,
    ) async {
      await _pump(tester, _vehicle(photoBase64: 'não é base64 de imagem'));
      await tester.pump();

      expect(find.byIcon(Icons.directions_car_outlined), findsOneWidget);
    });

    testWidgets('sem veículo nenhum ainda desenha algo', (tester) async {
      // A AppBar monta o thumb antes de o stream responder.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: VehicleThumb(vehicle: null, size: 32)),
        ),
      );

      expect(find.byIcon(Icons.directions_car_outlined), findsOneWidget);
    });
  });

  group('consumptionLine — cadastrado e medido lado a lado', () {
    EconomyResult ok(double kmPerLiter, {int fills = 3}) => (
      economy: (
        fuel: SupplyFuel.gasolina,
        kmPerLiter: kmPerLiter,
        km: 800,
        liters: 800 / kmPerLiter,
        fills: fills,
      ),
      gap: null,
      missing: 0,
    );

    EconomyResult gap(EconomyGap g, int missing) =>
        (economy: null, gap: g, missing: missing);

    test('os dois números aparecem juntos', () {
      // O ponto é justamente ver a diferença: o cadastrado alimenta a provisão
      // de toda rota, o medido é o que o carro faz.
      expect(
        consumptionLine(_vehicle(consumption: 10), {SupplyFuel.gasolina: ok(10.96)}),
        '10,00 km/l no cadastro · 10,96 medido',
      );
    });

    test('com um combustível só, não repete o nome dele', () {
      final linha = consumptionLine(
        _vehicle(consumption: 10),
        {SupplyFuel.gasolina: ok(10.96)},
      )!;

      expect(linha, isNot(contains('gasolina')));
    });

    test('com dois combustíveis, cada um é nomeado', () {
      final linha = consumptionLine(_vehicle(consumption: 10), {
        SupplyFuel.gasolina: ok(10.96),
        SupplyFuel.etanol: (
          economy: (
            fuel: SupplyFuel.etanol,
            kmPerLiter: 8,
            km: 400,
            liters: 50,
            fills: 3,
          ),
          gap: null,
          missing: 0,
        ),
      })!;

      expect(linha, contains('gasolina 10,96'));
      expect(linha, contains('etanol 8,00'));
    });

    test('sem medição, mostra só o cadastrado', () {
      expect(
        consumptionLine(_vehicle(consumption: 10), null),
        '10,00 km/l no cadastro',
      );
    });

    test('sem cadastro e sem abastecimento, não há linha', () {
      // Sem nada a dizer, a linha seria ruído.
      expect(consumptionLine(_vehicle(consumption: null), null), isNull);
      expect(consumptionLine(_vehicle(consumption: null), const {}), isNull);
    });

    test('com abastecimento mas sem medir, diz o que destrava', () {
      expect(
        consumptionLine(_vehicle(consumption: null), {
          SupplyFuel.gasolina: gap(EconomyGap.semKm, 2),
        }),
        contains('Informe o KM'),
      );
    });

    test('com cadastro, a dica não rouba o lugar do número', () {
      // Ele já tem um consumo configurado; a dica viraria ruído no card.
      expect(
        consumptionLine(_vehicle(consumption: 10), {
          SupplyFuel.gasolina: gap(EconomyGap.semKm, 2),
        }),
        '10,00 km/l no cadastro',
      );
    });
  });

  testWidgets('o card mostra a linha de consumo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VehicleCard(
            vehicle: _vehicle(consumption: 10),
            economy: {
              SupplyFuel.gasolina: (
                economy: (
                  fuel: SupplyFuel.gasolina,
                  kmPerLiter: 10.96,
                  km: 800,
                  liters: 73,
                  fills: 3,
                ),
                gap: null,
                missing: 0,
              ),
            },
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('vehicle-card-consumption'))).data,
      '10,00 km/l no cadastro · 10,96 medido',
    );
  });

  testWidgets('sem economia, o card não desenha a linha vazia', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VehicleCard(vehicle: _vehicle(consumption: null))),
      ),
    );

    expect(find.byKey(const Key('vehicle-card-consumption')), findsNothing);
  });
}
