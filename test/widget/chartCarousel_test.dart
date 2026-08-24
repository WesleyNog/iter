import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/chartCarousel.dart';

Future<void> _pump(WidgetTester tester, int pageCount) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChartCarousel(
          height: 200,
          pages: [
            for (var index = 0; index < pageCount; index++)
              Center(child: Text('página $index')),
          ],
        ),
      ),
    ),
  );
}

/// As bolinhas são os únicos `AnimatedContainer` do carrossel.
int _dots(WidgetTester tester) =>
    tester.widgetList(find.byType(AnimatedContainer)).length;

void main() {
  testWidgets('desenha uma bolinha por página', (tester) async {
    await _pump(tester, 5);

    expect(_dots(tester), 5);
    expect(find.text('página 0'), findsOneWidget);
  });

  testWidgets('com uma página só, não desenha bolinha nenhuma', (tester) async {
    await _pump(tester, 1);

    // Uma bolinha sozinha promete uma página que não existe — é o caso do
    // carrossel de bairros depois que o insucesso saiu dele.
    expect(_dots(tester), 0);
    expect(find.text('página 0'), findsOneWidget);
  });

  group('totalHeight', () {
    test('com mais de uma página, soma o bloco de bolinhas', () {
      const carousel = ChartCarousel(height: 200, pages: [Text('a'), Text('b')]);

      // O bloco é o respiro mais a fileira, cuja altura é a da bolinha ativa.
      expect(carousel.totalHeight, greaterThan(carousel.height));
      expect(carousel.totalHeight - carousel.height, 10 + 11);
    });

    test('com uma página só, é a altura do PageView e nada mais', () {
      // O carrossel de bairros: sem bolinhas, somar 21px o empurraria para
      // fora do lugar na pilha.
      const carousel = ChartCarousel(height: 200, pages: [Text('a')]);

      expect(carousel.totalHeight, carousel.height);
    });

    // Os dois casos acima conferem a conta contra números escritos aqui; estes
    // conferem a conta contra o desenho, que é o que impede o getter de mentir
    // se um espaçamento do `build` mudar sozinho.
    testWidgets('bate com a altura que o carrossel realmente ocupa', (
      tester,
    ) async {
      const carousel = ChartCarousel(
        height: 200,
        pages: [Text('a'), Text('b'), Text('c')],
      );
      await _pumpMeasuring(tester, carousel);

      expect(
        tester.getSize(find.byType(ChartCarousel)).height,
        carousel.totalHeight,
      );
    });

    testWidgets('bate também quando não há bolinhas para desenhar', (
      tester,
    ) async {
      const carousel = ChartCarousel(height: 200, pages: [Text('a')]);
      await _pumpMeasuring(tester, carousel);

      expect(
        tester.getSize(find.byType(ChartCarousel)).height,
        carousel.totalHeight,
      );
    });
  });
}

/// Monta o carrossel sem altura imposta de fora, para a árvore poder dizer
/// quanto ela ocupa.
///
/// Direto no `body` do `Scaffold` a `Column` recebe altura apertada e estica
/// até a tela inteira — a medida responderia pelo `Scaffold`, não pelo
/// carrossel, e passaria valendo qualquer coisa.
Future<void> _pumpMeasuring(WidgetTester tester, ChartCarousel carousel) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: carousel))),
  );
}
