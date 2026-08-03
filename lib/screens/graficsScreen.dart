import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/barRankChart.dart';
import 'package:iter/widget/chartCard.dart';
import 'package:iter/widget/chartCarousel.dart';
import 'package:iter/widget/lineChartCard.dart';
import 'package:iter/widget/periodFilter.dart';
import 'package:iter/widget/summaryCards.dart';

/// Painel de gráficos das rotas do período.
///
/// Nenhuma conta mora aqui: tudo vem de `Utils/routeStats.dart`, e esta tela só
/// escolhe o período, formata e compõe os cards.
class GraficsScreen extends StatefulWidget {
  const GraficsScreen({super.key, required this.user});

  final User user;

  @override
  State<GraficsScreen> createState() => _GraficsScreenState();
}

class _GraficsScreenState extends State<GraficsScreen> {
  /// Criado uma única vez: montar o stream dentro do build reinscreveria no
  /// Firestore a cada rebuild. É o mesmo stream que a lista já lê, então
  /// gráfico e lista nunca discordam.
  late final Stream<List<NewRouteModal>> _routes = RouteController.watchAll(
    widget.user.uid,
  );

  late DateTime _start;
  late DateTime _end;
  Shift _shift = Shift.manha;

  @override
  void initState() {
    super.initState();
    final period = PeriodFilter.currentMonth();
    _start = period.start;
    _end = period.end;
  }

  /// Respiro do fim da tela. A `GlassNavBar` flutua por cima do conteúdo
  /// (`extendBody: true` na Home), e é o próprio `Scaffold` quem informa quanto
  /// ela ocupa — assim nenhum número da barra fica duplicado aqui.
  double get _bottomGap => 24 + MediaQuery.paddingOf(context).bottom;

  String _money(double value) => CurrencyFormatterHelper.formatMoney(value);

  /// Eixo vertical do gráfico de linha: tem 56px para caber.
  String _axisMoney(double value) => value >= 1000
      ? '${(value / 1000).toStringAsFixed(1)}k'
      : value.toStringAsFixed(0);

  String _whole(double value) => value.toStringAsFixed(0);

  String _oneDecimal(double value) => value.toStringAsFixed(1);

  String _percent(double value) => '${value.toStringAsFixed(1)}%';

  double _sum(List<RankEntry> entries) =>
      entries.fold(0, (total, entry) => total + entry.value);

  /// Ranking vazio é rotina agora que o período sem rota também desenha os
  /// cards — `entries.first` estouraria.
  String _highest(List<RankEntry> entries, String Function(double) format) =>
      entries.isEmpty ? '—' : format(entries.first.value);

  String _lowest(List<RankEntry> entries, String Function(double) format) =>
      entries.isEmpty ? '—' : format(entries.last.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          // Fora do StreamBuilder: o filtro continua visível carregando, vazio
          // ou em erro — senão o usuário fica sem como sair de um período seco.
          child: PeriodFilter(
            start: _start,
            end: _end,
            onChanged: (start, end) => setState(() {
              _start = start;
              _end = end;
            }),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    return StreamBuilder<List<NewRouteModal>>(
      stream: _routes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Erro ao ler as rotas: ${snapshot.error}');
          return _message(
            icon: Icons.error_outline,
            title: 'Não foi possível carregar seus gráficos.',
            subtitle: kDebugMode ? '${snapshot.error}' : 'Tente novamente.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snapshot.data ?? const <NewRouteModal>[];
        if (all.isEmpty) {
          return _message(
            icon: Icons.bar_chart_outlined,
            title: 'Nenhuma rota cadastrada ainda.',
            subtitle: 'Use o botão + para cadastrar a primeira.',
          );
        }

        // Período sem rota nenhuma continua desenhando os cards, cada um com
        // seu próprio vazio: tela em branco não deixa claro que o problema é o
        // período, e some com o formato da tela a cada troca de data.
        return _dashboard(inPeriod(all, start: _start, end: _end));
      },
    );
  }

  /// [routes] chega com **todos** os status do período.
  ///
  /// Os cards de dinheiro do topo usam o período inteiro — é lá que o
  /// agendado importa, para responder "já bati minha meta ou pego mais uma
  /// rota?". Os gráficos de análise usam só o que rodou: bairro percorrido e
  /// índice de insucesso de rota que ainda não saiu não existem.
  ///
  /// Por isso o TOTAL dos dois blocos difere de propósito, e o rótulo entre
  /// eles diz qual recorte está valendo.
  Widget _dashboard(List<NewRouteModal> routes) {
    final periodSummary = summarize(routes);
    final done = realized(routes);
    final doneSummary = summarize(done);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, _bottomGap),
      child: Column(
        children: [
          ChartCarousel(height: 290, pages: _moneyPages(periodSummary, routes)),
          const SizedBox(height: 24),
          _sectionLabel('Análise das rotas concluídas e pagas'),
          const SizedBox(height: 10),
          ChartCarousel(height: 340, pages: _companyPages(doneSummary, done)),
          const SizedBox(height: 20),
          ChartCarousel(height: 340, pages: _bairroPages(done)),
          const SizedBox(height: 20),
          ChartCarousel(height: 330, pages: _timePages(done)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Row(
      children: [
        Icon(Icons.insights_outlined, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  // --- Dinheiro do período ------------------------------------------------

  List<ShareSlice> _companySlices(List<NewRouteModal> routes) => [
    for (final entry in valueByCompany(routes))
      ShareSlice(
        label: companyLabel(entry.company),
        value: entry.value,
        color: companyColor(entry.company),
      ),
  ];

  String _average(double total, int count) =>
      _money(count == 0 ? 0 : total / count);

  List<Widget> _moneyPages(
    PeriodSummary summary,
    List<NewRouteModal> routes,
  ) {
    return [
      MoneyBreakdownCard(
        title: 'Resumo do período',
        // A barra aqui é por status, e não por empresa: ela é o índice das
        // outras três páginas — mostra para onde foi cada real do período.
        slices: [
          for (final entry in valueByStatus(routes))
            ShareSlice(
              label: statusLabel(entry.status),
              value: entry.value,
              color: statusChartColor(entry.status),
            ),
        ],
        total: summary.total,
        emptyNote: 'Sem rotas no período.',
        stats: [
          ChartStat('TOTAL', _money(summary.total)),
          ChartStat('ROTAS', '${summary.count}'),
          ChartStat('MÉDIA/ROTA', _average(summary.total, summary.count)),
        ],
        extra: DeliveryRateBar(summary: summary),
      ),
      MoneyBreakdownCard(
        title: 'Pago no período',
        slices: _companySlices(receivedPayment(routes)),
        total: summary.received,
        emptyNote: 'Nada foi pago neste período ainda.',
        stats: [
          ChartStat('PAGO', _money(summary.received)),
          ChartStat('ROTAS', '${summary.receivedCount}'),
          ChartStat(
            'MÉDIA/ROTA',
            _average(summary.received, summary.receivedCount),
          ),
        ],
      ),
      MoneyBreakdownCard(
        title: 'A receber no período',
        slices: _companySlices(pendingPayment(routes)),
        total: summary.pending,
        emptyNote: 'Nada a receber: tudo que rodou já foi pago.',
        footnote: 'Rota concluída e ainda não paga.',
        stats: [
          ChartStat('A RECEBER', _money(summary.pending)),
          ChartStat('ROTAS', '${summary.pendingCount}'),
          ChartStat(
            'MÉDIA/ROTA',
            _average(summary.pending, summary.pendingCount),
          ),
        ],
      ),
      MoneyBreakdownCard(
        title: 'Pendentes no período',
        slices: _companySlices(notRunYet(routes)),
        total: summary.upcoming,
        emptyNote: 'Nenhuma rota marcada para o período.',
        footnote: 'Estimativa: rota que ainda não rodou pode mudar.',
        stats: [
          ChartStat('ESTIMADO', _money(summary.upcoming)),
          ChartStat('AGENDADAS', '${summary.scheduledCount}'),
          ChartStat('EM ROTA', '${summary.runningCount}'),
        ],
      ),
    ];
  }

  // --- Empresas -----------------------------------------------------------

  List<Widget> _companyPages(
    PeriodSummary summary,
    List<NewRouteModal> routes,
  ) {
    final byValue = valuePerCompany(routes);
    final byCount = countPerCompany(routes);
    final failures = failuresPerCompany(routes);
    final rates = failureRatePerCompany(routes);
    final totalFailures = _sum(failures);
    final overallRate = summary.packages == 0
        ? null
        : summary.failures / summary.packages * 100;

    return [
      BarRankChart(
        title: 'Empresas por valor',
        entries: byValue,
        formatValue: _money,
        emptyMessage: 'Nenhuma rota no período.',
        stats: [
          ChartStat('TOTAL', _money(summary.total)),
          ChartStat('MAIOR', _highest(byValue, _money)),
          ChartStat('MENOR', _lowest(byValue, _money)),
        ],
      ),
      BarRankChart(
        title: 'Empresas por rotas',
        entries: byCount,
        formatValue: _whole,
        emptyMessage: 'Nenhuma rota no período.',
        stats: [
          ChartStat('TOTAL', '${summary.count}'),
          ChartStat('MAIOR', _highest(byCount, _whole)),
          ChartStat('MENOR', _lowest(byCount, _whole)),
        ],
      ),
      BarRankChart(
        title: 'Insucessos por empresa',
        entries: failures,
        formatValue: _whole,
        emptyMessage: 'Nenhuma rota no período.',
        stats: [
          ChartStat('TOTAL', _whole(totalFailures)),
          ChartStat('MAIOR', _highest(failures, _whole)),
          ChartStat('MENOR', _lowest(failures, _whole)),
        ],
      ),
      BarRankChart(
        title: 'Índice de insucesso',
        entries: rates,
        formatValue: _percent,
        // Os valores já são taxas: participação no total não diria nada.
        showShare: false,
        footnote: 'Considera só rotas com os pacotes informados.',
        emptyMessage:
            'Nenhuma rota do período informou a quantidade de pacotes.\n'
            'Sem pacotes não há como calcular o índice.',
        stats: [
          ChartStat('GERAL', overallRate == null ? '—' : _percent(overallRate)),
          ChartStat('MAIOR', _highest(rates, _percent)),
          ChartStat('MENOR', _lowest(rates, _percent)),
        ],
      ),
    ];
  }

  // --- Bairros ------------------------------------------------------------

  List<Widget> _bairroPages(List<NewRouteModal> routes) {
    final rodados = routesPerBairro(routes);
    final failures = failuresPerBairro(routes);

    return [
      BarRankChart(
        title: 'Bairros mais rodados',
        entries: rodados,
        formatValue: _whole,
        emptyMessage:
            'Nenhuma rota do período informou bairro.\n'
            'Escolha os bairros ao cadastrar a rota.',
        stats: [
          ChartStat('BAIRROS', '${rodados.length}'),
          ChartStat('PASSAGENS', _whole(_sum(rodados))),
          ChartStat('MAIOR', _highest(rodados, _whole)),
        ],
      ),
      BarRankChart(
        title: 'Bairros com insucesso',
        entries: failures,
        formatValue: _oneDecimal,
        footnote: 'Insucesso rateado entre os bairros de cada rota.',
        emptyMessage: 'Nenhum insucesso com bairro informado no período.',
        stats: [
          ChartStat('BAIRROS', '${failures.length}'),
          ChartStat('TOTAL', _oneDecimal(_sum(failures))),
          ChartStat('MAIOR', _highest(failures, _oneDecimal)),
        ],
      ),
    ];
  }

  // --- Tempo --------------------------------------------------------------

  List<Widget> _timePages(List<NewRouteModal> routes) {
    final weekdays = valuePerWeekday(routes);
    final hours = valuePerHour(routes, _shift);
    final hourValues = [for (final point in hours) point.value];

    return [
      LineChartCard(
        title: 'Por dia da semana',
        values: weekdays,
        firstX: 0,
        labelOf: (x) => weekdayLabel(x + 1),
        tooltipLabelOf: (x) => weekdayFullLabel(x + 1),
        formatValue: _money,
        formatAxis: _axisMoney,
        emptyMessage: 'Nenhuma rota no período.',
        stats: _seriesStats(weekdays),
      ),
      LineChartCard(
        title: 'Faixa horária',
        values: hourValues,
        firstX: _shift.startHour,
        labelOf: (x) => '${x.toString().padLeft(2, '0')}h',
        tooltipLabelOf: (x) => 'Início às ${x.toString().padLeft(2, '0')}h',
        formatValue: _money,
        formatAxis: _axisMoney,
        emptyMessage: 'Nenhuma rota começou neste turno.',
        lineColors: const [Color(0xFFFFAB91), Color(0xFFFF7043)],
        trailing: _shiftPicker(),
        stats: _seriesStats(hourValues),
      ),
    ];
  }

  List<ChartStat> _seriesStats(List<double> values) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final highest = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a > b ? a : b);

    return [
      ChartStat('TOTAL', _money(total)),
      ChartStat('MAIOR', _money(highest)),
      ChartStat('MÉDIA', _money(values.isEmpty ? 0 : total / values.length)),
    ];
  }

  Widget _shiftPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButton<Shift>(
        value: _shift,
        dropdownColor: const Color(0xFF1976D2),
        underline: const SizedBox.shrink(),
        isDense: true,
        borderRadius: BorderRadius.circular(12),
        iconEnabledColor: Colors.white,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        items: [
          for (final shift in Shift.values)
            DropdownMenuItem(value: shift, child: Text(shift.label)),
        ],
        onChanged: (shift) {
          if (shift != null) setState(() => _shift = shift);
        },
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 0, 32, _bottomGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
