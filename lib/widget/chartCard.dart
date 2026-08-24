import 'package:flutter/material.dart';

/// Um número do cabeçalho do card: rótulo curto e valor já formatado.
class ChartStat {
  const ChartStat(this.label, this.value);

  final String label;
  final String value;
}

/// A paleta de um card: o fundo, as barras do ranking e a barra de progresso.
///
/// Existe porque o carrossel de insucessos passou a ter um fundo próprio, e
/// trocar só o gradiente deixaria as barras erradas: as cores de barra foram
/// escolhidas **contra o azul**, e o salmão (`#FF8A80`) sobre laranja é a
/// mesma cor duas vezes. Uma paleta é o conjunto inteiro, ou o card fica
/// legível só na metade que alguém lembrou de trocar.
///
/// As cores de [alerta] não foram escolhidas no olho: passaram no validador de
/// paleta (croma, separação sob daltonismo, piso de visão normal e contraste
/// contra a superfície). A única checagem que elas "reprovam" é a faixa de
/// luminosidade, calibrada para superfície neutra quase preta — sobre um
/// laranja vivo a barra precisa justamente sair dessa faixa para contrastar.
class ChartPalette {
  const ChartPalette({
    required this.gradient,
    required this.bars,
    required this.progress,
  });

  /// Fundo do card, do canto superior esquerdo ao inferior direito.
  final List<Color> gradient;

  /// Barras do ranking, cicladas por posição.
  final List<Color> bars;

  /// Preenchimento da [ChartProgressBar].
  final List<Color> progress;

  /// O azul de sempre — dinheiro, empresa, bairro, tempo.
  static const azul = ChartPalette(
    gradient: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
    bars: [
      Color(0xFF69F0AE),
      Color(0xFF84FFFF),
      Color(0xFFFFECB3),
      Color(0xFFFF8A80),
    ],
    // Laranja→vermelho: no card de índice a barra cheia é notícia ruim, ao
    // contrário da taxa de entrega do resumo, que é verde.
    progress: [Color(0xFFFFAB91), Color(0xFFFF7043)],
  );

  /// O laranja dos insucessos — o dado que é ruim justamente quando cresce.
  ///
  /// Complementar do azul na roda de cores, nos mesmos degraus do Material
  /// (900 / 700 / 400) que o azul usa: o antagonismo sai da construção, não de
  /// tentativa e erro.
  static const alerta = ChartPalette(
    gradient: [Color(0xFFBF360C), Color(0xFFE64A19), Color(0xFFFF7043)],
    bars: [
      Color(0xFFFFE082),
      Color(0xFF18FFFF),
      Color(0xFFCCFF90),
      Color(0xFF4A148C),
    ],
    // Dourado sobre laranja queimado: quente com quente mantém a leitura de
    // "ruim", e os dois tons passam de 3:1 contra o fundo.
    progress: [Color(0xFFFFECB3), Color(0xFFFFE082)],
  );
}

/// Moldura compartilhada de todos os cards de gráfico: gradiente, título,
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
    this.palette = ChartPalette.azul,
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

  final ChartPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: palette.gradient,
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

/// Barra horizontal de preenchimento sobre o fundo do card.
///
/// Mora aqui, e não no card que a usa, porque dois cards a desenham: a taxa de
/// entrega do resumo e o índice de insucesso.
class ChartProgressBar extends StatelessWidget {
  const ChartProgressBar({
    super.key,
    required this.fraction,
    required this.colors,
  });

  /// De 0 a 1. Quem chama decide a escala — não é necessariamente a
  /// porcentagem exibida ao lado.
  final double fraction;

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(50),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            gradient: LinearGradient(colors: colors),
          ),
        ),
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
