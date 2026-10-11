import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/glassSurface.dart';
import 'package:iter/widget/glassTabs.dart';
import 'package:iter/widget/segmentedSelector.dart';
import 'package:iter/widget/slidingIndicator.dart';

enum _Aba { amigos, ranking, feed }

const _abas = [
  SegmentOption(value: _Aba.amigos, label: 'Amigos', keySuffix: 'amigos'),
  SegmentOption(value: _Aba.ranking, label: 'Ranking', keySuffix: 'ranking'),
  SegmentOption(value: _Aba.feed, label: 'Feed', keySuffix: 'feed'),
];

Future<void> _pump(
  WidgetTester tester, {
  _Aba selected = _Aba.ranking,
  ValueChanged<_Aba>? onChanged,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassTabs<_Aba>(
            keyPrefix: 'aba',
            tabs: _abas,
            selected: selected,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('é o vidro da barra de baixo: um blur, uma pílula azul', (
    tester,
  ) async {
    await _pump(tester);

    // Blur duplicado é vidro leitoso e o dobro do custo — a regra do
    // `GlassSurface`.
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(SlidingIndicator), findsOneWidget);
    expect(find.byType(GlassIndicator), findsOneWidget);
  });

  testWidgets('cada aba avisa o próprio valor, inclusive a já selecionada', (
    tester,
  ) async {
    final tocadas = <_Aba>[];
    await _pump(tester, onChanged: tocadas.add);

    for (final suffix in ['ranking', 'feed', 'amigos']) {
      await tester.tap(find.byKey(ValueKey('aba-$suffix')));
      await tester.pump();
    }

    expect(tocadas, [_Aba.ranking, _Aba.feed, _Aba.amigos]);
  });

  testWidgets('o toque ao lado da palavra ainda troca de aba', (tester) async {
    final tocadas = <_Aba>[];
    await _pump(tester, onChanged: tocadas.add);

    // À direita de "Feed", fora do texto e ainda dentro da aba.
    final texto = tester.getRect(find.text('Feed'));
    await tester.tapAt(Offset(texto.right + 30, texto.center.dy));
    await tester.pump();

    expect(tocadas, [_Aba.feed]);
  });

  testWidgets('o rótulo aceso é branco, os outros no azul apagado', (
    tester,
  ) async {
    await _pump(tester, selected: _Aba.feed);

    Color? cor(String rotulo) =>
        tester.widget<Text>(find.text(rotulo)).style?.color;

    expect(cor('Feed'), Colors.white);
    expect(cor('Amigos'), GlassIndicator.accent.withValues(alpha: 0.7));
  });

  testWidgets('o rótulo não quebra linha e encolhe antes de cortar', (
    tester,
  ) async {
    await _pump(tester);

    // A causa, não "cabe?": a fonte do teste é quadrada e mede outra coisa
    // que a do aparelho. Uma linha só, e um `FittedBox` que reduz em vez de
    // trocar "Personalizado" por "Personaliza…".
    final texto = tester.widget<Text>(find.text('Ranking'));
    expect(texto.maxLines, 1);
    final ajuste = tester.widget<FittedBox>(
      find.ancestor(of: find.text('Ranking'), matching: find.byType(FittedBox)),
    );
    expect(ajuste.fit, BoxFit.scaleDown);
  });
}
