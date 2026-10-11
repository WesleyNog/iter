import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/periodSelection.dart';
import 'package:iter/widget/glassTabs.dart';
import 'package:iter/widget/periodFilter.dart';
import 'package:iter/widget/periodNavigator.dart';

final _hoje = DateTime(2026, 10, 11);

Future<List<PeriodSelection>> _pump(
  WidgetTester tester,
  PeriodSelection selection,
) async {
  final emitidos = <PeriodSelection>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: PeriodNavigator(selection: selection, onChanged: emitidos.add),
        ),
      ),
    ),
  );
  return emitidos;
}

void main() {
  testWidgets('três abas de vidro, sem rolagem lateral', (tester) async {
    await _pump(tester, PeriodSelection.month(0, _hoje));

    expect(find.byType(GlassTabs<PeriodKind>), findsOneWidget);
    for (final kind in PeriodKind.values) {
      expect(find.byKey(ValueKey('periodo-${kind.name}')), findsOneWidget);
    }
    // O defeito dos chips era rolar e esconder o Personalizado fora da tela.
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('no mês atual: o rótulo do mês e a seta › apagada', (
    tester,
  ) async {
    await _pump(tester, PeriodSelection.month(0, _hoje));

    expect(find.text('OUTUBRO 2026'), findsOneWidget);
    final seguinte = tester.widget<IconButton>(
      find.byKey(const ValueKey('periodo-seguinte')),
    );
    expect(seguinte.onPressed, isNull);
  });

  testWidgets('as setas emitem um passo', (tester) async {
    final emitidos = await _pump(tester, PeriodSelection.week(-2, _hoje));

    await tester.tap(find.byKey(const ValueKey('periodo-anterior')));
    await tester.tap(find.byKey(const ValueKey('periodo-seguinte')));

    expect(emitidos.map((p) => (p.kind, p.offset)), [
      (PeriodKind.semana, -3),
      (PeriodKind.semana, -1),
    ]);
  });

  testWidgets('tocar numa aba troca de tipo', (tester) async {
    final emitidos = await _pump(tester, PeriodSelection.month(0, _hoje));

    await tester.tap(find.byKey(const ValueKey('periodo-semana')));
    await tester.tap(find.byKey(const ValueKey('periodo-personalizado')));

    expect(emitidos.map((p) => p.kind), [
      PeriodKind.semana,
      PeriodKind.personalizado,
    ]);
  });

  testWidgets('as roletas só no Personalizado, as setas só fora dele', (
    tester,
  ) async {
    await _pump(tester, PeriodSelection.month(-2, _hoje));
    expect(find.byType(PeriodFilter), findsNothing);
    expect(find.byKey(const ValueKey('periodo-anterior')), findsOneWidget);

    await _pump(
      tester,
      PeriodSelection.custom((
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 12),
      )),
    );
    expect(find.byType(PeriodFilter), findsOneWidget);
    expect(find.byKey(const ValueKey('periodo-anterior')), findsNothing);
    // As datas que estavam na tela, nas roletas.
    expect(find.text('01/08/2026'), findsOneWidget);
    expect(find.text('12/08/2026'), findsOneWidget);
  });

  testWidgets('o rótulo entre as setas não quebra linha', (tester) async {
    await _pump(tester, PeriodSelection.week(0, DateTime(2026, 1, 2)));

    // A causa, não "cabe?": uma linha, com reticências.
    final rotulo = tester.widget<Text>(find.text('29/12/2025 – 04/01/2026'));
    expect(rotulo.maxLines, 1);
    expect(rotulo.overflow, TextOverflow.ellipsis);
  });
}
