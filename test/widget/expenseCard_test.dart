import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/expenseSummary.dart';
import 'package:iter/widget/expenseCard.dart';

ExpenseSummary _summary({
  double fuel = 430.50,
  double maintenance = 0,
  int supplies = 2,
  int maintenances = 0,
  double? liters = 72.5,
  double? averagePricePerLiter = 5.9379,
}) {
  return ExpenseSummary(
    fuel: fuel,
    maintenance: maintenance,
    supplies: supplies,
    maintenances: maintenances,
    liters: liters,
    averagePricePerLiter: averagePricePerLiter,
  );
}

Future<void> _pump(
  WidgetTester tester,
  ExpenseSummary summary, {
  VoidCallback? onDetail,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExpenseCard(summary: summary, onDetail: onDetail),
        ),
      ),
    ),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('mostra abastecimento, manutenção e total', (tester) async {
    await _pump(tester, _summary());

    expect(_text(tester, 'expense-fuel'), 'R\$ 430,50');
    expect(_text(tester, 'expense-total'), 'R\$ 430,50');
  });

  testWidgets('sem manutenção no período mostra R\$ 0,00, não "em breve"', (
    tester,
  ) async {
    // Virou o contrário do que era: antes o app não sabia e dizia "em breve";
    // agora sabe, e zero é **afirmação** — não gastou com peça no período.
    await _pump(tester, _summary());

    expect(_text(tester, 'expense-maintenance'), 'R\$ 0,00');
    expect(find.text('em breve'), findsNothing);
  });

  testWidgets('com manutenção real, mostra o valor', (tester) async {
    await _pump(tester, _summary(maintenance: 200, maintenances: 1));

    expect(_text(tester, 'expense-maintenance'), 'R\$ 200,00');
    expect(_text(tester, 'expense-total'), 'R\$ 630,50');
  });

  testWidgets('a linha de contexto traz quantidade, litros e preço médio', (
    tester,
  ) async {
    await _pump(tester, _summary());

    expect(
      _text(tester, 'expense-meta'),
      '2 abastecimentos · 72,5 L · R\$ 5,9379/L',
    );
  });

  testWidgets('a contagem de manutenções entra na linha', (tester) async {
    await _pump(tester, _summary(maintenance: 2400, maintenances: 3));

    expect(
      _text(tester, 'expense-meta'),
      '2 abastecimentos · 3 manutenções · 72,5 L · R\$ 5,9379/L',
    );
  });

  testWidgets('singular e plural em português', (tester) async {
    await _pump(tester, _summary(supplies: 1, maintenance: 200, maintenances: 1));

    expect(
      _text(tester, 'expense-meta'),
      startsWith('1 abastecimento · 1 manutenção ·'),
    );
  });

  testWidgets('contagem zerada não vira ruído na linha', (tester) async {
    // "0 manutenções" não acrescenta nada: a linha do valor logo acima já diz
    // que foi zero.
    await _pump(tester, _summary());

    expect(_text(tester, 'expense-meta'), isNot(contains('manutenç')));
  });

  testWidgets('só manutenção no período não mostra "0 abastecimentos"', (
    tester,
  ) async {
    await _pump(
      tester,
      _summary(
        fuel: 0,
        supplies: 0,
        maintenance: 2400,
        maintenances: 1,
        liters: null,
        averagePricePerLiter: null,
      ),
    );

    expect(_text(tester, 'expense-meta'), '1 manutenção');
  });

  testWidgets('sem litros, a linha omite litros e preço médio', (tester) async {
    await _pump(
      tester,
      _summary(liters: null, averagePricePerLiter: null),
    );

    expect(_text(tester, 'expense-meta'), '2 abastecimentos');
  });

  group('o aviso que impede a subtração de cabeça', () {
    testWidgets('está sempre visível', (tester) async {
      // Ver "Lucro R$ 175,60" logo acima de "Gastos R$ 430,50" convida a
      // subtrair — e a conta estaria errada, porque o lucro já desconta a
      // provisão de combustível.
      await _pump(tester, _summary());

      expect(_text(tester, 'expense-note'), contains('não se somam'));
    });

    testWidgets('aparece até no período sem gasto nenhum', (tester) async {
      await _pump(tester, _summary(fuel: 0, supplies: 0, liters: null));

      expect(find.byKey(const Key('expense-note')), findsOneWidget);
    });
  });

  group('período sem gasto', () {
    testWidgets('mostra zero, e zero aqui é verdade', (tester) async {
      // Diferente das métricas de rota: não gastar nada é um resultado, não
      // "não dá para calcular".
      await _pump(
        tester,
        _summary(fuel: 0, supplies: 0, liters: null, averagePricePerLiter: null),
      );

      expect(_text(tester, 'expense-total'), 'R\$ 0,00');
    });

    testWidgets('esconde a linha de contexto', (tester) async {
      await _pump(
        tester,
        _summary(fuel: 0, supplies: 0, liters: null, averagePricePerLiter: null),
      );

      expect(find.byKey(const Key('expense-meta')), findsNothing);
    });
  });

  group('botão detalhar', () {
    testWidgets('aparece quando há o que detalhar', (tester) async {
      await _pump(tester, _summary(), onDetail: () {});

      expect(find.byKey(const Key('expense-detail')), findsOneWidget);
    });

    testWidgets('some quando não há', (tester) async {
      await _pump(tester, _summary());

      expect(find.byKey(const Key('expense-detail')), findsNothing);
    });

    testWidgets('o toque avisa quem montou o card', (tester) async {
      var toques = 0;
      await _pump(tester, _summary(), onDetail: () => toques++);

      await tester.tap(find.byKey(const Key('expense-detail')));
      await tester.pump();

      expect(toques, 1);
    });
  });
}
