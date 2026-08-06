import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/expenseRules.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/screens/addSupply.dart';
import 'package:iter/services/location.dart';
import 'package:iter/services/overpass.dart';

Vehicle _vehicle({
  String id = 'v1',
  FuelType fuel = FuelType.flex,
  double? fuelPrice = 7.0,
  String? nickname = 'Fit',
}) {
  return Vehicle(
    id: id,
    type: VehicleType.carro,
    brandCode: '25',
    brandName: 'Honda',
    modelCode: '1',
    modelName: 'Fit EXL 1.5',
    nickname: nickname,
    fuel: fuel,
    fuelPrice: fuelPrice,
    consumption: 10,
    createdAt: '2026-01-01T00:00:00.000',
  );
}

const _station = FuelStation(
  id: 'way-1',
  name: 'Posto Apiguana',
  lat: -3.73,
  lng: -38.52,
);

/// Monta a tela sem Firestore, sem GPS e sem rede.
Future<void> _pump(
  WidgetTester tester, {
  List<Vehicle>? vehicles,
  Vehicle? active,
  List<NearbyStation>? stations,
  LocationFailure? failure,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AddSupply(
        uid: 'u1',
        vehiclesLoader: () async => (
          all: vehicles ?? const <Vehicle>[],
          active: active,
        ),
        stationsLoader: () async => (
          stations: stations,
          lat: stations == null ? null : -3.73,
          lng: stations == null ? null : -38.52,
          failure: failure,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _price(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('supply-price'))).data!;

void main() {
  group('preço do litro — o número que ele confere com a bomba', () {
    testWidgets('reage a valor e litros ao digitar', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byKey(const Key('supply-value')), '25000');
      await tester.enterText(find.byKey(const Key('supply-liters')), '39,75');
      await tester.pump();

      // R$ 250,00 ÷ 39,75 L
      expect(_price(tester), 'R\$ 6,2893/L');
    });

    testWidgets('sem litros mostra — e não zero', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byKey(const Key('supply-value')), '25000');
      await tester.pump();

      expect(_price(tester), '—');
    });

    testWidgets('litros zero não vira divisão por zero', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byKey(const Key('supply-value')), '25000');
      await tester.enterText(find.byKey(const Key('supply-liters')), '0');
      await tester.pump();

      expect(_price(tester), '—');
    });

    testWidgets('litros com ponto é lido como decimal', (tester) async {
      // O teclado do celular oferece ponto. "39.75 L" é 39,75 litros — tratar
      // como milhar daria 3975 L e um preço de seis centavos.
      await _pump(tester);

      await tester.enterText(find.byKey(const Key('supply-value')), '25000');
      await tester.enterText(find.byKey(const Key('supply-liters')), '39.75');
      await tester.pump();

      expect(_price(tester), 'R\$ 6,2893/L');
    });

    testWidgets('o campo do preço não é digitável', (tester) async {
      // É o ponto do requisito: quem calcula é o app, para ele conferir com o
      // painel. Campo digitável convidaria a corrigir o resultado em vez de
      // conferir a conta.
      await _pump(tester);

      expect(find.byKey(const Key('supply-price')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('supply-price')),
          matching: find.byType(EditableText),
        ),
        findsNothing,
      );
    });
  });

  group('validação', () {
    testWidgets('valor vazio bloqueia o salvamento', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('supply-save')));
      await tester.pump();

      expect(find.text('Informe o valor'), findsOneWidget);
    });

    testWidgets('litros vazio não bloqueia — é opcional', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byKey(const Key('supply-value')), '25000');
      await tester.tap(find.byKey(const Key('supply-save')));
      await tester.pump();

      expect(find.text('Informe o valor'), findsNothing);
    });
  });

  group('combustível', () {
    testWidgets('veículo flex mostra o seletor', (tester) async {
      final flex = _vehicle(fuel: FuelType.flex);
      await _pump(tester, vehicles: [flex], active: flex);

      expect(find.byKey(const Key('supply-fuel')), findsOneWidget);
    });

    testWidgets('veículo de combustível único não pergunta', (tester) async {
      // Perguntar aqui seria pedir para errar: o carro só aceita um líquido.
      final diesel = _vehicle(fuel: FuelType.diesel);
      await _pump(tester, vehicles: [diesel], active: diesel);

      expect(find.byKey(const Key('supply-fuel')), findsNothing);
    });

    testWidgets('sem veículo nenhum também não pergunta', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('supply-fuel')), findsNothing);
      expect(find.byKey(const Key('supply-vehicle')), findsNothing);
    });
  });

  group('posto', () {
    testWidgets('com localização, lista os postos', (tester) async {
      await _pump(
        tester,
        stations: [(station: _station, meters: 325)],
      );

      expect(find.text('Posto Apiguana'), findsOneWidget);
      expect(find.byKey(const Key('station-error')), findsNothing);
    });

    testWidgets('sem permissão, o formulário continua inteiro', (tester) async {
      // O gasto é dele: GPS negado não pode impedir de anotar.
      await _pump(tester, failure: LocationFailure.denied);

      expect(find.byKey(const Key('station-error')), findsOneWidget);
      expect(find.byKey(const Key('supply-value')), findsOneWidget);
      expect(find.byKey(const Key('supply-save')), findsOneWidget);
      expect(find.byKey(const Key('station-other')), findsOneWidget);
    });

    testWidgets('permissão bloqueada oferece os ajustes', (tester) async {
      await _pump(tester, failure: LocationFailure.deniedForever);

      expect(find.byKey(const Key('station-settings')), findsOneWidget);
    });

    testWidgets('escolher "Outro" revela o campo de texto', (tester) async {
      await _pump(tester, stations: [(station: _station, meters: 325)]);

      await tester.tap(find.byKey(const Key('station-other')));
      await tester.pump();

      expect(find.byKey(const Key('station-typed')), findsOneWidget);
    });
  });

  group('shouldOfferPriceUpdate — quando vale perguntar', () {
    Supply supply({
      double value = 250,
      double? liters = 39.75,
      SupplyFuel fuel = SupplyFuel.gasolina,
    }) => Supply(
      id: 's1',
      value: value,
      liters: liters,
      fuel: fuel,
      date: '2026-08-05T21:00:00.000',
      createdAt: '2026-08-05T21:00:00.000',
    );

    test('preço diferente do gravado, oferece', () {
      expect(shouldOfferPriceUpdate(_vehicle(fuelPrice: 7.0), supply()), isTrue);
    });

    test('veículo sem preço, oferece', () {
      expect(
        shouldOfferPriceUpdate(_vehicle(fuelPrice: null), supply()),
        isTrue,
      );
    });

    test('preço praticamente igual não incomoda', () {
      // O preço vem de uma divisão e quase nunca bate na terceira casa; sem a
      // folga, o app perguntaria a cada abastecimento.
      final v = _vehicle(fuelPrice: 6.2893);
      expect(shouldOfferPriceUpdate(v, supply()), isFalse);
    });

    test('sem litros não há preço para oferecer', () {
      expect(
        shouldOfferPriceUpdate(_vehicle(), supply(liters: null)),
        isFalse,
      );
    });

    test('sem veículo não oferece', () {
      expect(shouldOfferPriceUpdate(null, supply()), isFalse);
    });

    test('combustível diferente do que o carro usa não oferece', () {
      // Encher o tanque de diesel de um carro emprestado não pode
      // reprecificar a gasolina do carro dele.
      expect(
        shouldOfferPriceUpdate(
          _vehicle(fuel: FuelType.gasolina),
          supply(fuel: SupplyFuel.diesel),
        ),
        isFalse,
      );
    });

    test('flex oferece para gasolina e para etanol', () {
      // Só o motorista sabe qual dos dois o preço do cadastro representa — a
      // tela mostra qual foi o combustível para a escolha ser informada.
      final flex = _vehicle(fuel: FuelType.flex);

      expect(shouldOfferPriceUpdate(flex, supply()), isTrue);
      expect(
        shouldOfferPriceUpdate(flex, supply(fuel: SupplyFuel.etanol)),
        isTrue,
      );
    });
  });
}
