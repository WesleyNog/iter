import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/widget/chartCard.dart';
import 'package:iter/widget/failureRateCard.dart';

FailureRateRow _row(
  String axis, {
  String? label,
  double failures = 0,
  double packages = 0,
}) => FailureRateRow(
  axis: axis,
  leader: label == null
      ? null
      : FailureRate(label: label, failures: failures, packages: packages),
  emptyNote: 'Sem dado de $axis.',
);

Future<void> _pump(
  WidgetTester tester, {
  required List<FailureRateRow> rows,
  double? overall,
}) {
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Altura do carrossel de insucessos, para o card ser testado no
        // espaço real que ele tem.
        body: SizedBox(
          height: 340,
          child: FailureRateCard(
            rows: rows,
            overall: overall,
            // Em produção todas as páginas têm eyebrow, e ele come altura da
            // área do gráfico: sem ele a guarda mede uma folga inexistente.
            eyebrow: 'Rotas concluídas e pagas',
          ),
        ),
      ),
    ),
  );
}

List<double> _fractions(WidgetTester tester) => tester
    .widgetList<ChartProgressBar>(find.byType(ChartProgressBar))
    .map((bar) => bar.fraction)
    .toList();

void main() {
  testWidgets('mostra o pior de cada eixo com a conta ao lado', (tester) async {
    await _pump(
      tester,
      overall: 6.25,
      rows: [
        _row('Empresa', label: 'Mercado Livre', failures: 3, packages: 48),
        _row('Bairro', label: 'Aeroporto', failures: 2, packages: 24),
        _row('Clima', label: 'Chuva', failures: 1, packages: 8),
      ],
    );

    expect(find.text('Empresa · Mercado Livre'), findsOneWidget);
    expect(find.text('Bairro · Aeroporto'), findsOneWidget);
    expect(find.text('Clima · Chuva'), findsOneWidget);

    // Duas vezes: o GERAL do topo e a linha da empresa, que aqui coincidem
    // porque a única empresa é o período inteiro.
    expect(find.text('6.3%'), findsNWidgets(2));
    expect(find.text('8.3%'), findsOneWidget); // bairro
    expect(find.text('12.5%'), findsOneWidget); // clima
    expect(find.text('(1 de 8)'), findsOneWidget);
  });

  testWidgets('a barra é relativa ao pior índice, não a 0–100', (tester) async {
    await _pump(
      tester,
      overall: 5,
      rows: [
        _row('Empresa', label: 'Amazon', failures: 5, packages: 100), // 5%
        _row('Bairro', label: 'Centro', failures: 10, packages: 100), // 10%
        _row('Clima', label: 'Sol', failures: 0, packages: 100), // 0%
      ],
    );

    // O pior enche a barra; os outros ficam proporcionais a ele. Numa régua de
    // 0 a 100 as três seriam faixas quase vazias e indistinguíveis.
    expect(_fractions(tester), [0.5, 1.0, 0.0]);
  });

  testWidgets('sem insucesso nenhum, nenhuma barra enche', (tester) async {
    await _pump(
      tester,
      overall: 0,
      rows: [
        _row('Empresa', label: 'Amazon', failures: 0, packages: 100),
        _row('Bairro', label: 'Centro', failures: 0, packages: 50),
        _row('Clima', label: 'Sol', failures: 0, packages: 50),
      ],
    );

    // Zero dividido pelo pior (também zero) não pode virar barra cheia.
    expect(_fractions(tester), [0.0, 0.0, 0.0]);
  });

  testWidgets('eixo sem dado explica o motivo em vez de mostrar 0%', (
    tester,
  ) async {
    await _pump(
      tester,
      overall: 6.25,
      rows: [
        _row('Empresa', label: 'Mercado Livre', failures: 3, packages: 48),
        _row('Bairro'),
        _row('Clima'),
      ],
    );

    expect(find.text('Sem dado de Bairro.'), findsOneWidget);
    expect(find.text('Sem dado de Clima.'), findsOneWidget);
    // Só o eixo com dado desenha barra.
    expect(_fractions(tester), hasLength(1));
  });

  testWidgets('sem pacotes no período, o GERAL vira travessão', (tester) async {
    await _pump(tester, overall: null, rows: [_row('Empresa')]);

    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('número rateado do bairro não vira dízima na tela', (
    tester,
  ) async {
    await _pump(
      tester,
      overall: 10,
      rows: [_row('Bairro', label: 'Centro', failures: 1.5, packages: 16)],
    );

    // Bairro cai em quebrado por causa do rateio; empresa e clima são inteiros.
    expect(find.text('(1.5 de 16)'), findsOneWidget);
  });
}
