import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/chartCard.dart';

const _recorte = 'Rotas concluídas e pagas';

Future<void> _pump(WidgetTester tester, {String? eyebrow}) {
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Altura de um carrossel de verdade: é lá que o card mora.
        body: SizedBox(
          height: 340,
          child: ChartCard(
            title: 'Valor por empresa',
            eyebrow: eyebrow,
            stats: const [ChartStat('TOTAL', r'R$ 1.200,00')],
            child: const ChartEmpty('Nenhuma rota no período.'),
          ),
        ),
      ),
    ),
  );
}

/// Os filhos da coluna do card, na ordem em que ele os empilha.
///
/// A pergunta do teste é de **árvore**, não de aparência: sem eyebrow nada
/// pode entrar aqui — nem a linha, nem o `SizedBox` que a separaria do título.
List<Widget> _filhosDoCard(WidgetTester tester) => tester
    .widget<Column>(
      find
          .descendant(of: find.byType(ChartCard), matching: find.byType(Column))
          .first,
    )
    .children;

/// A decoração que o card realmente pintou.
BoxDecoration _decoracao(WidgetTester tester) =>
    tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byType(ChartCard),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  group('eyebrow', () {
    testWidgets('aparece acima do título quando recebido', (tester) async {
      await _pump(tester, eyebrow: _recorte);

      expect(find.text(_recorte), findsOneWidget);
      // O mesmo ícone do rótulo de seção que a linha substitui na tela.
      expect(find.byIcon(Icons.insights_outlined), findsOneWidget);
      // Primeiro filho da coluna: acima do título, e não abaixo dele.
      expect(_filhosDoCard(tester).first.key, const Key('chart-eyebrow'));
    });

    testWidgets('sem eyebrow, nem a linha nem o espaço dela entram na árvore', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byKey(const Key('chart-eyebrow')), findsNothing);
      expect(find.byIcon(Icons.insights_outlined), findsNothing);
      // Os seis cards que não pedem recorte têm de continuar idênticos: a
      // coluna começa direto na linha do título, sem espaçador sobrando.
      expect(_filhosDoCard(tester).first, isA<Row>());
    });

    testWidgets('a linha custa exatamente ela mesma e o seu espaço', (
      tester,
    ) async {
      await _pump(tester);
      final sem = _filhosDoCard(tester).length;

      await _pump(tester, eyebrow: _recorte);
      expect(_filhosDoCard(tester).length, sem + 2);
    });

    testWidgets('é de uma linha só e corta com reticências', (tester) async {
      await _pump(tester, eyebrow: _recorte);

      final texto = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('chart-eyebrow')),
          matching: find.byType(Text),
        ),
      );

      // A altura do card é fixa dentro do carrossel: uma ressalva que quebrasse
      // em duas linhas sairia da altura do gráfico. Quanto de texto cabe é
      // pergunta para o aparelho — aqui se testa que ele não empurra nada.
      expect(texto.maxLines, 1);
      expect(texto.overflow, TextOverflow.ellipsis);
    });
  });

  group('sem sombra, e por um motivo medido', () {
    testWidgets('o card não pendura BoxShadow', (tester) async {
      // Não é esquecimento. Todo `ChartCard` é página de um `PageView`, e o
      // `PageView` instala um `ClipRect` do tamanho exato da página — sombra
      // só pinta fora do retângulo do widget, então ela seria recortada
      // inteira. Pendurá-la é código morto com cara de enfeite.
      await _pump(tester);
      expect(_decoracao(tester).boxShadow, anyOf(isNull, isEmpty));
    });

    testWidgets('e o PageView de fato recorta no retângulo da página', (
      tester,
    ) async {
      // A prova do motivo acima, para ninguém "consertar" a falta de sombra
      // sem antes descobrir por que ela não aparecia.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 300,
              child: PageView(
                children: const [
                  ChartCard(title: 'A', child: SizedBox()),
                  ChartCard(title: 'B', child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ClipRect), findsWidgets);
    });

    testWidgets('a decoração continua sendo a do gradiente', (tester) async {
      // O primeiro `Container` do card é o que os testes de paleta leem para
      // conferir o gradiente: embrulhar o card num `Container` novo devolveria
      // a decoração errada para eles.
      await _pump(tester);
      expect(
        (_decoracao(tester).gradient! as LinearGradient).colors,
        ChartPalette.azul.gradient,
      );
    });
  });
}
