import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/companyFilter.dart';

/// Bombeia o filtro com [selected] marcado e devolve o que o toque em [key]
/// emitiu.
///
/// O widget não alterna nada — quem alterna é a tela, com
/// `RouteFilter.toggleCompany` —, então o que se verifica aqui é sempre "qual
/// empresa ele avisou", nunca "qual conjunto sobrou".
Future<Company?> tapSegment(
  WidgetTester tester,
  String key, {
  Set<Company> selected = const {},
}) async {
  Company? touched;
  var called = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CompanyFilter(
          selected: selected,
          onToggle: (company) {
            touched = company;
            called = true;
          },
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(ValueKey('filtro-$key')));
  await tester.pump();

  expect(called, isTrue, reason: 'onToggle não foi chamado para "$key"');
  return touched;
}

Future<void> pumpFilter(WidgetTester tester, Set<Company> selected) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CompanyFilter(selected: selected, onToggle: (_) {}),
      ),
    ),
  );
}

/// A opacidade de cada segmento, na ordem em que eles estão na árvore.
///
/// O trilho desenha um `Opacity` por segmento e nenhum fora deles, então
/// contar os que estão em 1 é contar os logos acesos.
List<double> opacities(WidgetTester tester) => tester
    .widgetList<Opacity>(find.byType(Opacity))
    .map((widget) => widget.opacity)
    .toList();

void main() {
  testWidgets('mostra um segmento por empresa e nenhum de "todas"', (
    tester,
  ) async {
    await pumpFilter(tester, const {});

    for (final company in Company.values) {
      expect(find.byKey(ValueKey('filtro-${company.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('filtro-todas')), findsNothing);
    expect(opacities(tester).length, Company.values.length);
  });

  testWidgets('tocar num desmarcado avisa aquela empresa', (tester) async {
    expect(await tapSegment(tester, 'mercadolivre'), Company.mercadolivre);
    expect(await tapSegment(tester, 'amazon'), Company.amazon);
    expect(await tapSegment(tester, 'shopee'), Company.shopee);
  });

  testWidgets('tocar num já marcado avisa a mesma empresa', (tester) async {
    // O toque no marcado e no desmarcado emitem a mesma coisa de propósito:
    // este widget só reporta onde o dedo caiu. Se ele também decidisse marcar
    // ou desmarcar, a regra do "vazio ou completo" existiria em dois lugares.
    expect(
      await tapSegment(
        tester,
        'amazon',
        selected: const {Company.amazon, Company.shopee},
      ),
      Company.amazon,
    );
  });

  testWidgets('conjunto vazio deixa os três apagados', (tester) async {
    await pumpFilter(tester, const {});

    expect(opacities(tester).where((value) => value == 1), isEmpty);
  });

  testWidgets('conjunto com duas deixa exatamente duas acesas', (tester) async {
    await pumpFilter(tester, const {Company.amazon, Company.shopee});

    expect(opacities(tester).where((value) => value == 1).length, 2);
  });

  testWidgets('conjunto com as três deixa as três acesas', (tester) async {
    // "Todas marcadas" e "nenhuma marcada" filtram igual, mas não se parecem
    // na tela: aqui o usuário chegou marcando uma a uma e vê as três acesas.
    await pumpFilter(tester, Company.values.toSet());

    expect(
      opacities(tester).where((value) => value == 1).length,
      Company.values.length,
    );
  });
}
