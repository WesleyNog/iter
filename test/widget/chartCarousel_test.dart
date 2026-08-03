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
}
