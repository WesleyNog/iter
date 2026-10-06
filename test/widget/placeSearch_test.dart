import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/services/geocoding.dart';
import 'package:iter/widget/placeSearch.dart';

const Place _maraponga = (
  title: 'Maraponga',
  detail: 'Fortaleza, Ceará',
  lat: -3.7934,
  lng: -38.5690,
);

const Place _centroCaucaia = (
  title: 'Centro',
  detail: 'Caucaia, Ceará',
  lat: -3.7349,
  lng: -38.6551,
);

/// O buscador falso: conta as chamadas e devolve o que o teste mandar.
class _Busca {
  _Busca(this.answer);

  Future<List<Place>?> Function(String query) answer;
  final queries = <String>[];
  double? lat;
  double? lng;

  Future<List<Place>?> call(String query, {double? lat, double? lng}) {
    queries.add(query);
    this.lat = lat;
    this.lng = lng;
    return answer(query);
  }
}

/// Abre "Outra localização" a partir de uma tela qualquer e guarda o que ela
/// devolveu.
Future<List<Place?>> _open(
  WidgetTester tester,
  _Busca busca, {
  double? lat,
  double? lng,
}) async {
  final devolvido = <Place?>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => devolvido.add(
              await showPlaceSearch(
                context,
                lat: lat,
                lng: lng,
                search: busca.call,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return devolvido;
}

Future<void> _type(WidgetTester tester, String text) =>
    tester.enterText(find.byKey(const Key('place-query')), text);

void main() {
  testWidgets('digitar NÃO busca — o Nominatim proíbe autocompletar', (
    tester,
  ) async {
    final busca = _Busca((_) async => [_maraponga]);
    await _open(tester, busca);

    await _type(tester, 'M');
    await _type(tester, 'Mara');
    await _type(tester, 'Maraponga');
    await tester.pumpAndSettle();

    expect(busca.queries, isEmpty);
  });

  testWidgets('confirmar no teclado busca uma vez, com a posição', (
    tester,
  ) async {
    final busca = _Busca((_) async => [_maraponga]);
    await _open(tester, busca, lat: -3.73, lng: -38.52);

    await _type(tester, 'Maraponga');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(busca.queries, ['Maraponga']);
    expect(busca.lat, -3.73);
    expect(busca.lng, -38.52);
  });

  testWidgets('o botão também busca', (tester) async {
    final busca = _Busca((_) async => [_maraponga]);
    await _open(tester, busca);

    await _type(tester, '  Maraponga  ');
    await tester.tap(find.byKey(const Key('place-search')));
    await tester.pumpAndSettle();

    expect(busca.queries, ['Maraponga']);
  });

  testWidgets('busca vazia não vai à rede', (tester) async {
    final busca = _Busca((_) async => [_maraponga]);
    await _open(tester, busca);

    await _type(tester, '   ');
    await tester.tap(find.byKey(const Key('place-search')));
    await tester.pumpAndSettle();

    expect(busca.queries, isEmpty);
  });

  testWidgets('durante a busca o botão fica desligado', (tester) async {
    // Dois toques seguidos seriam duas requisições no mesmo segundo.
    final resposta = Completer<List<Place>?>();
    final busca = _Busca((_) => resposta.future);
    await _open(tester, busca);

    await _type(tester, 'Maraponga');
    await tester.tap(find.byKey(const Key('place-search')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('place-search')));
    await tester.pump();

    expect(busca.queries, ['Maraponga']);

    resposta.complete([_maraponga]);
    await tester.pumpAndSettle();
  });

  testWidgets('resultado mostra a cidade, e tocar devolve o lugar', (
    tester,
  ) async {
    final busca = _Busca((_) async => [_maraponga, _centroCaucaia]);
    final devolvido = await _open(tester, busca);

    await _type(tester, 'Centro');
    await tester.tap(find.byKey(const Key('place-search')));
    await tester.pumpAndSettle();

    expect(find.text('Caucaia, Ceará'), findsOneWidget);

    await tester.tap(find.byKey(const Key('place-item-1')));
    await tester.pumpAndSettle();

    expect(devolvido, [_centroCaucaia]);
  });

  testWidgets('voltar sem escolher devolve null', (tester) async {
    final busca = _Busca((_) async => [_maraponga]);
    final devolvido = await _open(tester, busca);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(devolvido, [null]);
  });

  testWidgets('nada encontrado cita o que foi buscado', (tester) async {
    final busca = _Busca((_) async => const []);
    await _open(tester, busca);

    await _type(tester, 'Xyzzy');
    await tester.tap(find.byKey(const Key('place-search')));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum lugar encontrado para "Xyzzy".'), findsOneWidget);
    expect(find.byKey(const Key('place-failed')), findsNothing);
  });

  testWidgets('falha é outra frase, com tentar de novo', (tester) async {
    // "Não deu para perguntar" não é "não existe": o lugar pode estar lá.
    var tentativas = 0;
    final busca = _Busca((_) async => ++tentativas == 1 ? null : [_maraponga]);
    await _open(tester, busca);

    await _type(tester, 'Maraponga');
    await tester.tap(find.byKey(const Key('place-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('place-failed')), findsOneWidget);
    expect(find.byKey(const Key('place-empty')), findsNothing);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.text('Maraponga'), findsWidgets);
    expect(find.byKey(const Key('place-failed')), findsNothing);
  });
}
