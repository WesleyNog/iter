import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/accountMenu.dart';

Future<List<AccountAction>> _pump(
  WidgetTester tester, {
  bool busy = false,
}) async {
  final escolhidos = <AccountAction>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: Scaffold(
        appBar: AppBar(
          actions: [AccountMenu(busy: busy, onSelected: escolhidos.add)],
        ),
      ),
    ),
  );
  return escolhidos;
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-conta')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abre com Sair e Excluir conta, separados por uma divisória', (
    tester,
  ) async {
    await _pump(tester);
    await _abrir(tester);

    expect(find.text('Sair'), findsOneWidget);
    expect(find.text('Excluir conta'), findsOneWidget);
    // O que se desfaz no próximo login separado do que não se desfaz nunca.
    expect(find.byType(PopupMenuDivider), findsOneWidget);
  });

  testWidgets('cada item avisa a própria ação', (tester) async {
    final escolhidos = await _pump(tester);

    await _abrir(tester);
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    await _abrir(tester);
    await tester.tap(find.text('Excluir conta'));
    await tester.pumpAndSettle();

    expect(escolhidos, [AccountAction.signOut, AccountAction.delete]);
  });

  testWidgets('excluir conta leva a cor de erro do tema', (tester) async {
    await _pump(tester);
    await _abrir(tester);

    final contexto = tester.element(find.text('Excluir conta'));
    final erro = Theme.of(contexto).colorScheme.error;
    final texto = tester.widget<Text>(find.text('Excluir conta'));
    expect(texto.style?.color, erro);
  });

  testWidgets('o menu é branco de verdade, sem o tom lilás do tema', (
    tester,
  ) async {
    await _pump(tester);

    // A causa do cinza-lilás: o Material 3 tinge a superfície com a cor
    // primária do tema. Branco e sem tinta é o que casa com o vidro.
    final botao = tester.widget<PopupMenuButton<AccountAction>>(
      find.byKey(const ValueKey('menu-conta')),
    );
    expect(botao.color, Colors.white);
    expect(botao.surfaceTintColor, Colors.transparent);
    expect(botao.position, PopupMenuPosition.under);
  });

  testWidgets('saindo, o ícone vira progresso e o menu não abre', (
    tester,
  ) async {
    await _pump(tester, busy: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-conta')));
    await tester.pump();
    expect(find.text('Sair'), findsNothing);
  });
}
