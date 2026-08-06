import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/companySummary.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/companySummaryCard.dart';

CompanySummary _summary({
  int routes = 12,
  double value = 1510,
  double profit = 1446.24,
  double uncalculatedValue = 0,
  int failures = 12,
  double? km = 428.5,
  int? packages = 512,
  int? stops = 390,
  double? failureRate = 2.34,
  double? costPerKm = 0.8193333,
  String? topBairro = 'Aldeota',
  String? bottomBairro = 'Messejana',
}) {
  return CompanySummary(
    routes: routes,
    value: value,
    profit: profit,
    uncalculatedValue: uncalculatedValue,
    failures: failures,
    km: km,
    packages: packages,
    stops: stops,
    failureRate: failureRate,
    costPerKm: costPerKm,
    topBairro: topBairro,
    bottomBairro: bottomBairro,
  );
}

Future<void> _pump(
  WidgetTester tester,
  CompanySummary summary, {
  Company? company = Company.mercadolivre,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CompanySummaryCard(summary: summary, company: company),
        ),
      ),
    ),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('mostra empresa, contagem, valor e lucro', (tester) async {
    await _pump(tester, _summary());

    expect(_text(tester, 'summary-title'), 'MERCADO LIVRE');
    expect(_text(tester, 'summary-routes'), '12 rotas');
    expect(_text(tester, 'summary-value'), 'R\$ 1.510,00');
    expect(_text(tester, 'summary-profit'), 'R\$ 1.446,24');
  });

  testWidgets('uma rota não vira "1 rotas"', (tester) async {
    await _pump(tester, _summary(routes: 1));

    expect(_text(tester, 'summary-routes'), '1 rota');
  });

  testWidgets('mostra KM, pacotes, paradas e insucessos com a taxa', (
    tester,
  ) async {
    await _pump(tester, _summary());

    expect(_text(tester, 'summary-km'), '428,5 km');
    expect(_text(tester, 'summary-packages'), '512');
    expect(_text(tester, 'summary-stops'), '390');
    // A quantidade sozinha não compara entre empresas.
    expect(_text(tester, 'summary-failures'), '12 (2,3%)');
    expect(_text(tester, 'summary-cost'), 'R\$ 0,8193');
  });

  testWidgets('números grandes ganham separador de milhar', (tester) async {
    await _pump(tester, _summary(km: 1284.5, packages: 1412, stops: 980));

    expect(_text(tester, 'summary-km'), '1.284,5 km');
    expect(_text(tester, 'summary-packages'), '1.412');
    expect(_text(tester, 'summary-stops'), '980');
  });

  group('a ressalva do lucro misto', () {
    testWidgets('aparece quando há rota sem custo calculado', (tester) async {
      await _pump(tester, _summary(uncalculatedValue: 812.50));

      expect(
        _text(tester, 'summary-uncalculated'),
        'R\$ 812,50 ainda sem custo calculado',
      );
    });

    testWidgets('some quando todas têm custo — e o silêncio é o sinal', (
      tester,
    ) async {
      await _pump(tester, _summary(uncalculatedValue: 0));

      expect(find.byKey(const Key('summary-uncalculated')), findsNothing);
    });
  });

  group('métricas incalculáveis', () {
    testWidgets('mostram — e nunca 0', (tester) async {
      await _pump(
        tester,
        _summary(km: null, packages: null, stops: null, costPerKm: null),
      );

      expect(_text(tester, 'summary-km'), '—');
      expect(_text(tester, 'summary-packages'), '—');
      expect(_text(tester, 'summary-stops'), '—');
      expect(_text(tester, 'summary-cost'), '—');
    });

    testWidgets('sem taxa, o insucesso aparece só como quantidade', (
      tester,
    ) async {
      await _pump(tester, _summary(failures: 3, failureRate: null));

      expect(_text(tester, 'summary-failures'), '3');
    });

    testWidgets('zero insucesso é 0, não —', (tester) async {
      // "Não teve insucesso" é um fato; `—` sugeriria que ninguém preencheu.
      await _pump(tester, _summary(failures: 0, failureRate: 0));

      expect(_text(tester, 'summary-failures'), '0 (0,0%)');
    });
  });

  group('bairros', () {
    testWidgets('mostra mais e menos rodado', (tester) async {
      await _pump(tester, _summary());

      expect(_text(tester, 'summary-top'), 'Aldeota');
      expect(_text(tester, 'summary-bottom'), 'Messejana');
    });

    testWidgets('bairro único não aparece como mais E menos rodado', (
      tester,
    ) async {
      // O mesmo nome em duas linhas com rótulos opostos parece defeito.
      await _pump(
        tester,
        _summary(topBairro: 'Aldeota', bottomBairro: 'Aldeota'),
      );

      expect(_text(tester, 'summary-top'), 'Aldeota');
      expect(find.byKey(const Key('summary-bottom')), findsNothing);
    });

    testWidgets('sem bairro nenhum, a seção some inteira', (tester) async {
      await _pump(tester, _summary(topBairro: null, bottomBairro: null));

      expect(find.byKey(const Key('summary-top')), findsNothing);
      expect(find.byKey(const Key('summary-bottom')), findsNothing);
    });
  });

  group('empresa sem rota no período', () {
    testWidgets('o card continua na tela, com o rótulo', (tester) async {
      await _pump(
        tester,
        const CompanySummary(
          routes: 0,
          value: 0,
          profit: 0,
          uncalculatedValue: 0,
          failures: 0,
        ),
        company: Company.shopee,
      );

      // Card que some e volta faz a posição dos outros dançar entre um mês e
      // outro.
      expect(_text(tester, 'summary-title'), 'SHOPEE');
      expect(find.byKey(const Key('summary-empty')), findsOneWidget);
      expect(find.byKey(const Key('summary-value')), findsNothing);
    });
  });

  group('card de total geral', () {
    testWidgets('sem empresa, usa o rótulo de total e não mostra logo', (
      tester,
    ) async {
      await _pump(tester, _summary(), company: null);

      expect(_text(tester, 'summary-title'), 'Total do período');
      expect(find.byType(Image), findsNothing);
      // Os números ficam nas mesmas posições do card de empresa.
      expect(_text(tester, 'summary-value'), 'R\$ 1.510,00');
      expect(_text(tester, 'summary-km'), '428,5 km');
    });
  });
}
