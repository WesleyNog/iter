import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/segmentedSelector.dart';

enum _Aba { amigos, ranking, feed }

/// As três abas da tela de Amigos, que é o caso que estreia o rótulo de texto
/// neste trilho — o `CompanyFilter` sempre desenhou ícone.
List<SegmentOption<_Aba>> _abas() {
  return const [
    SegmentOption(value: _Aba.amigos, label: 'Amigos', keySuffix: 'amigos'),
    SegmentOption(value: _Aba.ranking, label: 'Ranking', keySuffix: 'ranking'),
    SegmentOption(value: _Aba.feed, label: 'Feed', keySuffix: 'feed'),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  _Aba selected = _Aba.amigos,
  ValueChanged<_Aba>? onChanged,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SegmentedSelector<_Aba>(
          keyPrefix: 'aba',
          segments: _abas(),
          selected: selected,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('os três segmentos têm a mesma largura', (tester) async {
    await _pump(tester);

    // Comparar os segmentos entre si, e não com um terço da tela: o trilho
    // tem `padding: 4` e cada segmento `margin: 2`, então a fração exata
    // nasceria vermelha e "ajustar até passar" seria projetar para o teste.
    final larguras = ['amigos', 'ranking', 'feed']
        .map((suffix) => tester.getSize(find.byKey(ValueKey('aba-$suffix'))))
        .map((size) => size.width)
        .toList();

    expect(larguras[0], larguras[1]);
    expect(larguras[1], larguras[2]);
  });

  testWidgets('cada segmento avisa o próprio valor', (tester) async {
    final escolhidos = <_Aba>[];
    await _pump(tester, onChanged: escolhidos.add);

    for (final suffix in ['ranking', 'feed', 'amigos']) {
      await tester.tap(find.byKey(ValueKey('aba-$suffix')));
      await tester.pump();
    }

    expect(escolhidos, [_Aba.ranking, _Aba.feed, _Aba.amigos]);
  });

  testWidgets('só o segmento selecionado fica sem transparência', (
    tester,
  ) async {
    await _pump(tester, selected: _Aba.ranking);

    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((widget) => widget.opacity)
        .toList();

    expect(opacities.length, 3);
    expect(opacities.where((value) => value == 1).length, 1);
  });

  testWidgets('sem child, o rótulo vira texto e não leva tooltip', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Amigos'), findsOneWidget);
    expect(find.text('Ranking'), findsOneWidget);
    expect(find.text('Feed'), findsOneWidget);
    // O rótulo já está visível; o balão seria ruído.
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('o rótulo de texto não quebra linha', (tester) async {
    await _pump(tester);

    // Não é asserção de "o texto cabe" — a fonte do teste é quadrada e mede
    // outra coisa que a do aparelho. É a *causa*: uma linha só, com corte por
    // reticências em vez de quebra.
    final texto = tester.widget<Text>(find.text('Ranking'));
    expect(texto.maxLines, 1);
    expect(texto.overflow, TextOverflow.ellipsis);
  });
}
