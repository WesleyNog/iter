import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/companyFilter.dart';

Future<Company?> tapSegment(WidgetTester tester, String key) async {
  Company? chosen;
  var called = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CompanyFilter(
          selected: null,
          onChanged: (company) {
            chosen = company;
            called = true;
          },
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(ValueKey('filtro-$key')));
  await tester.pump();

  expect(called, isTrue, reason: 'onChanged não foi chamado para "$key"');
  return chosen;
}

void main() {
  testWidgets('mostra um segmento para todas mais um por empresa', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyFilter(selected: null, onChanged: (_) {}),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('filtro-todas')), findsOneWidget);
    for (final company in Company.values) {
      expect(find.byKey(ValueKey('filtro-${company.name}')), findsOneWidget);
    }
  });

  testWidgets('avisa qual empresa foi escolhida', (tester) async {
    expect(await tapSegment(tester, 'mercadolivre'), Company.mercadolivre);
    expect(await tapSegment(tester, 'amazon'), Company.amazon);
    expect(await tapSegment(tester, 'shopee'), Company.shopee);
  });

  testWidgets('o segmento de todas devolve null', (tester) async {
    expect(await tapSegment(tester, 'todas'), isNull);
  });

  testWidgets('só o segmento selecionado fica sem transparência', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyFilter(selected: Company.amazon, onChanged: (_) {}),
        ),
      ),
    );

    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((widget) => widget.opacity)
        .toList();

    expect(opacities.where((value) => value == 1).length, 1);
    expect(opacities.length, Company.values.length + 1);
  });
}
