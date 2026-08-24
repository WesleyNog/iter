import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/widget/barRankChart.dart';
import 'package:iter/widget/chartCard.dart';

Future<void> pumpChart(
  WidgetTester tester, {
  required List<RankEntry> entries,
  String Function(double)? formatValue,
  String? footnote,
  bool showShare = true,
  ChartPalette palette = ChartPalette.azul,
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
            // Em produção todas as páginas têm eyebrow, e ele come
            // altura da área do gráfico: sem ele a guarda mede uma
            // folga que a tela não tem.
            eyebrow: 'Rotas concluídas e pagas',
            entries: entries,
            formatValue: formatValue ?? (value) => value.toStringAsFixed(0),
            emptyMessage: 'Nada no período',
            footnote: footnote,
            showShare: showShare,
            palette: palette,
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

  group('paleta', () {
    /// O gradiente que o card realmente pintou.
    List<Color> gradienteDe(WidgetTester tester) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ChartCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      return (decoration.gradient! as LinearGradient).colors;
    }

    const entries = [RankEntry('Shopee', 4), RankEntry('Amazon', 3)];

    testWidgets('o padrão continua sendo o azul', (tester) async {
      await pumpChart(tester, entries: entries);
      expect(gradienteDe(tester), ChartPalette.azul.gradient);
    });

    testWidgets('a paleta de alerta troca o fundo', (tester) async {
      await pumpChart(
        tester,
        entries: entries,
        palette: ChartPalette.alerta,
      );
      expect(gradienteDe(tester), ChartPalette.alerta.gradient);
    });

    testWidgets('trocar o fundo troca as barras junto', (tester) async {
      // As duas coisas andam juntas de propósito: as cores de barra foram
      // escolhidas contra um fundo específico, e o salmão do azul sobre o
      // laranja é a mesma cor duas vezes.
      expect(
        ChartPalette.alerta.bars,
        isNot(equals(ChartPalette.azul.bars)),
      );
      expect(
        ChartPalette.alerta.progress,
        isNot(equals(ChartPalette.azul.progress)),
      );
    });

    testWidgets('as barras usam a cor da paleta recebida', (tester) async {
      await pumpChart(
        tester,
        entries: entries,
        palette: ChartPalette.alerta,
      );

      final pintadas = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>()
          .toSet();

      expect(pintadas.contains(ChartPalette.alerta.bars.first), isTrue);
      expect(pintadas.contains(ChartPalette.azul.bars.first), isFalse);
    });
  });

  group('largura fixa do degrau', () {
    /// A barra desenhada com a cor do primeiro degrau.
    Finder primeiraBarra() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == ChartPalette.azul.bars.first,
    );

    testWidgets('uma barra tem a mesma largura que teria com quatro', (
      tester,
    ) async {
      // A causa da queixa: com `Expanded`, um ranking de um item só esticava a
      // barra pela largura inteira do card, e um retângulo do tamanho do
      // cartão não se lê como gráfico.
      await pumpChart(
        tester,
        entries: const [
          RankEntry('A', 4),
          RankEntry('B', 3),
          RankEntry('C', 2),
          RankEntry('D', 1),
        ],
      );
      final comQuatro = tester.getSize(primeiraBarra()).width;

      await pumpChart(tester, entries: const [RankEntry('A', 4)]);
      final comUma = tester.getSize(primeiraBarra()).width;

      expect(comUma, comQuatro);
    });

    testWidgets('duas barras também mantêm a largura', (tester) async {
      await pumpChart(
        tester,
        entries: const [
          RankEntry('A', 4),
          RankEntry('B', 3),
          RankEntry('C', 2),
          RankEntry('D', 1),
        ],
      );
      final comQuatro = tester.getSize(primeiraBarra()).width;

      await pumpChart(
        tester,
        entries: const [RankEntry('A', 7), RankEntry('B', 0)],
      );

      expect(tester.getSize(primeiraBarra()).width, comQuatro);
    });

    testWidgets('a barra sozinha fica centralizada no card', (tester) async {
      await pumpChart(tester, entries: const [RankEntry('A', 4)]);

      final centroDoCard = tester.getCenter(find.byType(ChartCard)).dx;
      final centroDaBarra = tester.getCenter(primeiraBarra()).dx;

      expect(centroDaBarra, closeTo(centroDoCard, 1));
    });

    testWidgets('o rótulo continua debaixo da sua barra', (tester) async {
      // Duas linhas separadas desenham barra e rótulo; largura de slot
      // diferente entre elas desalinharia uma da outra.
      await pumpChart(
        tester,
        entries: const [RankEntry('Nublado', 7), RankEntry('Sol', 0)],
      );

      expect(
        tester.getCenter(find.text('Nublado')).dx,
        closeTo(tester.getCenter(primeiraBarra()).dx, 1),
      );
    });

    testWidgets('com quatro degraus a fila ocupa a largura toda', (
      tester,
    ) async {
      // O caso que já estava certo não pode ter mudado: com `maxBars` barras,
      // slot × 4 é exatamente a largura disponível.
      await pumpChart(
        tester,
        entries: const [
          RankEntry('A', 4),
          RankEntry('B', 3),
          RankEntry('C', 2),
          RankEntry('D', 1),
        ],
      );

      final larguraDaBarra = tester.getSize(primeiraBarra()).width;
      final larguraDoCard = tester.getSize(find.byType(ChartCard)).width;

      // 16 de padding do card em cada lado, 5 de padding do degrau em cada.
      expect(larguraDaBarra * 4, closeTo(larguraDoCard - 32 - 40, 1));
    });
  });
}
