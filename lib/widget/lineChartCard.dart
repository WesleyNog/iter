import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:iter/widget/chartCard.dart';

/// Gráfico de linha de uma série contínua.
///
/// Os dois usos da tela são sequências de inteiros seguidos — dia da semana
/// (0 a 6) e hora do turno (ex.: 5 a 11) — então a série entra como uma lista
/// de valores mais o [firstX] de onde ela começa. Sem tipo de ponto novo e sem
/// o `fl_chart` vazar para a tela.
class LineChartCard extends StatelessWidget {
  const LineChartCard({
    super.key,
    required this.title,
    required this.values,
    required this.firstX,
    required this.labelOf,
    required this.tooltipLabelOf,
    required this.formatValue,
    required this.formatAxis,
    required this.emptyMessage,
    this.trailing,
    this.stats = const <ChartStat>[],
    this.lineColors = const [Color(0xFF69F0AE), Color(0xFF84FFFF)],
  });

  final String title;

  /// Valores em sequência; o eixo X é `firstX + índice`.
  final List<double> values;
  final int firstX;

  /// Rótulo curto do eixo (`Seg`, `08h`).
  final String Function(int x) labelOf;

  /// Rótulo por extenso do tooltip (`Segunda-feira`).
  final String Function(int x) tooltipLabelOf;

  final String Function(double value) formatValue;

  /// Eixo vertical: versão curta, que precisa caber em 56px.
  final String Function(double value) formatAxis;

  final String emptyMessage;
  final Widget? trailing;
  final List<ChartStat> stats;
  final List<Color> lineColors;

  @override
  Widget build(BuildContext context) {
    final highest = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a > b ? a : b);

    return ChartCard(
      title: title,
      trailing: trailing,
      stats: stats,
      // Série toda zerada desenha uma reta no chão que parece dado. Melhor
      // dizer que não houve rota.
      child: highest <= 0
          ? ChartEmpty(emptyMessage)
          : Padding(
              padding: const EdgeInsets.only(top: 12, right: 12),
              child: LineChart(_data(highest)),
            ),
    );
  }

  LineChartData _data(double highest) {
    final step = highest / 4;
    final lastX = firstX + values.length - 1;

    return LineChartData(
      minX: firstX.toDouble(),
      maxX: lastX.toDouble(),
      minY: 0,
      // Folga no topo para o maior ponto não encostar na borda do card.
      maxY: highest * 1.15,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: step,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.white.withValues(alpha: 0.12), strokeWidth: 1),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          left: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 28,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(
                labelOf(value.round()),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: step,
            reservedSize: 56,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(
                formatAxis(value),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var index = 0; index < values.length; index++)
              FlSpot((firstX + index).toDouble(), values[index]),
          ],
          isCurved: true,
          // Sem isso a curva "estoura" abaixo de zero entre dois pontos quando
          // um vale é muito fundo, desenhando faturamento negativo.
          preventCurveOverShooting: true,
          gradient: LinearGradient(colors: lineColors),
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 5,
              color: Colors.white,
              strokeWidth: 3,
              strokeColor: lineColors.first,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                lineColors.first.withValues(alpha: 0.3),
                lineColors.last.withValues(alpha: 0.05),
              ],
            ),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.white.withValues(alpha: 0.92),
          getTooltipItems: (spots) => [
            for (final spot in spots)
              LineTooltipItem(
                '${tooltipLabelOf(spot.x.round())}\n${formatValue(spot.y)}',
                const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
