import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/stationPrices.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/screens/stationsScreen.dart';
import 'package:iter/services/geocoding.dart';
import 'package:iter/services/location.dart';
import 'package:iter/services/overpass.dart';

NearbyStation _near(
  String id,
  String name,
  double meters, {
  String? brand,
  String? suburb,
}) => (
  station: FuelStation(
    id: id,
    name: name,
    brand: brand,
    suburb: suburb,
    lat: 0,
    lng: 0,
  ),
  meters: meters,
);

final _casa = [
  _near('way-1', 'Posto Apiguana', 325, brand: 'Ipiranga', suburb: 'Centro'),
  _near('node-2', 'Posto Aliança', 494, brand: 'BR', suburb: 'Joaquim Távora'),
  _near('way-3', 'Posto Prainha', 1183, brand: 'Shell'),
];

final _maraponga = [
  _near('way-9', 'Posto Maraponga', 2800, brand: 'BR', suburb: 'Maraponga'),
];

const Place _lugar = (
  title: 'Maraponga',
  detail: 'Fortaleza, Ceará',
  lat: -3.7934,
  lng: -38.5690,
);

StationsSnapshot _ok(List<NearbyStation> stations) =>
    (stations: stations, lat: -3.73, lng: -38.52, failure: null);

StationsSnapshot _semGps(LocationFailure failure) =>
    (stations: null, lat: null, lng: null, failure: failure);

/// O que a tela pediu aos carregadores falsos.
class _Chamadas {
  final around = <(double, double)>[];
  final prices = <List<String>>[];
  var locate = 0;
  var settings = 0;
}

/// Abre a tela por cima de outra, para o `pop` dela ter para onde voltar, e
/// guarda o que ela devolveu.
Future<List<StationChoice?>> _open(
  WidgetTester tester, {
  Future<StationsSnapshot>? nearby,
  Future<StationsSnapshot> Function()? locate,
  Future<List<NearbyStation>?> Function(double, double)? around,
  Future<Map<String, StationPrices>?> Function(List<String>)? prices,
  Future<List<Place>?> Function(String)? places,
  StationChoice? current,
  _Chamadas? chamadas,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final calls = chamadas ?? _Chamadas();
  final devolvido = <StationChoice?>[];

  // Testes que abrem a tela duas vezes: sem desmontar, a primeira continuaria
  // empilhada por cima do botão "abrir".
  await tester.pumpWidget(const SizedBox());

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => devolvido.add(
              await Navigator.of(context).push<StationChoice>(
                MaterialPageRoute(
                  builder: (_) => StationsScreen(
                    nearby: nearby ?? Future.value(_ok(_casa)),
                    locate: () {
                      calls.locate++;
                      return (locate ?? () async => _ok(_casa))();
                    },
                    current: current,
                    stationsAround: (lat, lng) {
                      calls.around.add((lat, lng));
                      return (around ?? (_, _) async => _maraponga)(lat, lng);
                    },
                    pricesLoader: (ids) {
                      calls.prices.add(ids);
                      return (prices ?? (_) async => const {})(ids);
                    },
                    placeSearch: (query, {lat, lng}) =>
                        (places ?? (_) async => [_lugar])(query),
                    onOpenSettings: () => calls.settings++,
                  ),
                ),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  // `pump` com tempo, e não `pumpAndSettle`: com a busca ainda pendente o
  // indicador de carregamento gira para sempre e a tela nunca "assenta".
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return devolvido;
}

/// "Outra localização" → digita → busca → escolhe o primeiro resultado.
Future<void> _goTo(WidgetTester tester, String query) async {
  await tester.tap(find.byKey(const Key('stations-other')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('place-query')), query);
  await tester.tap(find.byKey(const Key('place-search')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('place-item-0')));
  await tester.pumpAndSettle();
}

/// Os índices dos cards desenhados como escolhidos (borda de 2 px).
List<int> _selectedCards(WidgetTester tester) => [
  for (var i = 0; find.byKey(Key('station-item-$i')).evaluate().isNotEmpty; i++)
    if ((tester
                    .widget<Material>(
                      find
                          .descendant(
                            of: find.byKey(Key('station-item-$i')),
                            matching: find.byType(Material),
                          )
                          .first,
                    )
                    .shape!
                as RoundedRectangleBorder)
            .side
            .width ==
        2)
      i,
];

List<String> _titles(WidgetTester tester) => tester
    .widgetList<Text>(find.byKey(const Key('station-title')))
    .map((t) => t.data!)
    .toList();

void main() {
  group('a lista', () {
    testWidgets('na ordem recebida, com distância e bairro', (tester) async {
      // Quem ordena é o `parseStations`; a tela não reordena por conta
      // própria, senão haveria duas noções de "mais próximo".
      await _open(tester);

      expect(_titles(tester), [
        'Posto Apiguana',
        'Posto Aliança',
        'Posto Prainha',
      ]);
      expect(find.text('325 m'), findsOneWidget);
      expect(find.text('Joaquim Távora'), findsOneWidget);
    });

    testWidgets('nada vem marcado', (tester) async {
      // Em casa, o mais próximo é justamente o errado, e seria salvo calado.
      await _open(tester);

      expect(_selectedCards(tester), isEmpty);
    });

    testWidgets('tocar num posto devolve ele, perto de mim', (tester) async {
      final devolvido = await _open(tester);

      await tester.tap(find.text('Posto Aliança'));
      await tester.pumpAndSettle();

      expect(devolvido.single!.station!.id, 'node-2');
      expect(devolvido.single!.nearMe, isTrue);
    });

    testWidgets('o já escolhido aparece marcado', (tester) async {
      await _open(
        tester,
        current: StationChoice.picked(_casa[1].station, nearMe: true),
      );

      expect(_selectedCards(tester), [1]);
    });
  });

  group('preços', () {
    testWidgets('pede os preços dos postos da lista, numa chamada', (
      tester,
    ) async {
      final chamadas = _Chamadas();
      await _open(tester, chamadas: chamadas);

      expect(chamadas.prices, [
        ['way-1', 'node-2', 'way-3'],
      ]);
    });

    testWidgets('relatado aparece, ausente é —', (tester) async {
      await _open(
        tester,
        prices: (_) async => {
          'way-1': StationPrices.fromMap({
            'prices': {'gasolina': 6.14},
          }),
        },
      );

      expect(find.text('R\$ 6,14'), findsOneWidget);
      // 2 colunas vazias no primeiro, 3 em cada um dos outros dois.
      expect(find.text('—'), findsNWidgets(8));
    });

    testWidgets('carregando NÃO mostra —', (tester) async {
      final resposta = Completer<Map<String, StationPrices>?>();
      await _open(tester, prices: (_) => resposta.future);

      expect(find.text('—'), findsNothing);
      expect(find.byKey(const Key('station-price-loading')), findsWidgets);

      resposta.complete(const {});
      await tester.pumpAndSettle();
      expect(find.text('—'), findsNWidgets(9));
    });

    testWidgets('falha diz que falhou, sem — em lugar nenhum', (tester) async {
      await _open(tester, prices: (_) async => null);

      expect(find.text('—'), findsNothing);
      expect(find.byKey(const Key('station-prices-failed')), findsNWidgets(3));
      // A lista continua escolhível.
      expect(_titles(tester), hasLength(3));
    });
  });

  group('filtro', () {
    testWidgets('por bairro, sem acento', (tester) async {
      await _open(tester);

      await tester.enterText(
        find.byKey(const Key('stations-filter')),
        'joaquim tavora',
      );
      await tester.pumpAndSettle();

      expect(_titles(tester), ['Posto Aliança']);
    });

    testWidgets('sem resultado cita o que foi buscado e deixa limpar', (
      tester,
    ) async {
      await _open(tester);

      await tester.enterText(
        find.byKey(const Key('stations-filter')),
        'Texaco',
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhum posto com "Texaco" por aqui.'), findsOneWidget);

      await tester.tap(find.text('Limpar busca'));
      await tester.pumpAndSettle();

      expect(_titles(tester), hasLength(3));
    });
  });

  group('outra localização — quem registra em casa', () {
    testWidgets('recentra a lista no lugar escolhido', (tester) async {
      final chamadas = _Chamadas();
      await _open(tester, chamadas: chamadas);

      await _goTo(tester, 'Maraponga');

      expect(chamadas.around, [(-3.7934, -38.5690)]);
      expect(_titles(tester), ['Posto Maraponga']);
      expect(find.text('2,8 km'), findsOneWidget);
    });

    testWidgets('o botão mostra o lugar, para saber de onde é a distância', (
      tester,
    ) async {
      await _open(tester);

      await _goTo(tester, 'Maraponga');

      expect(
        find.descendant(
          of: find.byKey(const Key('stations-other')),
          matching: find.text('Maraponga'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('posto de lá volta marcado como não sendo perto de mim', (
      tester,
    ) async {
      final devolvido = await _open(tester);

      await _goTo(tester, 'Maraponga');
      await tester.tap(find.text('Posto Maraponga'));
      await tester.pumpAndSettle();

      expect(devolvido.single!.station!.id, 'way-9');
      expect(devolvido.single!.nearMe, isFalse);
    });

    testWidgets('funciona sem permissão de localização', (tester) async {
      // Antes desta tela, quem negava o GPS só podia digitar o nome — e o
      // relato de preço nunca chegava em `gastop`.
      await _open(
        tester,
        nearby: Future.value(_semGps(LocationFailure.denied)),
      );

      expect(find.byKey(const Key('stations-error')), findsOneWidget);

      await _goTo(tester, 'Maraponga');

      expect(_titles(tester), ['Posto Maraponga']);
    });

    testWidgets('voltar para "Minha localização" não pergunta ao GPS de novo', (
      tester,
    ) async {
      final chamadas = _Chamadas();
      await _open(tester, chamadas: chamadas);

      await _goTo(tester, 'Maraponga');
      await tester.tap(find.byKey(const Key('stations-near-me')));
      await tester.pumpAndSettle();

      expect(_titles(tester), hasLength(3));
      expect(chamadas.locate, 0);
    });

    testWidgets('resposta atrasada da busca anterior não cobre a nova', (
      tester,
    ) async {
      // Trocou de lugar com a lista de casa ainda carregando: quando ela chega,
      // a tela já é da Maraponga.
      final casa = Completer<StationsSnapshot>();
      await _open(tester, nearby: casa.future);

      await _goTo(tester, 'Maraponga');
      casa.complete(_ok(_casa));
      await tester.pumpAndSettle();

      expect(_titles(tester), ['Posto Maraponga']);
    });

    testWidgets('Overpass fora do ar no outro lugar: tentar de novo', (
      tester,
    ) async {
      var tentativas = 0;
      final chamadas = _Chamadas();
      await _open(
        tester,
        chamadas: chamadas,
        around: (_, _) async => ++tentativas == 1 ? null : _maraponga,
      );

      await _goTo(tester, 'Maraponga');
      expect(
        find.text('Não foi possível buscar os postos agora.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('stations-retry')));
      await tester.pumpAndSettle();

      expect(_titles(tester), ['Posto Maraponga']);
      expect(chamadas.locate, 0);
    });
  });

  group('estados', () {
    testWidgets('carregando mostra o aviso e nenhuma lista', (tester) async {
      final casa = Completer<StationsSnapshot>();
      await _open(tester, nearby: casa.future);

      expect(find.byKey(const Key('stations-loading')), findsOneWidget);
      expect(find.byKey(const Key('station-title')), findsNothing);

      casa.complete(_ok(_casa));
      await tester.pumpAndSettle();
    });

    testWidgets('sem permissão: a frase do motivo e tentar de novo', (
      tester,
    ) async {
      final chamadas = _Chamadas();
      await _open(
        tester,
        chamadas: chamadas,
        nearby: Future.value(_semGps(LocationFailure.denied)),
      );

      expect(
        find.text(locationFailureMessage(LocationFailure.denied)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('stations-retry')));
      await tester.pumpAndSettle();

      expect(chamadas.locate, 1);
      expect(_titles(tester), hasLength(3));
    });

    testWidgets('"abrir ajustes" só aparece quando é o que resolve', (
      tester,
    ) async {
      await _open(
        tester,
        nearby: Future.value(_semGps(LocationFailure.denied)),
      );
      expect(find.byKey(const Key('stations-settings')), findsNothing);

      final chamadas = _Chamadas();
      await _open(
        tester,
        chamadas: chamadas,
        nearby: Future.value(_semGps(LocationFailure.deniedForever)),
      );
      await tester.tap(find.byKey(const Key('stations-settings')));
      expect(chamadas.settings, 1);
    });

    testWidgets('GPS certo e Overpass fora do ar não culpa a localização', (
      tester,
    ) async {
      await _open(
        tester,
        nearby: Future.value((
          stations: null,
          lat: -3.73,
          lng: -38.52,
          failure: null,
        )),
      );

      expect(
        find.text('Não foi possível buscar os postos agora.'),
        findsOneWidget,
      );
      expect(
        find.text(locationFailureMessage(LocationFailure.failed)),
        findsNothing,
      );
    });

    testWidgets('lista vazia diz que não achou, e não parece erro', (
      tester,
    ) async {
      // Zona rural existe: "nenhum posto no raio" é resposta, não falha.
      await _open(tester, nearby: Future.value(_ok(const [])));

      expect(find.byKey(const Key('stations-empty')), findsOneWidget);
      expect(find.byKey(const Key('stations-error')), findsNothing);
    });
  });

  group('"Outro / não listado"', () {
    testWidgets('existe em todos os estados', (tester) async {
      // A Overpass pode responder certinho e não ter o posto do abastecimento.
      await _open(tester);
      expect(find.byKey(const Key('station-other')), findsOneWidget);

      await _open(
        tester,
        nearby: Future.value(_semGps(LocationFailure.denied)),
      );
      expect(find.byKey(const Key('station-other')), findsOneWidget);

      await _open(tester, nearby: Future.value(_ok(const [])));
      expect(find.byKey(const Key('station-other')), findsOneWidget);

      final casa = Completer<StationsSnapshot>();
      await _open(tester, nearby: casa.future);
      expect(find.byKey(const Key('station-other')), findsOneWidget);
      casa.complete(_ok(_casa));
      await tester.pumpAndSettle();
    });

    testWidgets('o campo só aparece depois de tocar', (tester) async {
      await _open(tester);
      expect(find.byKey(const Key('station-typed')), findsNothing);

      await tester.tap(find.byKey(const Key('station-other')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('station-typed')), findsOneWidget);
    });

    testWidgets('nome vazio não é escolha', (tester) async {
      final devolvido = await _open(tester);

      await tester.tap(find.byKey(const Key('station-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('station-typed-confirm')));
      await tester.pumpAndSettle();

      expect(devolvido, isEmpty);
    });

    testWidgets('devolve só o nome, sem id', (tester) async {
      final devolvido = await _open(tester);

      await tester.tap(find.byKey(const Key('station-other')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('station-typed')),
        ' Posto do Zé ',
      );
      // O botão só liga depois do rebuild que o texto provoca.
      await tester.pump();
      await tester.tap(find.byKey(const Key('station-typed-confirm')));
      await tester.pumpAndSettle();

      expect(devolvido.single!.typedName, 'Posto do Zé');
      expect(devolvido.single!.station, isNull);
    });

    testWidgets('com um nome digitado, nenhum posto da lista fica marcado', (
      tester,
    ) async {
      await _open(
        tester,
        current: const StationChoice.typed('Posto do Zé', nearMe: true),
      );

      expect(_selectedCards(tester), isEmpty);
    });

    testWidgets('reabrir com um nome digitado já mostra o campo preenchido', (
      tester,
    ) async {
      await _open(
        tester,
        current: const StationChoice.typed('Posto do Zé', nearMe: true),
      );

      expect(find.text('Posto do Zé'), findsOneWidget);
    });
  });
}
