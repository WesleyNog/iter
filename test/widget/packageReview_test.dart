import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/packageLabel.dart';
import 'package:iter/Utils/packageSession.dart';
import 'package:iter/widget/packageReview.dart';

LabelRead _read(
  String id, {
  String? bairro = 'Papicu',
  String? raw,
  String? stop,
  PackageType type = PackageType.residencial,
}) => LabelRead(
  shipmentId: id,
  type: type,
  bairro: bairro,
  rawBairro: raw ?? bairro,
  stopKey: stop ?? 'p-$id',
);

PackageSession _carga() => PackageSession()
  ..add(_read('1', stop: 'predio'))
  ..add(_read('2', stop: 'predio'))
  ..add(_read('3', bairro: 'Meireles', type: PackageType.agencia))
  ..add(_read('4', bairro: null, raw: 'Água Fria'));

class _Result {
  PackageLoad? saved;
  int back = 0;
}

Future<_Result> _pump(
  WidgetTester tester, {
  PackageSession? session,
  List<String> previous = const [],
}) async {
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PackageReview(
          session: session ?? _carga(),
          previousBairros: previous,
          onSave: (load) => result.saved = load,
          onBack: () => result.back++,
        ),
      ),
    ),
  );
  return result;
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

bool _canSave(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('salvar-carga')))
        .onPressed !=
    null;

void main() {
  testWidgets('abre com o que a leitura contou', (tester) async {
    await _pump(tester);

    expect(_field(tester, 'campo-pacotes'), '4');
    // Os dois do mesmo prédio são uma parada.
    expect(_field(tester, 'campo-paradas'), '3');
    expect(find.text('R 3  ·  C 0  ·  A 1'), findsOneWidget);
  });

  testWidgets('pacotes e paradas lado a lado, dividindo a largura', (
    tester,
  ) async {
    // A causa, não o texto caber: os dois campos na mesma linha.
    await _pump(tester);

    final pacotes = tester.getRect(find.byKey(const ValueKey('campo-pacotes')));
    final paradas = tester.getRect(find.byKey(const ValueKey('campo-paradas')));
    expect(pacotes.top, paradas.top);
    expect(pacotes.width, closeTo(paradas.width, 1));
  });

  testWidgets('salvar sem editar grava o que foi lido', (tester) async {
    final result = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('salvar-carga')));

    final load = result.saved!;
    expect(load.packages, 4);
    expect(load.stops, 3);
    expect(load.bairros, ['Papicu', 'Meireles']);
    expect(load.pacotesPorBairro, {'Papicu': 2, 'Meireles': 1});
  });

  testWidgets('o total corrigido é o que vai, e a medição acompanha', (
    tester,
  ) async {
    // Tirou a caixa da agência fechada sem ler de novo.
    final result = await _pump(tester);

    await tester.enterText(find.byKey(const ValueKey('campo-pacotes')), '2');
    await tester.enterText(find.byKey(const ValueKey('campo-paradas')), '1');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('salvar-carga')));

    expect(result.saved!.packages, 2);
    expect(result.saved!.pacotesPorBairro, {'Papicu': 2});
  });

  testWidgets('zero pacotes ou mais paradas que pacotes não salva', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const ValueKey('campo-pacotes')), '0');
    await tester.pump();
    expect(_canSave(tester), isFalse);

    await tester.enterText(find.byKey(const ValueKey('campo-pacotes')), '2');
    await tester.enterText(find.byKey(const ValueKey('campo-paradas')), '3');
    await tester.pump();
    expect(_canSave(tester), isFalse);
    expect(find.text('Mais paradas que pacotes.'), findsOneWidget);
  });

  testWidgets('o que não casou com a lista aparece, com a contagem', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('1 pacote sem bairro reconhecido'), findsOneWidget);
    expect(find.textContaining('"Água Fria"'), findsOneWidget);
  });

  testWidgets('diz quais bairros do agendamento a leitura substitui', (
    tester,
  ) async {
    await _pump(tester, previous: const ['Aldeota', 'Papicu']);

    expect(
      find.text('Substitui o que estava marcado no agendamento: Aldeota.'),
      findsOneWidget,
    );
  });

  testWidgets('sem diferença do agendamento, nada a avisar', (tester) async {
    await _pump(tester, previous: const ['Papicu']);

    expect(find.byKey(const ValueKey('substitui')), findsNothing);
  });

  testWidgets('voltar a ler não salva', (tester) async {
    final result = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('voltar-a-ler')));

    expect(result.back, 1);
    expect(result.saved, isNull);
  });
}
