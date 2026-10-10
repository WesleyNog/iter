import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/expenseRules.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/screens/addSupply.dart';
import 'package:iter/screens/stationsScreen.dart';
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
  Future<void> Function(String uid, Supply supply)? saver,
  Future<StationChoice?> Function(BuildContext, StationChoice?)? stationPicker,
  Supply? supply,
  Future<void> Function(String uid, Supply supply)? updater,
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
        saver: saver,
        stationPicker: stationPicker,
        supply: supply,
        updater: updater,
      ),
      // O caminho de salvamento passa por `EasyLoading.show`, e o overlay dele
      // é instalado por este builder — como em `main.dart`.
      builder: EasyLoading.init(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Captura o que o formulário manda gravar, sem tocar no Firestore.
class _Gravacao {
  Supply? supply;
  int chamadas = 0;

  Future<void> call(String uid, Supply saved) async {
    chamadas++;
    supply = saved;
  }
}

/// Preenche o valor e salva, esperando o aviso de sucesso sair da tela.
Future<void> _save(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('supply-value')), '25000');
  await tester.tap(find.byKey(const Key('supply-save')));
  await tester.pumpAndSettle();
  // O toast de sucesso some sozinho; sem isto o timer dele fica pendente.
  await tester.pump(const Duration(seconds: 10));
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _ddMMyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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

  group('data — quem registra no dia seguinte', () {
    testWidgets('começa em hoje', (tester) async {
      await _pump(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('supply-date')),
          matching: find.textContaining(_ddMMyyyy(_today())),
        ),
        findsOneWidget,
      );
    });

    testWidgets('o seletor não deixa escolher o futuro', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('supply-date')));
      await tester.pumpAndSettle();

      final picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      final max = picker.maximumDate!;
      expect(DateTime(max.year, max.month, max.day), _today());
    });

    testWidgets('salvo hoje, grava o instante do registro', (tester) async {
      final gravacao = _Gravacao();
      await _pump(tester, saver: gravacao.call);

      final antes = DateTime.now();
      await _save(tester);

      final date = DateTime.parse(gravacao.supply!.date);
      expect(date.isBefore(antes.subtract(const Duration(minutes: 1))), isFalse);
      expect(gravacao.supply!.createdAt, isNotEmpty);
    });

    testWidgets('escolhido ontem, grava ontem ao meio-dia', (tester) async {
      final gravacao = _Gravacao();
      await _pump(tester, saver: gravacao.call);

      final ontem = _today().subtract(const Duration(days: 1));
      await tester.tap(find.byKey(const Key('supply-date')));
      await tester.pumpAndSettle();
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(ontem);
      // Fecha a roleta tocando fora dela.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('supply-date')),
          matching: find.textContaining(_ddMMyyyy(ontem)),
        ),
        findsOneWidget,
      );

      await _save(tester);

      final saved = gravacao.supply!;
      expect(
        saved.date,
        DateTime(ontem.year, ontem.month, ontem.day, 12).toIso8601String(),
      );
      // `createdAt` é quando foi registrado — a diferença entre os dois é o
      // que diz "registrado depois".
      expect(DateTime.parse(saved.createdAt).isAfter(DateTime.parse(saved.date)), isTrue);
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
    testWidgets('é um campo, e nada vem escolhido', (tester) async {
      // Em casa, o mais próximo é justamente o errado, e seria salvo calado.
      await _pump(tester, stations: [(station: _station, meters: 325)]);

      expect(find.text('Escolher posto'), findsOneWidget);
      expect(find.text('Posto Apiguana'), findsNothing);
    });

    testWidgets('sem permissão, o formulário continua inteiro', (tester) async {
      // O gasto é de quem abasteceu: GPS negado não pode impedir de anotar.
      await _pump(tester, failure: LocationFailure.denied);

      expect(find.byKey(const Key('station-field')), findsOneWidget);
      expect(find.byKey(const Key('supply-value')), findsOneWidget);
      expect(find.byKey(const Key('supply-save')), findsOneWidget);
    });

    testWidgets('tocar abre "Postos da região" com a busca já feita', (
      tester,
    ) async {
      var buscas = 0;
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AddSupply(
            uid: 'u1',
            vehiclesLoader: () async => (all: const <Vehicle>[], active: null),
            stationsLoader: () async {
              buscas++;
              return (
                stations: [(station: _station, meters: 325.0)],
                lat: -3.73,
                lng: -38.52,
                failure: null,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('station-field')));
      await tester.pumpAndSettle();

      expect(find.byType(StationsScreen), findsOneWidget);
      expect(find.text('Posto Apiguana'), findsOneWidget);
      // A busca começou quando o formulário abriu; a tela não refez.
      expect(buscas, 1);
    });

    testWidgets('o escolhido aparece no campo, sem distância', (tester) async {
      await _pump(
        tester,
        stationPicker: (_, _) async =>
            const StationChoice.picked(_station, nearMe: true),
      );

      await tester.tap(find.byKey(const Key('station-field')));
      await tester.pumpAndSettle();

      expect(find.text('Posto Apiguana'), findsOneWidget);
      expect(find.byKey(const Key('station-distance')), findsNothing);
    });

    testWidgets('voltar sem escolher mantém o que estava', (tester) async {
      var vez = 0;
      await _pump(
        tester,
        stationPicker: (_, _) async => ++vez == 1
            ? const StationChoice.picked(_station, nearMe: true)
            : null,
      );

      await tester.tap(find.byKey(const Key('station-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('station-field')));
      await tester.pumpAndSettle();

      expect(find.text('Posto Apiguana'), findsOneWidget);
    });

    testWidgets('perto de mim grava o posto e onde o aparelho estava', (
      tester,
    ) async {
      final gravacao = _Gravacao();
      await _pump(
        tester,
        stations: [(station: _station, meters: 325)],
        saver: gravacao.call,
        stationPicker: (_, _) async =>
            const StationChoice.picked(_station, nearMe: true),
      );

      await tester.tap(find.byKey(const Key('station-field')));
      await tester.pumpAndSettle();
      await _save(tester);

      final saved = gravacao.supply!;
      expect(saved.station!.id, 'way-1');
      expect(saved.lat, -3.73);
      expect(saved.lng, -38.52);
    });

    testWidgets('de outra localização grava o id do OSM e lat/lng nulos', (
      tester,
    ) async {
      // Em casa, o GPS é o endereço de quem registra — não o lugar do
      // abastecimento.
      const maraponga = FuelStation(
        id: 'way-9',
        name: 'Posto Maraponga',
        brand: 'BR',
        suburb: 'Maraponga',
        lat: -3.79,
        lng: -38.56,
      );
      final gravacao = _Gravacao();
      await _pump(
        tester,
        stations: [(station: _station, meters: 325)],
        saver: gravacao.call,
        stationPicker: (_, _) async =>
            const StationChoice.picked(maraponga, nearMe: false),
      );

      await tester.tap(find.byKey(const Key('station-field')));
      await tester.pumpAndSettle();
      await _save(tester);

      final saved = gravacao.supply!;
      // Com o id da fonte, o relato de preço chega em `gastop`.
      expect(saved.station!.id, 'way-9');
      expect(saved.station!.suburb, 'Maraponga');
      expect(saved.lat, isNull);
      expect(saved.lng, isNull);
    });

    testWidgets('nome digitado grava sem id — fica fora de gastop', (
      tester,
    ) async {
      final gravacao = _Gravacao();
      await _pump(
        tester,
        saver: gravacao.call,
        stationPicker: (_, _) async =>
            const StationChoice.typed('Posto do Zé', nearMe: true),
      );

      await tester.tap(find.byKey(const Key('station-field')));
      await tester.pumpAndSettle();
      expect(find.text('Posto do Zé'), findsOneWidget);

      await _save(tester);

      final station = gravacao.supply!.station!;
      expect(station.id, isEmpty);
      expect(station.name, 'Posto do Zé');
    });

    testWidgets('sem escolher posto, salva sem posto', (tester) async {
      final gravacao = _Gravacao();
      await _pump(tester, saver: gravacao.call);

      await _save(tester);

      expect(gravacao.chamadas, 1);
      expect(gravacao.supply!.station, isNull);
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

  group('editar', () {
    // Um abastecimento de hoje às 14:32, com posto da lista e o GPS de então.
    Supply gravado() {
      final today = _today();
      return Supply(
        id: 'sup-1',
        vehicleId: 'v1',
        value: 250,
        liters: 39.75,
        fuel: SupplyFuel.etanol,
        odometer: 128800,
        station: _station,
        lat: -3.70,
        lng: -38.50,
        date: DateTime(
          today.year,
          today.month,
          today.day,
          14,
          32,
        ).toIso8601String(),
        createdAt: '2026-10-01T08:00:00.000',
      );
    }

    String field(WidgetTester tester, String key) => tester
        .widget<TextFormField>(find.byKey(Key(key)))
        .controller!
        .text;

    Future<void> saveEdit(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('supply-save')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
    }

    testWidgets('reabre com os campos como estavam', (tester) async {
      await _pump(tester, supply: gravado());

      expect(find.text('Editar abastecimento'), findsOneWidget);
      expect(find.text('SALVAR ALTERAÇÕES'), findsOneWidget);
      expect(field(tester, 'supply-value'), contains('250,00'));
      expect(field(tester, 'supply-liters'), '39,75');
      expect(field(tester, 'supply-odometer'), '128.800');
      expect(find.textContaining('Apiguana'), findsOneWidget);
    });

    testWidgets('salva com o mesmo id e NÃO relata preço ao posto', (
      tester,
    ) async {
      // O caminho do cadastro (`saver`) é o que relata em `gastop`. Na
      // edição ele não pode ser chamado: o relato original é imutável, e um
      // segundo contaria o mesmo abastecimento duas vezes na mediana.
      final cadastro = _Gravacao();
      final edicao = _Gravacao();
      await _pump(
        tester,
        supply: gravado(),
        saver: cadastro.call,
        updater: edicao.call,
      );

      await tester.enterText(find.byKey(const Key('supply-value')), '30000');
      await saveEdit(tester);

      expect(cadastro.chamadas, 0);
      expect(edicao.chamadas, 1);
      final saved = edicao.supply!;
      expect(saved.id, 'sup-1');
      expect(saved.value, 300);
      expect(saved.createdAt, '2026-10-01T08:00:00.000');
      // Mesmo dia: a data gravada fica, hora incluída.
      expect(saved.date, gravado().date);
      expect(saved.fuel, SupplyFuel.etanol);
    });

    testWidgets('posto mantido mantém a posição gravada', (tester) async {
      // O GPS de agora é a casa de quem corrige, não a bomba.
      final edicao = _Gravacao();
      await _pump(
        tester,
        supply: gravado(),
        stations: const [],
        updater: edicao.call,
      );
      await saveEdit(tester);

      expect(edicao.supply!.station!.id, 'way-1');
      expect(edicao.supply!.lat, -3.70);
      expect(edicao.supply!.lng, -38.50);
    });

    testWidgets('posto trocado perde a posição gravada', (tester) async {
      const outro = FuelStation(
        id: 'way-2',
        name: 'Posto Ipiranga Aldeota',
        lat: -3.74,
        lng: -38.49,
      );
      final edicao = _Gravacao();
      await _pump(
        tester,
        supply: gravado(),
        updater: edicao.call,
        stationPicker: (_, _) async =>
            const StationChoice.picked(outro, nearMe: true),
      );

      await tester.ensureVisible(find.textContaining('Apiguana'));
      await tester.tap(find.textContaining('Apiguana'));
      await tester.pumpAndSettle();
      await saveEdit(tester);

      expect(edicao.supply!.station!.id, 'way-2');
      // O posto carrega as próprias coordenadas; a do aparelho não vale.
      expect(edicao.supply!.lat, isNull);
      expect(edicao.supply!.lng, isNull);
    });

    testWidgets('o veículo é o do abastecimento, não o ativo', (tester) async {
      final edicao = _Gravacao();
      await _pump(
        tester,
        supply: gravado(),
        vehicles: [_vehicle(id: 'v1'), _vehicle(id: 'v2', nickname: 'Uno')],
        active: _vehicle(id: 'v2', nickname: 'Uno'),
        updater: edicao.call,
      );
      await saveEdit(tester);

      expect(edicao.supply!.vehicleId, 'v1');
    });
  });
}
