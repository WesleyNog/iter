import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/widget/chartCard.dart';
import 'package:iter/widget/summaryCards.dart';

/// Altura real do carrossel de cima. Testar em altura solta esconde justo o
/// erro que interessa: a legenda de quatro status quebra em duas linhas e o
/// card estoura.
const _carouselHeight = 290.0;

PeriodSummary _summary({
  double total = 1000,
  int count = 6,
  int packages = 100,
  int failures = 4,
  double pending = 245,
  double received = 155,
  double upcoming = 600,
  int pendingCount = 2,
  int receivedCount = 1,
  int scheduledCount = 2,
  int runningCount = 1,
}) => PeriodSummary(
  total: total,
  count: count,
  packages: packages,
  failures: failures,
  pending: pending,
  received: received,
  upcoming: upcoming,
  pendingCount: pendingCount,
  receivedCount: receivedCount,
  scheduledCount: scheduledCount,
  runningCount: runningCount,
);

/// As quatro fatias de status — o pior caso de legenda.
const _fourSlices = [
  ShareSlice(label: 'Agendado', value: 400, color: Color(0xFF90CAF9)),
  ShareSlice(label: 'Em rota', value: 200, color: Color(0xFFFFCC80)),
  ShareSlice(label: 'Concluído', value: 245, color: Color(0xFFCE93D8)),
  ShareSlice(label: 'Pago', value: 155, color: Color(0xFF69F0AE)),
];

Future<void> _pump(WidgetTester tester, Widget card) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SizedBox(height: _carouselHeight, child: card)),
  ),
);

void main() {
  testWidgets('resumo cabe na altura com as quatro fatias e a taxa', (
    tester,
  ) async {
    await _pump(
      tester,
      MoneyBreakdownCard(
        title: 'Resumo do período',
        slices: _fourSlices,
        total: 1000,
        emptyNote: 'Sem rotas no período.',
        stats: const [
          ChartStat('TOTAL', 'R\$ 1.000,00'),
          ChartStat('ROTAS', '6'),
          ChartStat('MÉDIA/ROTA', 'R\$ 166,67'),
        ],
        extra: DeliveryRateBar(summary: _summary()),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('RESUMO DO PERÍODO'), findsOneWidget);
    expect(find.text('Agendado (40%)'), findsOneWidget);
    expect(find.text('Pago (16%)'), findsOneWidget);
    expect(find.text('96.0%'), findsOneWidget);
  });

  testWidgets('a porcentagem usa o total do card, não o do período', (
    tester,
  ) async {
    await _pump(
      tester,
      const MoneyBreakdownCard(
        title: 'A receber no período',
        slices: [
          ShareSlice(label: 'Shopee', value: 180, color: Color(0xFFFF8A80)),
          ShareSlice(label: 'Amazon', value: 60, color: Color(0xFF84FFFF)),
        ],
        // 240 é o total a receber; o período inteiro é bem maior.
        total: 240,
        emptyNote: 'Nada a receber.',
        footnote: 'Rota concluída e ainda não paga.',
        stats: [ChartStat('A RECEBER', 'R\$ 240,00')],
      ),
    );

    expect(find.text('Shopee (75%)'), findsOneWidget);
    expect(find.text('Amazon (25%)'), findsOneWidget);
    expect(find.text('Rota concluída e ainda não paga.'), findsOneWidget);
  });

  testWidgets('card zerado mostra a nota em vez da barra', (tester) async {
    await _pump(
      tester,
      const MoneyBreakdownCard(
        title: 'Pendentes no período',
        slices: [],
        total: 0,
        emptyNote: 'Nenhuma rota marcada para o período.',
        stats: [ChartStat('ESTIMADO', 'R\$ 0,00')],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Nenhuma rota marcada para o período.'), findsOneWidget);
  });

  testWidgets('fatia zerada não vira legenda nem pedaço de barra', (
    tester,
  ) async {
    await _pump(
      tester,
      const MoneyBreakdownCard(
        title: 'Pago no período',
        slices: [
          ShareSlice(label: 'Shopee', value: 100, color: Color(0xFFFF8A80)),
          ShareSlice(label: 'Amazon', value: 0, color: Color(0xFF84FFFF)),
        ],
        total: 100,
        emptyNote: 'Nada pago.',
        stats: [ChartStat('PAGO', 'R\$ 100,00')],
      ),
    );

    expect(find.text('Shopee (100%)'), findsOneWidget);
    expect(find.textContaining('Amazon'), findsNothing);
  });

  group('DeliveryRateBar', () {
    testWidgets('sem pacotes informados, explica em vez de mostrar 0%', (
      tester,
    ) async {
      await _pump(
        tester,
        MoneyBreakdownCard(
          title: 'Resumo',
          slices: _fourSlices,
          total: 1000,
          emptyNote: 'vazio',
          stats: const [],
          extra: DeliveryRateBar(
            summary: _summary(packages: 0, failures: 0),
          ),
        ),
      );

      expect(
        find.text('Preencha "Pacotes" na rota para acompanhar.'),
        findsOneWidget,
      );
    });

    testWidgets('sem rota nenhuma, diz que o período está vazio', (
      tester,
    ) async {
      await _pump(
        tester,
        MoneyBreakdownCard(
          title: 'Resumo',
          slices: const [],
          total: 0,
          emptyNote: 'Sem rotas no período.',
          stats: const [],
          extra: DeliveryRateBar(
            summary: _summary(
              total: 0,
              count: 0,
              packages: 0,
              failures: 0,
              pending: 0,
              received: 0,
              upcoming: 0,
              pendingCount: 0,
              receivedCount: 0,
              scheduledCount: 0,
              runningCount: 0,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Sem rotas no período.'), findsNWidgets(2));
    });
  });
}
