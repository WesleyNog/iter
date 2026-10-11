import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/slidingIndicator.dart';

const _pilula = ValueKey('pilula');

/// Um trilho de 300 px com três fatias de 100 — as contas do teste ficam
/// redondas e legíveis.
Future<void> _pump(
  WidgetTester tester, {
  required int index,
  bool semAnimacao = false,
  double inset = 0,
  double Function(double slot)? widthFor,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: semAnimacao),
          child: Center(
            child: SizedBox(
              width: 300,
              height: 40,
              child: SlidingIndicator(
                count: 3,
                index: index,
                inset: inset,
                widthFor: widthFor,
                child: const SizedBox(key: _pilula),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// As bordas da pílula medidas a partir da esquerda do trilho.
({double left, double right}) _bordas(WidgetTester tester) {
  final trilho = tester.getRect(find.byType(SlidingIndicator));
  final pilula = tester.getRect(find.byKey(_pilula));
  return (left: pilula.left - trilho.left, right: pilula.right - trilho.left);
}

void main() {
  testWidgets('parado, ocupa a fatia do índice', (tester) async {
    await _pump(tester, index: 1);

    expect(_bordas(tester), (left: 100.0, right: 200.0));
  });

  testWidgets('inset recua dos dois lados, widthFor centra na fatia', (
    tester,
  ) async {
    await _pump(tester, index: 0, inset: 4);
    expect(_bordas(tester), (left: 4.0, right: 96.0));

    // O caso da barra de baixo: marcador de largura própria no meio da fatia.
    await _pump(tester, index: 2, widthFor: (slot) => 60);
    await tester.pumpAndSettle();
    expect(_bordas(tester), (left: 220.0, right: 280.0));
  });

  testWidgets('no meio do deslize, uma pílula só, entre a origem e o destino', (
    tester,
  ) async {
    await _pump(tester, index: 0);
    await _pump(tester, index: 2);
    await tester.pump(const Duration(milliseconds: 150));

    // O defeito do trilho antigo era haver duas, meio acesas, neste instante.
    expect(find.byKey(_pilula), findsOneWidget);

    final meio = _bordas(tester);
    expect(meio.left, greaterThan(0));
    expect(meio.left, lessThan(200));
    expect(meio.right, greaterThan(100));
    expect(meio.right, lessThan(300));

    await tester.pumpAndSettle();
    expect(_bordas(tester), (left: 200.0, right: 300.0));
  });

  testWidgets('estica no caminho: a borda da frente sai antes da de trás', (
    tester,
  ) async {
    await _pump(tester, index: 0);
    await _pump(tester, index: 2);
    await tester.pump(const Duration(milliseconds: 150));

    // Fatia de 100 px: mais larga que isso, só esticada. É o efeito "líquido"
    // que a decisão 2 da spec pediu nos três trilhos.
    final meio = _bordas(tester);
    expect(meio.right - meio.left, greaterThan(100));
  });

  testWidgets('trocar de alvo no meio do caminho parte de onde ela está', (
    tester,
  ) async {
    await _pump(tester, index: 0);
    await _pump(tester, index: 2);
    await tester.pump(const Duration(milliseconds: 150));
    final antes = _bordas(tester);

    // Novo toque antes de chegar: o primeiro quadro tem de estar onde a pílula
    // estava, não de volta na fatia 0 — senão ela salta para trás.
    await _pump(tester, index: 1);
    await tester.pump(const Duration(milliseconds: 16));
    final depois = _bordas(tester);

    expect((depois.left - antes.left).abs(), lessThan(15));
    expect((depois.right - antes.right).abs(), lessThan(15));

    await tester.pumpAndSettle();
    expect(_bordas(tester), (left: 100.0, right: 200.0));
  });

  testWidgets('quem pediu menos movimento recebe a pílula já no lugar', (
    tester,
  ) async {
    await _pump(tester, index: 0, semAnimacao: true);
    await _pump(tester, index: 2, semAnimacao: true);

    expect(_bordas(tester), (left: 200.0, right: 300.0));
  });

  test('o gesto inteiro é a borda mais o atraso', () {
    // `total` é escrito à mão porque soma de `Duration` não é constante — e as
    // curvas do conteúdo (`contentCurve`) dividem pelos mesmos números. Se um
    // deles mudar sozinho, o rótulo deixa de acompanhar a pílula.
    expect(
      SlidingIndicator.total,
      SlidingIndicator.edge + SlidingIndicator.lag,
    );
    final acende = SlidingIndicator.contentCurve(on: true) as Interval;
    final apaga = SlidingIndicator.contentCurve(on: false) as Interval;
    final total = SlidingIndicator.total.inMilliseconds;
    expect(acende.end, SlidingIndicator.edge.inMilliseconds / total);
    expect(apaga.begin, SlidingIndicator.lag.inMilliseconds / total);
  });
}
