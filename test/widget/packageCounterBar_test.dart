import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/packageLabel.dart';
import 'package:iter/Utils/packageSession.dart';
import 'package:iter/widget/packageCounterBar.dart';
import 'package:iter/widget/packageList.dart';

LabelRead _read(String id, PackageType? type, {String? stop}) => LabelRead(
  shipmentId: id,
  type: type,
  bairro: 'Papicu',
  stopKey: stop ?? 'cep-$id',
);

class _Taps {
  final opened = <PackageListFilter>[];
  int finished = 0;
}

Future<_Taps> _pump(WidgetTester tester, PackageSession session) async {
  final taps = _Taps();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: PackageCounterBar(
            session: session,
            onOpenList: taps.opened.add,
            onFinish: () => taps.finished++,
          ),
        ),
      ),
    ),
  );
  return taps;
}

PackageTypeChip _chip(WidgetTester tester, String letter) =>
    tester.widget<PackageTypeChip>(find.byKey(ValueKey('chip-$letter')));

void main() {
  testWidgets('conta cada tipo, o total e as paradas', (tester) async {
    final session = PackageSession()
      ..add(_read('1', PackageType.residencial, stop: 'p1'))
      ..add(_read('2', PackageType.residencial, stop: 'p1'))
      ..add(_read('3', PackageType.comercial))
      ..add(_read('4', PackageType.agencia));
    await _pump(tester, session);

    expect(find.textContaining('4 pacotes'), findsOneWidget);
    expect(find.textContaining('3 paradas'), findsOneWidget);
    expect(_chip(tester, 'R').count, 2);
    expect(_chip(tester, 'C').count, 1);
    expect(_chip(tester, 'A').count, 1);
  });

  testWidgets('A tem o destaque mais forte, C o do meio, R nenhum', (
    tester,
  ) async {
    // A causa, não o pixel: qual nível cada chip recebe. Como o nível vira
    // cor e tamanho é coisa de aparelho.
    await _pump(tester, PackageSession()..add(_read('1', null)));

    expect(_chip(tester, 'A').emphasis, ChipEmphasis.forte);
    expect(_chip(tester, 'C').emphasis, ChipEmphasis.alerta);
    expect(_chip(tester, 'R').emphasis, ChipEmphasis.normal);
  });

  testWidgets('o "?" só aparece quando há pacote sem letra', (tester) async {
    await _pump(tester, PackageSession()..add(_read('1', PackageType.agencia)));
    expect(find.byKey(const ValueKey('chip-?')), findsNothing);

    await _pump(tester, PackageSession()..add(_read('1', null)));
    expect(_chip(tester, '?').count, 1);
  });

  testWidgets('singular para um pacote e uma parada', (tester) async {
    await _pump(tester, PackageSession()..add(_read('1', PackageType.agencia)));

    expect(find.textContaining('1 pacote'), findsOneWidget);
    expect(find.textContaining('1 parada'), findsOneWidget);
  });

  testWidgets('tocar num tipo abre a lista daquele tipo', (tester) async {
    final taps = await _pump(
      tester,
      PackageSession()..add(_read('1', PackageType.agencia)),
    );

    await tester.tap(find.byKey(const ValueKey('chip-A')));
    await tester.tap(find.byKey(const ValueKey('total')));

    expect(taps.opened, [PackageListFilter.agencia, PackageListFilter.todos]);
  });

  testWidgets('Finalizar não existe sem nenhum pacote', (tester) async {
    final taps = await _pump(tester, PackageSession());

    await tester.tap(find.byKey(const ValueKey('finalizar')));

    expect(taps.finished, 0);
  });
}
