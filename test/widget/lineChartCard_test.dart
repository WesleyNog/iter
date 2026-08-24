import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/chartCarousel.dart';
import 'package:iter/widget/lineChartCard.dart';

/// Monta o card na **mesma altura** que a tela usa (330), porque é aí que
/// overflow aparece: um card que cabe em 600px pode estourar no carrossel.
Future<void> pumpLine(
  WidgetTester tester, {
  required List<double> values,
  int firstX = 0,
  Widget? trailing,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 330,
          child: LineChartCard(
            title: 'Por dia da semana',
            // Em produção todas as páginas têm eyebrow, e ele come
            // altura da área do gráfico: sem ele a guarda mede uma
            // folga que a tela não tem.
            eyebrow: 'Rotas concluídas e pagas',
            values: values,
            firstX: firstX,
            labelOf: (x) => 'x$x',
            tooltipLabelOf: (x) => 'ponto $x',
            formatValue: (value) => 'R\$ ${value.toStringAsFixed(0)}',
            formatAxis: (value) => value.toStringAsFixed(0),
            emptyMessage: 'Nenhuma rota no período.',
            trailing: trailing,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('desenha a série sem estourar a altura do carrossel', (
    tester,
  ) async {
    await pumpLine(tester, values: [10, 0, 30, 0, 50, 5, 0]);

    expect(find.text('POR DIA DA SEMANA'), findsOneWidget);
    expect(find.text('x0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('série toda zerada mostra a mensagem de vazio', (tester) async {
    await pumpLine(tester, values: [0, 0, 0, 0, 0, 0, 0]);

    // Reta no chão parece dado; a mensagem diz a verdade.
    expect(find.text('Nenhuma rota no período.'), findsOneWidget);
  });

  testWidgets('lista vazia não quebra', (tester) async {
    await pumpLine(tester, values: []);

    expect(find.text('Nenhuma rota no período.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('respeita o firstX do turno', (tester) async {
    await pumpLine(tester, values: [1, 2, 3], firstX: 5);

    expect(find.text('x5'), findsOneWidget);
    expect(find.text('x0'), findsNothing);
  });

  testWidgets('mostra o widget do canto do título', (tester) async {
    await pumpLine(
      tester,
      values: [1, 2, 3],
      trailing: const Text('Manhã'),
    );

    expect(find.text('Manhã'), findsOneWidget);
  });

  testWidgets('o carrossel troca de página e acompanha nas bolinhas', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChartCarousel(
            height: 200,
            pages: [
              Center(child: Text('primeira')),
              Center(child: Text('segunda')),
            ],
          ),
        ),
      ),
    );

    expect(find.text('primeira'), findsOneWidget);

    await tester.drag(find.text('primeira'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('segunda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
