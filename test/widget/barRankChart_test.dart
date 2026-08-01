import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/widget/barRankChart.dart';

Future<void> pumpChart(
  WidgetTester tester, {
  required List<RankEntry> entries,
  String Function(double)? formatValue,
  String? footnote,
  bool showShare = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Altura fixa: no app o card vive dentro de um carrossel, e o gráfico
        // usa Expanded contando com ela.
        body: SizedBox(
          height: 340,
          child: BarRankChart(
            title: 'Empresas',
            entries: entries,
            formatValue: formatValue ?? (value) => value.toStringAsFixed(0),
            emptyMessage: 'Nada no período',
            footnote: footnote,
            showShare: showShare,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra rótulo e valor de cada degrau', (tester) async {
    await pumpChart(
      tester,
      entries: const [
        RankEntry('Mercado Livre', 150),
        RankEntry('Amazon', 50),
      ],
    );

    expect(find.text('Mercado Livre'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(find.text('Amazon'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('usa o formatador recebido', (tester) async {
    await pumpChart(
      tester,
      entries: const [RankEntry('Amazon', 12.5)],
      formatValue: (value) => '${value.toStringAsFixed(1)}%',
    );

    expect(find.text('12.5%'), findsOneWidget);
  });

  testWidgets('mostra a participação de cada degrau no total', (tester) async {
    await pumpChart(
      tester,
      entries: const [RankEntry('Amazon', 75), RankEntry('Shopee', 25)],
    );

    expect(find.text('75.0%'), findsOneWidget);
    expect(find.text('25.0%'), findsOneWidget);
  });

  testWidgets('corta no top 4, mas a participação olha o total inteiro', (
    tester,
  ) async {
    await pumpChart(
      tester,
      entries: const [
        RankEntry('A', 40),
        RankEntry('B', 30),
        RankEntry('C', 20),
        RankEntry('D', 5),
        RankEntry('E', 5),
      ],
    );

    expect(find.text('E'), findsNothing);
    // 40 de 100 (com o E fora da tela), e não 40 de 95.
    expect(find.text('40.0%'), findsOneWidget);
  });

  testWidgets('sem dado, mostra a mensagem de vazio', (tester) async {
    await pumpChart(tester, entries: const []);

    expect(find.text('Nada no período'), findsOneWidget);
  });

  testWidgets('ranking todo zerado não quebra e some com a participação', (
    tester,
  ) async {
    await pumpChart(
      tester,
      entries: const [RankEntry('Amazon', 0), RankEntry('Shopee', 0)],
    );

    // Sem divisão por zero: os degraus aparecem, a porcentagem não.
    expect(find.text('Amazon'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('showShare desligado esconde a participação', (tester) async {
    await pumpChart(
      tester,
      entries: const [RankEntry('Amazon', 5), RankEntry('Shopee', 10)],
      formatValue: (value) => '${value.toStringAsFixed(1)}%',
      showShare: false,
    );

    // Os valores são taxas; somá-las para tirar participação não diz nada.
    expect(find.text('5.0%'), findsOneWidget);
    expect(find.text('33.3%'), findsNothing);
  });

  testWidgets('mostra a ressalva quando recebe uma', (tester) async {
    await pumpChart(
      tester,
      entries: const [RankEntry('Amazon', 10)],
      footnote: 'considera só rotas com pacotes informados',
    );

    expect(
      find.text('considera só rotas com pacotes informados'),
      findsOneWidget,
    );
  });
}
