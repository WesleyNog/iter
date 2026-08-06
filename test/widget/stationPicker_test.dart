import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/services/overpass.dart';
import 'package:iter/widget/stationPicker.dart';

NearbyStation _near(String id, String name, double meters) => (
  station: FuelStation(id: id, name: name, lat: 0, lng: 0),
  meters: meters,
);

final _tres = [
  _near('way-1', 'Posto Apiguana', 325),
  _near('node-2', 'BR', 494),
  _near('way-3', 'Shell', 1183),
];

Future<void> _pump(
  WidgetTester tester, {
  List<NearbyStation>? stations,
  bool loading = false,
  String? failureMessage,
  bool canOpenSettings = false,
  FuelStation? selected,
  bool otherSelected = false,
  void Function(FuelStation?)? onSelect,
  VoidCallback? onRetry,
  VoidCallback? onOpenSettings,
  TextEditingController? typed,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StationPicker(
            stations: stations,
            loading: loading,
            failureMessage: failureMessage,
            canOpenSettings: canOpenSettings,
            selected: selected,
            otherSelected: otherSelected,
            onSelect: onSelect ?? (_) {},
            typedName: typed ?? TextEditingController(),
            onTypedName: (_) {},
            onRetry: onRetry,
            onOpenSettings: onOpenSettings,
          ),
        ),
      ),
    ),
  );
}

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

  group('a lista', () {
    testWidgets('mostra os postos com a distância', (tester) async {
      await _pump(tester, stations: _tres);

      expect(find.text('Posto Apiguana'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('station-distance-0'))).data,
        '325 m',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('station-distance-2'))).data,
        '1,2 km',
      );
    });

    testWidgets('o primeiro da lista é o que veio primeiro do serviço', (
      tester,
    ) async {
      // Quem ordena é o `parseStations`; o picker não reordena por conta
      // própria, senão haveria duas noções de "mais próximo".
      await _pump(tester, stations: _tres);

      final first = tester.widget<ListTile>(
        find.byKey(const Key('station-item-0')),
      );
      expect((first.title! as Text).data, 'Posto Apiguana');
    });

    testWidgets('tocar num posto avisa qual foi', (tester) async {
      FuelStation? escolhido;
      var chamadas = 0;

      await _pump(
        tester,
        stations: _tres,
        onSelect: (s) {
          escolhido = s;
          chamadas++;
        },
      );

      await tester.tap(find.byKey(const Key('station-item-1')));
      await tester.pump();

      expect(chamadas, 1);
      expect(escolhido!.id, 'node-2');
    });

    testWidgets('o escolhido aparece marcado', (tester) async {
      await _pump(
        tester,
        stations: _tres,
        selected: _tres[1].station,
      );

      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });
  });

  group('"Outro / não listado"', () {
    testWidgets('existe mesmo com a lista cheia', (tester) async {
      // A Overpass pode responder certinho e não ter o posto onde ele parou.
      await _pump(tester, stations: _tres);

      expect(find.byKey(const Key('station-other')), findsOneWidget);
    });

    testWidgets('existe também quando a busca falhou', (tester) async {
      await _pump(tester, failureMessage: 'Sem localização.');

      expect(find.byKey(const Key('station-other')), findsOneWidget);
    });

    testWidgets('tocar nele avisa com null', (tester) async {
      FuelStation? recebido = _tres.first.station;
      var chamadas = 0;

      await _pump(
        tester,
        stations: _tres,
        onSelect: (s) {
          recebido = s;
          chamadas++;
        },
      );

      await tester.tap(find.byKey(const Key('station-other')));
      await tester.pump();

      expect(chamadas, 1);
      expect(recebido, isNull);
    });

    testWidgets('o campo de texto só aparece depois de marcado', (tester) async {
      await _pump(tester, stations: _tres);
      expect(find.byKey(const Key('station-typed')), findsNothing);

      await _pump(tester, stations: _tres, otherSelected: true);
      expect(find.byKey(const Key('station-typed')), findsOneWidget);
    });

    testWidgets('com "Outro" marcado, nenhum posto da lista fica marcado', (
      tester,
    ) async {
      // `selected` continua apontando para o último escolhido; sem a distinção,
      // dois itens apareceriam marcados ao mesmo tempo.
      await _pump(
        tester,
        stations: _tres,
        selected: _tres.first.station,
        otherSelected: true,
      );

      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });
  });

  group('estados', () {
    testWidgets('carregando mostra o aviso e nenhuma lista', (tester) async {
      await _pump(tester, loading: true);

      expect(find.byKey(const Key('station-loading')), findsOneWidget);
      expect(find.byKey(const Key('station-item-0')), findsNothing);
    });

    testWidgets('falha mostra a frase e o "tentar de novo"', (tester) async {
      await _pump(
        tester,
        failureMessage: 'Ative a localização do aparelho.',
        onRetry: () {},
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('station-error'))).data,
        'Ative a localização do aparelho.',
      );
      expect(find.byKey(const Key('station-retry')), findsOneWidget);
    });

    testWidgets('"abrir ajustes" só aparece quando é o que resolve', (
      tester,
    ) async {
      await _pump(
        tester,
        failureMessage: 'Bloqueada nos ajustes.',
        canOpenSettings: true,
        onOpenSettings: () {},
      );
      expect(find.byKey(const Key('station-settings')), findsOneWidget);

      await _pump(
        tester,
        failureMessage: 'Você negou agora.',
        onRetry: () {},
      );
      expect(find.byKey(const Key('station-settings')), findsNothing);
    });

    testWidgets('lista vazia diz que não achou, e não parece erro', (
      tester,
    ) async {
      // Zona rural existe: "nenhum posto no raio" é resposta, não falha.
      await _pump(tester, stations: const []);

      expect(find.byKey(const Key('station-empty')), findsOneWidget);
      expect(find.byKey(const Key('station-error')), findsNothing);
    });

    testWidgets('antes de qualquer busca não desenha lista nem erro', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byKey(const Key('station-empty')), findsNothing);
      expect(find.byKey(const Key('station-error')), findsNothing);
      expect(find.byKey(const Key('station-other')), findsOneWidget);
    });
  });
}
