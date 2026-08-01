import 'package:flutter/material.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/widget/chartCard.dart';

/// Paleta das barras, ciclada por posição. Quatro tons chapados sobre o
/// gradiente azul do card.
const _barColors = [
  Color(0xFF69F0AE),
  Color(0xFF84FFFF),
  Color(0xFFFFECB3),
  Color(0xFFFF8A80),
];

/// Gráfico de barras de um ranking: até [maxBars] degraus, altura proporcional
/// ao maior, valor em cima e rótulo embaixo.
///
/// É o mesmo desenho para os seis rankings da tela — empresa por valor, por
/// quantidade, por insucesso, por índice, e os dois de bairro. O que muda é a
/// lista e o [formatValue].
class BarRankChart extends StatelessWidget {
  const BarRankChart({
    super.key,
    required this.title,
    required this.entries,
    required this.formatValue,
    required this.emptyMessage,
    this.stats = const <ChartStat>[],
    this.footnote,
    this.maxBars = 4,
    this.showShare = true,
  });

  final String title;

  /// Ranking completo, já ordenado. O corte no top [maxBars] é feito aqui —
  /// a participação de cada degrau continua sendo calculada sobre o total
  /// inteiro, senão o que sobra na tela sempre somaria 100%.
  final List<RankEntry> entries;

  final String Function(double value) formatValue;
  final String emptyMessage;
  final List<ChartStat> stats;
  final String? footnote;
  final int maxBars;

  /// Participação do degrau no total, embaixo do rótulo.
  ///
  /// Desligue quando os valores já forem percentuais: somar taxas de insucesso
  /// de empresas diferentes para tirar uma "participação" não significa nada.
  final bool showShare;

  @override
  Widget build(BuildContext context) {
    final top = entries.take(maxBars).toList();
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    final highest = top.isEmpty ? 0.0 : top.first.value;

    return ChartCard(
      title: title,
      stats: stats,
      footnote: footnote,
      child: top.isEmpty
          ? ChartEmpty(emptyMessage)
          : Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var index = 0; index < top.length; index++)
                        _bar(top[index], index, highest),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  child: Row(
                    children: [
                      for (final entry in top) _caption(entry, total),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _bar(RankEntry entry, int index, double highest) {
    // Ranking inteiro zerado (nenhum insucesso no período, por exemplo): sem
    // altura de referência, todas as barras ficam no chão em vez de dividir
    // por zero.
    final ratio = highest > 0 ? entry.value / highest : 0.0;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatValue(entry.value),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: FractionallySizedBox(
                // Fração da altura disponível, e não pixels fixos como na tela
                // de referência: assim a barra acompanha a altura do carrossel
                // em vez de estourar em tela pequena.
                heightFactor: ratio.clamp(0.02, 1.0),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _barColors[index % _barColors.length],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caption(RankEntry entry, double total) {
    final share = showShare && total > 0 ? entry.value / total * 100 : null;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Center(
                child: Text(
                  entry.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (share != null)
              Text(
                '${share.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 9,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
