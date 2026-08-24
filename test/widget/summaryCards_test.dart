import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/widget/chartCard.dart';
import 'package:iter/widget/summaryCards.dart';

/// Altura real do carrossel de cima. Testar em altura solta esconde justo o
/// erro que interessa: a legenda de cinco status quebra em duas linhas e o
/// card estoura.
// A altura que a tela usa hoje. Subiu de 290 para 312 quando o eyebrow
// entrou: ele custa 22px, tirados do `Expanded` do gráfico.
const _carouselHeight = 312.0;

PeriodSummary _summary({
  double total = 1000,
  int count = 6,
  // Segue `total` quando não informado: sem isso, `_summary(total: 0)` sairia
  // com dinheiro de rota e zero rotas, que é justo o descasamento em teste.
  double? routeTotal,
  int packages = 100,
  int failures = 4,
  double pending = 245,
  double received = 155,
  double upcoming = 600,
  double noRoute = 0,
  int pendingCount = 2,
  int receivedCount = 1,
  int scheduledCount = 2,
  int runningCount = 1,
  int noRouteCount = 0,
}) => PeriodSummary(
  total: total,
  count: count,
  routeTotal: routeTotal ?? total,
  packages: packages,
  failures: failures,
  pending: pending,
  received: received,
  upcoming: upcoming,
  noRoute: noRoute,
  pendingCount: pendingCount,
  receivedCount: receivedCount,
  scheduledCount: scheduledCount,
  runningCount: runningCount,
  noRouteCount: noRouteCount,
);

/// As cinco fatias de status — o pior caso de legenda.
///
/// A quinta **só existe com dinheiro dentro**: `MoneyBreakdownCard` descarta
/// fatia de valor zero, então um teste que apenas acrescentasse o status novo ao
/// enum continuaria desenhando quatro chips e continuaria verde, deixando o
/// layout que pode estourar sem cobertura nenhuma.
const _fiveSlices = [
  ShareSlice(label: 'Agendado', value: 400, color: Color(0xFF90CAF9)),
  ShareSlice(label: 'Em rota', value: 200, color: Color(0xFFFFCC80)),
  ShareSlice(label: 'Concluído', value: 245, color: Color(0xFFCE93D8)),
  ShareSlice(label: 'Pago', value: 155, color: Color(0xFF69F0AE)),
  ShareSlice(label: 'Sem Rota', value: 100, color: Color(0xFFB9F6CA)),
];

Future<void> _pump(WidgetTester tester, Widget card) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SizedBox(height: _carouselHeight, child: card)),
  ),
);

void main() {
  testWidgets('resumo cabe na altura com as cinco fatias e a taxa', (
    tester,
  ) async {
    await _pump(
      tester,
      MoneyBreakdownCard(
        title: 'Resumo do período',
        // A guarda tem de montar o card que o app desenha: em produção as 15
        // páginas passaram a ter eyebrow, e ele come altura justamente da área
        // do gráfico. Sem esta linha a guarda mede uma folga que não existe.
        eyebrow: 'Todos os status do período',
        slices: _fiveSlices,
        total: 1100,
        emptyNote: 'Sem rotas no período.',
        stats: const [
          ChartStat('TOTAL', 'R\$ 1.100,00'),
          ChartStat('ROTAS', '6'),
          ChartStat('MÉDIA/ROTA', 'R\$ 166,67'),
        ],
        extra: DeliveryRateBar(summary: _summary(noRoute: 100, noRouteCount: 1)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('RESUMO DO PERÍODO'), findsOneWidget);
    expect(find.text('Agendado (36%)'), findsOneWidget);
    expect(find.text('Pago (14%)'), findsOneWidget);
    expect(find.text('Sem Rota (9%)'), findsOneWidget);
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
          slices: _fiveSlices,
          total: 1100,
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

    testWidgets('só idas ao CD não é "sem rotas" nem "preencha pacotes"', (
      tester,
    ) async {
      // O período tem dinheiro na barra logo acima: "Sem rotas no período"
      // pareceria defeito, e mandar preencher "Pacotes" seria pedir o
      // impossível — a ida não carregou nenhum.
      await _pump(
        tester,
        MoneyBreakdownCard(
          title: 'Resumo',
          slices: const [
            ShareSlice(label: 'Sem Rota', value: 140, color: Color(0xFFB9F6CA)),
          ],
          total: 140,
          emptyNote: 'vazio',
          stats: const [],
          extra: DeliveryRateBar(
            summary: _summary(
              total: 140,
              count: 0,
              packages: 0,
              failures: 0,
              pending: 0,
              received: 0,
              upcoming: 0,
              noRoute: 140,
              pendingCount: 0,
              receivedCount: 0,
              scheduledCount: 0,
              runningCount: 0,
              noRouteCount: 2,
            ),
          ),
        ),
      );

      expect(find.text('Só idas sem rota no período.'), findsOneWidget);
      expect(find.text('Sem rotas no período.'), findsNothing);
    });
  });
}
