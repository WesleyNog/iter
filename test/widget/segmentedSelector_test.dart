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

/// O mesmo trilho no modo de múltipla escolha, com o conjunto aceso vindo de
/// fora — é assim que a lista o usa, com `RouteFilter.companies`.
Future<void> _pumpMulti(
  WidgetTester tester, {
  required Set<_Aba> selected,
  ValueChanged<_Aba>? onChanged,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SegmentedSelector<_Aba>.multi(
          keyPrefix: 'filtro',
          segments: _abas(),
          selected: selected,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  );
}

/// Quantos segmentos estão acesos, contados como o teste da escolha única
/// conta: um `Opacity` por segmento, e o aceso é o que está em 1.
int _acesos(WidgetTester tester) {
  return tester
      .widgetList<Opacity>(find.byType(Opacity))
      .where((widget) => widget.opacity == 1)
      .length;
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

  group('múltipla escolha', () {
    testWidgets('dois segmentos ficam acesos ao mesmo tempo', (tester) async {
      await _pumpMulti(tester, selected: {_Aba.amigos, _Aba.feed});

      // O que a escolha única não consegue dizer: acender dois é o motivo do
      // construtor existir.
      expect(_acesos(tester), 2);
    });

    testWidgets('conjunto vazio deixa todos apagados', (tester) async {
      await _pumpMulti(tester, selected: const {});

      // Vazio quer dizer "passa tudo" no filtro, e mesmo assim o trilho fica
      // todo apagado: quem explica isso é o estado vazio da lista, não daqui.
      expect(_acesos(tester), 0);
    });

    testWidgets('conjunto com todos deixa todos acesos', (tester) async {
      await _pumpMulti(tester, selected: _Aba.values.toSet());

      expect(_acesos(tester), 3);
    });

    testWidgets('tocar num segmento emite o valor dele', (tester) async {
      final tocados = <_Aba>[];
      await _pumpMulti(
        tester,
        selected: {_Aba.ranking},
        onChanged: tocados.add,
      );

      // Inclusive o que já está aceso: `onChanged` é "o usuário tocou NESTE",
      // e não "este passou a estar marcado".
      for (final suffix in ['ranking', 'feed', 'amigos']) {
        await tester.tap(find.byKey(ValueKey('filtro-$suffix')));
        await tester.pump();
      }

      expect(tocados, [_Aba.ranking, _Aba.feed, _Aba.amigos]);
    });

    testWidgets('o widget não alterna nada por conta própria', (tester) async {
      await _pumpMulti(tester, selected: {_Aba.ranking});

      await tester.tap(find.byKey(const ValueKey('filtro-ranking')));
      await tester.pump();

      // Quem alterna é o chamador, com `RouteFilter.toggleCompany`. Se o
      // trilho apagasse sozinho o que acabou de ser tocado, ele e o filtro
      // discordariam do que está marcado até o rebuild seguinte.
      expect(_acesos(tester), 1);
    });

    testWidgets('as chaves seguem prefixo-sufixo', (tester) async {
      await _pumpMulti(tester, selected: const {});

      for (final suffix in ['amigos', 'ranking', 'feed']) {
        expect(find.byKey(ValueKey('filtro-$suffix')), findsOneWidget);
      }
    });
  });
}
