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
    this.eyebrow,
    this.trailing,
    this.stats = const <ChartStat>[],
    this.footnote,
    this.fillHeight = true,
    this.palette = ChartPalette.azul,
  });

  final String title;

  /// O gráfico em si.
  final Widget child;

  /// Linha miúda acima do título, dentro do gradiente: o recorte a que os
  /// números do card obedecem (ex.: "Rotas concluídas e pagas").
  ///
  /// Existe porque na pilha de gráficos o card seguinte encaixa por cima do
  /// rótulo de seção da tela — e é esse rótulo que carrega a ressalva de que
  /// rota agendada fica de fora. Coberto o rótulo, o total daqui passaria a
  /// contradizer o do card de dinheiro, que conta todos os status, sem nada
  /// na tela explicando a diferença.
  ///
  /// `null` deixa o card como sempre foi: sem a linha e sem o espaço dela.
  final String? eyebrow;

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
        // Sobre o fundo claro da tela, e sem nunca se encostarem, os cards
        // liam sem sombra. Na pilha eles se sobrepõem: dois cards da mesma
        // família de cor encostados viram um bloco só, e é a sombra que
        // devolve a borda entre um e outro.
        //
        // Os valores são os da `GlassPill` (glassNavBar.dart) — a sombra de
        // "flutuando sobre o conteúdo" que o app já tem — para não nascer uma
        // terceira variante. O card da lista de rotas não serve de fonte: ele
        // é `elevation: 0` e se separa por uma borda cinza, que sobre um
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
          // Sem eyebrow nada entra na árvore: nem a linha, nem o espaço dela.
          if (eyebrow != null) ...[
            _eyebrow(eyebrow!),
            const SizedBox(height: 6),
          ],
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

  /// O mesmo ícone do rótulo de seção que esta linha substitui, para quem já
  /// conhecia a tela reconhecer a ressalva onde ela foi parar — só que nas
  /// cores de dentro do card, sobre o gradiente.
  Widget _eyebrow(String text) {
    return Row(
      key: const Key('chart-eyebrow'),
      children: [
        Icon(
          Icons.insights_outlined,
          size: 13,
          color: Colors.white.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            // Uma linha só: a altura do card é fixa dentro do carrossel, então
            // uma ressalva que quebrasse em duas linhas sairia da altura do
            // gráfico, não do espaço em branco.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
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
