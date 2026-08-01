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

  /// `formatDoubleToMoney` devolve string vazia para zero — aqui zero é
  /// resultado legítimo e precisa aparecer.
  String _money(double value) => value == 0
      ? 'R\$ 0,00'
      : CurrencyFormatterHelper.formatDoubleToMoney(value);

  /// Eixo vertical do gráfico de linha: tem 56px para caber.
  String _axisMoney(double value) => value >= 1000
      ? '${(value / 1000).toStringAsFixed(1)}k'
      : value.toStringAsFixed(0);

  String _whole(double value) => value.toStringAsFixed(0);

  String _oneDecimal(double value) => value.toStringAsFixed(1);

  String _percent(double value) => '${value.toStringAsFixed(1)}%';

  double _sum(List<RankEntry> entries) =>
      entries.fold(0, (total, entry) => total + entry.value);

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

        final routes = realizedInPeriod(all, start: _start, end: _end);

        // Tem rota, só nenhuma realizada no período: mandar cadastrar a
        // primeira aqui seria mentira.
        if (routes.isEmpty) {
          return _message(
            icon: Icons.event_busy_outlined,
            title:
                'Nenhuma rota concluída entre '
                '${PeriodFilter.formatDate(_start)} e '
                '${PeriodFilter.formatDate(_end)}.',
            subtitle:
                'Troque o período acima. Rota agendada ou em andamento não '
                'entra na conta.',
          );
        }

        return _dashboard(routes);
      },
    );
  }

  Widget _dashboard(List<NewRouteModal> routes) {
    final summary = summarize(routes);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        children: [
          _summaryCard(summary, routes),
          const SizedBox(height: 20),
          ChartCarousel(height: 340, pages: _companyPages(summary, routes)),
          const SizedBox(height: 20),
          ChartCarousel(height: 340, pages: _bairroPages(routes)),
          const SizedBox(height: 20),
          ChartCarousel(height: 330, pages: _timePages(routes)),
        ],
      ),
    );
  }

  // --- Resumo -------------------------------------------------------------

  Widget _summaryCard(PeriodSummary summary, List<NewRouteModal> routes) {
    final byCompany = valueByCompany(routes);

    return ChartCard(
      title: 'Resumo do período',
      fillHeight: false,
      stats: [
        ChartStat('TOTAL', _money(summary.total)),
        ChartStat('ROTAS', '${summary.count}'),
        ChartStat('MÉDIA/ROTA', _money(summary.average)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shareBar(byCompany, summary.total),
          const SizedBox(height: 14),
          Center(
            child: Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                for (final entry in byCompany)
                  _legendItem(entry, summary.total),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _deliveryRate(summary),
        ],
      ),
    );
  }

  Widget _shareBar(
    List<({Company company, double value})> byCompany,
    double total,
  ) {
    final visible = byCompany.where((entry) => entry.value > 0).toList();

    // Período inteiro de rotas com valor zero: uma barra vazia é mais honesta
    // que dividir por zero para achar a proporção.
    if (visible.isEmpty || total <= 0) {
      return Container(
        height: 12,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(50),
        ),
      );
    }

    // O arredondamento dos cantos fica no ClipRRect, e não em cada pedaço: a
    // conta de "sou o primeiro ou o último?" erra assim que uma empresa some.
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: Row(
        children: [
          for (final entry in visible)
            Expanded(
              flex: (entry.value / total * 1000).round().clamp(1, 1000),
              child: Container(
                height: 12,
                color: companyColor(entry.company),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendItem(({Company company, double value}) entry, double total) {
    final share = total > 0 ? entry.value / total * 100 : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 4, backgroundColor: companyColor(entry.company)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${companyLabel(entry.company)} (${share.toStringAsFixed(0)}%)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
              ),
            ),
            Text(
              _money(entry.value),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _deliveryRate(PeriodSummary summary) {
    final rate = summary.deliveryRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Taxa de entrega',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        if (rate == null)
          Text(
            'Preencha "Pacotes" na rota para acompanhar.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: rate,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF69F0AE), Color(0xFF00C853)],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(rate * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${summary.failures} de ${summary.packages} pacotes)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
            ],
          ),
      ],
    );
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
          ChartStat('MAIOR', _money(byValue.first.value)),
          ChartStat('MENOR', _money(byValue.last.value)),
        ],
      ),
      BarRankChart(
        title: 'Empresas por rotas',
        entries: byCount,
        formatValue: _whole,
        emptyMessage: 'Nenhuma rota no período.',
        stats: [
          ChartStat('TOTAL', '${summary.count}'),
          ChartStat('MAIOR', _whole(byCount.first.value)),
          ChartStat('MENOR', _whole(byCount.last.value)),
        ],
      ),
      BarRankChart(
        title: 'Insucessos por empresa',
        entries: failures,
        formatValue: _whole,
        emptyMessage: 'Nenhuma rota no período.',
        stats: [
          ChartStat('TOTAL', _whole(totalFailures)),
          ChartStat('MAIOR', _whole(failures.first.value)),
          ChartStat('MENOR', _whole(failures.last.value)),
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
          ChartStat(
            'MAIOR',
            rates.isEmpty ? '—' : _percent(rates.first.value),
          ),
          ChartStat('MENOR', rates.isEmpty ? '—' : _percent(rates.last.value)),
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
          ChartStat(
            'MAIOR',
            rodados.isEmpty ? '—' : _whole(rodados.first.value),
          ),
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
          ChartStat(
            'MAIOR',
            failures.isEmpty ? '—' : _oneDecimal(failures.first.value),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
