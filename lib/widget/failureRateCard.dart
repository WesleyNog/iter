import 'package:flutter/material.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/widget/chartCard.dart';

/// Uma linha do card: o eixo (Empresa, Bairro, Clima) e quem lidera o índice
/// nele. [leader] nulo = aquele eixo não tem dado, e [emptyNote] explica por quê.
class FailureRateRow {
  const FailureRateRow({
    required this.axis,
    required this.leader,
    required this.emptyNote,
  });

  final String axis;
  final FailureRate? leader;
  final String emptyNote;
}

/// Índice de insucesso dos três eixos num card só.
///
/// Mostra **o pior de cada eixo**, não todos os itens: a pergunta que se faz
/// olhando isso é "onde dói mais", e uma lista completa de empresas, bairros e
/// climas empilhados responderia isso pior, não melhor.
///
/// Antes eram dois cards de barras verticais (empresa e clima) em páginas
/// separadas do carrossel, e bairro não tinha índice nenhum — comparar os três
/// exigia arrastar e decorar números.
class FailureRateCard extends StatelessWidget {
  const FailureRateCard({
    super.key,
    required this.rows,
    required this.overall,
    this.footnote,
  });

  final List<FailureRateRow> rows;

  /// Índice do período inteiro, o número grande do topo. `null` quando ninguém
  /// informou pacotes.
  final double? overall;

  final String? footnote;

  /// Laranja→vermelho: aqui a barra cheia é notícia ruim, ao contrário da taxa
  /// de entrega do resumo, que é verde.
  static const _colors = [Color(0xFFFFAB91), Color(0xFFFF7043)];

  @override
  Widget build(BuildContext context) {
    // Escala relativa ao pior: com índices baixos (2%, 6%, 12%) uma régua de
    // 0 a 100 deixaria as três barras visualmente idênticas e vazias. O número
    // ao lado é que diz o valor real.
    final worst = rows
        .map((row) => row.leader?.rate ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return ChartCard(
      title: 'Índice de insucesso',
      footnote: footnote,
      stats: [
        ChartStat('GERAL', overall == null ? '—' : _percent(overall!)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [for (final row in rows) _row(row, worst)],
      ),
    );
  }

  Widget _row(FailureRateRow row, double worst) {
    final leader = row.leader;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          leader == null ? row.axis : '${row.axis} · ${leader.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        if (leader == null)
          Text(
            row.emptyNote,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: ChartProgressBar(
                  // Tudo zerado não vira barra cheia: sem insucesso nenhum, as
                  // três ficam vazias, que é a leitura certa.
                  fraction: worst <= 0 ? 0 : leader.rate / worst,
                  colors: _colors,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _percent(leader.rate),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '(${_count(leader.failures)} de ${_count(leader.packages)})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  static String _percent(double value) => '${value.toStringAsFixed(1)}%';

  /// Bairro tem números rateados e cai em quebrado; empresa e clima são
  /// inteiros. Mostrar "24,0 pacotes" onde cabe "24" só polui.
  static String _count(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
