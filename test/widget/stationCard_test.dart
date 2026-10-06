import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/stationFlag.dart';
import 'package:iter/model/stationPrices.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/widget/stationCard.dart';

const _maraponga = FuelStation(
  id: 'way-1',
  name: 'Posto Maraponga',
  brand: 'BR',
  suburb: 'Maraponga',
  lat: -3.79,
  lng: -38.56,
);

Future<void> _pump(
  WidgetTester tester, {
  FuelStation station = _maraponga,
  double? meters = 2800,
  PricesState? pricesState,
  StationPrices? prices,
  bool selected = false,
  VoidCallback? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StationCard(
          station: station,
          meters: meters,
          pricesState: pricesState,
          prices: prices,
          selected: selected,
          onTap: onTap,
        ),
      ),
    ),
  );
}

Finder _inColumn(SupplyFuel fuel, Finder matching) => find.descendant(
  of: find.byKey(Key('station-price-${fuel.name}')),
  matching: matching,
);

void main() {
  group('formatDistance', () {
    test('metros até um quilômetro', () {
      expect(formatDistance(325), '325 m');
      expect(formatDistance(999), '999 m');
      expect(formatDistance(0), '0 m');
    });

    test('quilômetros com uma casa, em vírgula', () {
      // "3417 m" é mais difícil de ler que "3,4 km", e a diferença de 100 m
      // nessa distância não muda a decisão de ninguém.
      expect(formatDistance(1000), '1,0 km');
      expect(formatDistance(1183), '1,2 km');
      expect(formatDistance(3417), '3,4 km');
    });
  });

  group('stationTitle — o texto é o nome; o logo já diz a bandeira', () {
    FuelStation station({String name = '', String? brand, String? address}) =>
        FuelStation(
          id: 'node-1',
          name: name,
          brand: brand,
          address: address,
          lat: 0,
          lng: 0,
        );

    test('com logo, o nome sozinho, sem repetir a bandeira', () {
      expect(stationTitle(_maraponga), 'Posto Maraponga');
    });

    test('nome que cita a bandeira e diz mais é nome', () {
      expect(
        stationTitle(station(name: 'Posto Shell | 13 de Maio', brand: 'Shell')),
        'Posto Shell | 13 de Maio',
      );
      expect(
        stationTitle(station(name: 'Posto BR Fórmula', brand: 'BR')),
        'Posto BR Fórmula',
      );
    });

    test('"nome" que só repete a bandeira não é nome — vai o endereço', () {
      // 42 postos da RMF têm `name=Shell`, `name=BR`… Ao lado do logo, é a
      // mesma informação duas vezes e nenhuma que diga qual Shell é.
      const rua = 'Avenida Antônio Sales, 1340';

      expect(
        stationTitle(station(name: 'Shell', brand: 'Shell', address: rua)),
        rua,
      );
      expect(
        stationTitle(station(name: 'Posto BR', brand: 'BR', address: rua)),
        rua,
      );
      expect(
        stationTitle(station(name: 'Petrobras', brand: 'BR', address: rua)),
        rua,
      );
    });

    test('sem nome, o endereço', () {
      expect(
        stationTitle(
          station(brand: 'Ipiranga', address: 'Rua 24 de Maio, 1230'),
        ),
        'Rua 24 de Maio, 1230',
      );
      expect(
        stationTitle(station(address: 'Avenida Duque de Caxias')),
        'Avenida Duque de Caxias',
      );
    });

    test(
      'com logo e sem nome nem endereço: "Posto sem nome", não a bandeira',
      () {
        expect(stationTitle(station(brand: 'Shell')), 'Posto sem nome');
        expect(
          stationTitle(station(name: 'Shell', brand: 'Shell')),
          'Posto sem nome',
        );
      },
    );

    test('sem logo, a bandeira em texto é a única que existe', () {
      // SP não tem desenho: tirar o texto apagaria a bandeira da tela.
      expect(
        stationTitle(station(name: 'Posto Ximenes', brand: 'SP')),
        'Posto Ximenes | SP',
      );
      expect(stationTitle(station(brand: 'SP')), 'SP');
      expect(stationTitle(station(name: 'Posto SP', brand: 'SP')), 'Posto SP');
    });

    test('sem nada, "Posto sem nome"', () {
      expect(stationTitle(station()), 'Posto sem nome');
    });
  });

  group('cabeçalho', () {
    testWidgets('logo da bandeira derivada', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('station-logo-br')), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, StationFlag.br.asset);
    });

    testWidgets('bairro em cima do nome, quando o OSM tem', (tester) async {
      await _pump(tester);

      expect(find.text('Maraponga'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Maraponga')).dy,
        lessThan(tester.getTopLeft(find.text('Posto Maraponga')).dy),
      );
    });

    testWidgets('sem bairro, nenhuma linha no lugar', (tester) async {
      const semBairro = FuelStation(id: 'w', name: 'Posto X', lat: 0, lng: 0);
      await _pump(tester, station: semBairro);

      expect(find.byKey(const Key('station-suburb')), findsNothing);
    });

    testWidgets('distância só quando informada', (tester) async {
      await _pump(tester);
      expect(find.text('2,8 km'), findsOneWidget);

      await _pump(tester, meters: null);
      expect(find.byKey(const Key('station-distance')), findsNothing);
    });

    testWidgets('nome longo não quebra linha', (tester) async {
      // Testa a causa, não "cabe na tela": a fonte de teste é quadrada.
      await _pump(tester);

      final title = tester.widget<Text>(find.byKey(const Key('station-title')));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('tocar chama onTap', (tester) async {
      var tocou = 0;
      await _pump(tester, onTap: () => tocou++);

      await tester.tap(find.byType(StationCard));
      expect(tocou, 1);
    });
  });

  group('faixa de preços — três estados que não se confundem', () {
    testWidgets('sem pricesState a faixa nem aparece', (tester) async {
      // É o card do formulário.
      await _pump(tester);

      expect(find.byKey(const Key('station-prices')), findsNothing);
    });

    testWidgets('as três colunas dividem a linha', (tester) async {
      await _pump(tester, pricesState: PricesState.ready);

      for (final fuel in pumpFuels) {
        expect(
          find.ancestor(
            of: find.byKey(Key('station-price-${fuel.name}')),
            matching: find.byType(Expanded),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Gasolina'), findsOneWidget);
      expect(find.text('Etanol'), findsOneWidget);
      expect(find.text('Diesel'), findsOneWidget);
    });

    testWidgets('relatado mostra o preço e a idade', (tester) async {
      final prices = StationPrices.fromMap({
        'prices': {'gasolina': 6.14},
        'pricedAt': {
          'gasolina': DateTime.now()
              .subtract(const Duration(days: 2, hours: 1))
              .toIso8601String(),
        },
      });
      await _pump(tester, pricesState: PricesState.ready, prices: prices);

      expect(
        _inColumn(SupplyFuel.gasolina, find.text('R\$ 6,14')),
        findsOneWidget,
      );
      expect(
        _inColumn(SupplyFuel.gasolina, find.text('há 2d')),
        findsOneWidget,
      );
    });

    testWidgets('ninguém relatou: —', (tester) async {
      final prices = StationPrices.fromMap({
        'prices': {'gasolina': 6.14},
      });
      await _pump(tester, pricesState: PricesState.ready, prices: prices);

      expect(_inColumn(SupplyFuel.etanol, find.text('—')), findsOneWidget);
      expect(_inColumn(SupplyFuel.diesel, find.text('—')), findsOneWidget);
    });

    testWidgets('posto fora de gastop: — nas três', (tester) async {
      await _pump(tester, pricesState: PricesState.ready);

      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('preço sem data não inventa idade', (tester) async {
      final prices = StationPrices.fromMap({
        'prices': {'gasolina': 6.29},
      });
      await _pump(tester, pricesState: PricesState.ready, prices: prices);

      expect(find.textContaining('há '), findsNothing);
    });

    testWidgets('carregando NÃO mostra —', (tester) async {
      await _pump(tester, pricesState: PricesState.loading);

      expect(find.text('—'), findsNothing);
      expect(find.byKey(const Key('station-price-loading')), findsNWidgets(3));
    });

    testWidgets('falha esconde as colunas e diz que falhou', (tester) async {
      await _pump(tester, pricesState: PricesState.failed);

      expect(find.text('—'), findsNothing);
      expect(find.byKey(const Key('station-price-gasolina')), findsNothing);
      expect(find.byKey(const Key('station-prices-failed')), findsOneWidget);
    });
  });
}
