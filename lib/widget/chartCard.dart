import 'package:flutter/material.dart';

/// Um número do cabeçalho do card: rótulo curto e valor já formatado.
class ChartStat {
  const ChartStat(this.label, this.value);

  final String label;
  final String value;
}

/// Moldura compartilhada de todos os cards de gráfico: gradiente azul, título,
/// até três números no topo e o gráfico embaixo.
///
/// Existe para os seis gráficos não serem seis cópias da mesma decoração — foi
/// o que aconteceu na tela que serviu de referência, onde cada mudança de
/// espaçamento tinha que ser repetida seis vezes.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.stats = const <ChartStat>[],
    this.footnote,
    this.fillHeight = true,
  });

  final String title;

  /// O gráfico em si.
  final Widget child;

  /// Canto direito do título — o seletor de turno, por exemplo.
  final Widget? trailing;

  final List<ChartStat> stats;

  /// Linha miúda no rodapé, para a ressalva que o gráfico precisa carregar
  /// (ex.: "considera só rotas com pacotes informados").
  final String? footnote;

  /// Dentro de um carrossel de altura fixa o gráfico ocupa a sobra; no card de
  /// resumo, que rola com a página, ele tem a altura do próprio conteúdo.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [for (final stat in stats) _stat(stat)]),
          ],
          const SizedBox(height: 12),
          if (fillHeight) Expanded(child: child) else child,
          if (footnote != null) ...[
            const SizedBox(height: 10),
            Text(
              footnote!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(ChartStat stat) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          // Valor em reais estoura três colunas com facilidade; encolher é
          // melhor que cortar com reticências, que esconde justo o dígito mais
          // significativo.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              stat.value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mensagem de vazio padrão de dentro de um [ChartCard].
class ChartEmpty extends StatelessWidget {
  const ChartEmpty(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 14,
        ),
      ),
    );
  }
}
