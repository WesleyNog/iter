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
}
