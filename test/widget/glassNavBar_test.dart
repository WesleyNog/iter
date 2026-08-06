import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/glassNavBar.dart';

/// Fixa o contrato de que `graficsScreen` e `listIterScreen` dependem para o
/// respiro do fim do scroll: com `extendBody: true`, o `Scaffold` avisa ao body,
/// pelo `MediaQuery`, quanto a barra flutuante ocupa. Se isso deixar de valer, o
/// último card volta a nascer embaixo da barra — e este teste avisa antes.
void main() {
  testWidgets('com extendBody, o body recebe a altura da barra no MediaQuery', (
    tester,
  ) async {
    double? bottomInset;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: Builder(
            builder: (context) {
              bottomInset = MediaQuery.paddingOf(context).bottom;
              return const SizedBox.expand();
            },
          ),
          bottomNavigationBar: GlassNavBar(
            currentIndex: 0,
            onTap: (_) {},
            trailing: GlassCircleButton(icon: Icons.add, onTap: () {}),
            items: const [
              GlassNavItem(icon: Icons.bar_chart, label: 'Gráfico'),
              GlassNavItem(icon: Icons.receipt_long, label: 'Lista'),
            ],
          ),
        ),
      ),
    );

    expect(bottomInset, tester.getSize(find.byType(GlassNavBar)).height);
  });

  testWidgets('sem extendBody o body não sabe da barra — daí o corte', (
    tester,
  ) async {
    double? bottomInset;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              bottomInset = MediaQuery.paddingOf(context).bottom;
              return const SizedBox.expand();
            },
          ),
          bottomNavigationBar: GlassNavBar(
            currentIndex: 0,
            onTap: (_) {},
            items: const [
              GlassNavItem(icon: Icons.bar_chart, label: 'Gráfico'),
              GlassNavItem(icon: Icons.receipt_long, label: 'Lista'),
            ],
          ),
        ),
      ),
    );

    // A barra existe e ocupa espaço, mas o body não fica sabendo: era assim que
    // a Home estava, e por isso o conteúdo terminava rente à barra.
    expect(tester.getSize(find.byType(GlassNavBar)).height, greaterThan(0));
    expect(bottomInset, 0);
  });

  group('comportamento — o que o polimento não pode quebrar', () {
    const items = [
      GlassNavItem(icon: Icons.bar_chart, label: 'Gráfico'),
      GlassNavItem(icon: Icons.receipt_long, label: 'Lista'),
      GlassNavItem(icon: Icons.data_saver_off_rounded, label: 'Resumo'),
      GlassNavItem(icon: Icons.people, label: 'Amigos'),
    ];

    Future<void> pumpBar(
      WidgetTester tester, {
      int currentIndex = 0,
      ValueChanged<int>? onTap,
      int pendingCount = 0,
      int pendingIndex = -1,
      Widget? trailing,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            extendBody: true,
            body: const SizedBox.expand(),
            bottomNavigationBar: GlassNavBar(
              items: items,
              currentIndex: currentIndex,
              onTap: onTap ?? (_) {},
              pendingCount: pendingCount,
              pendingIndex: pendingIndex,
              trailing: trailing,
            ),
          ),
        ),
      );
    }

    testWidgets('desenha um ícone por item', (tester) async {
      await pumpBar(tester);

      for (final item in items) {
        expect(find.byIcon(item.icon), findsOneWidget);
      }
    });

    testWidgets('tocar em um item avisa o índice certo', (tester) async {
      final tapped = <int>[];
      await pumpBar(tester, onTap: tapped.add);

      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.tap(find.byIcon(Icons.people));
      await tester.pump();

      expect(tapped, [1, 3]);
    });

    testWidgets('tocar no item já selecionado também avisa', (tester) async {
      // Quem depende disso é a Home: um `setState` com o mesmo índice é inócuo,
      // mas engolir o toque faria a barra parecer travada.
      final tapped = <int>[];
      await pumpBar(tester, currentIndex: 2, onTap: tapped.add);

      await tester.tap(find.byIcon(Icons.data_saver_off_rounded));
      await tester.pump();

      expect(tapped, [2]);
    });

    testWidgets('tocar no vão entre dois ícones ainda troca de aba', (
      tester,
    ) async {
      // O ícone não preenche o slot; sem `HitTestBehavior.opaque` o toque na
      // borda do item cai no vazio. Verificado removendo o `opaque`: este
      // teste falha (`Expected: [0], Actual: []`). A primeira versão dele
      // tocava logo acima do ícone e passava dos dois jeitos — ponto de toque
      // mal escolhido faz o teste virar enfeite.
      final tapped = <int>[];
      await pumpBar(tester, onTap: tapped.add);

      final icon = tester.getRect(find.byIcon(Icons.bar_chart));
      // À direita do ícone, fora do glifo e ainda dentro do slot do item —
      // o slot tem ~180px de largura e o ícone só 26.
      await tester.tapAt(Offset(icon.right + 40, icon.center.dy));
      await tester.pump();

      expect(tapped, [0]);
    });

    testWidgets('o badge aparece no índice pedido e some com zero', (
      tester,
    ) async {
      await pumpBar(tester, pendingCount: 3, pendingIndex: 1);
      expect(find.text('3'), findsOneWidget);

      await pumpBar(tester, pendingCount: 0, pendingIndex: 1);
      expect(find.text('3'), findsNothing);
    });

    group('trailing', () {
      testWidgets('aparece quando informado', (tester) async {
        await pumpBar(
          tester,
          trailing: GlassCircleButton(icon: Icons.add, onTap: () {}),
        );

        expect(find.byType(GlassCircleButton), findsOneWidget);
      });

      testWidgets('o toque nele não troca de aba', (tester) async {
        // O "+" abre o menu de criar; se ele também navegasse, a Home mudaria
        // de aba por baixo do sheet.
        final tapped = <int>[];
        var plusTaps = 0;

        await pumpBar(
          tester,
          onTap: tapped.add,
          trailing: GlassCircleButton(
            icon: Icons.add,
            onTap: () => plusTaps++,
          ),
        );

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        expect(plusTaps, 1);
        expect(tapped, isEmpty);
      });
    });
  });
}
