import 'package:flutter/material.dart';

/// As duas bordas de um indicador, em pixels a partir da esquerda do trilho.
typedef IndicatorEdges = ({double left, double right});

/// O indicador que desliza entre as fatias de um trilho — **um só** para as abas
/// do topo de Amigos, o critério do Ranking e a barra de baixo.
///
/// Existe porque o trilho de critério acendia **dois** segmentos a cada toque:
/// cada segmento tinha a própria pílula, e a velha apagava enquanto a nova
/// acendia. Com um indicador por trilho isso não tem como acontecer. E um para
/// os três porque três cópias do mesmo movimento divergem na primeira vez que
/// alguém ajusta a curva de uma — a deriva que o `GlassSurface` fechou para o
/// material, agora para o movimento.
///
/// O movimento é "líquido": a borda da frente sai primeiro e a de trás alcança
/// [lag] depois, então a pílula estica no caminho e volta ao tamanho ao chegar.
/// **Sem chave para desligar** — um segundo jeito de se mover é a divergência
/// esperando para acontecer. Ver `docs/specs/redesenho-amigos.md`.
///
/// Ocupa a área que o pai der (quem usa o põe num `Positioned` do tamanho do
/// trilho) e desenha [child] entre as bordas da fatia [index].
class SlidingIndicator extends StatefulWidget {
  const SlidingIndicator({
    super.key,
    required this.count,
    required this.index,
    required this.child,
    this.inset = 0,
    this.widthFor,
  });

  final int count;
  final int index;

  /// O desenho da pílula — gradiente azul no vidro, branco sobre a cabeça azul
  /// do Ranking. O movimento é daqui; a aparência é de quem chama.
  final Widget child;

  /// Recuo de cada lado dentro da fatia.
  final double inset;

  /// A largura do indicador para uma fatia desta largura, centrado nela.
  ///
  /// Existe pela barra de baixo, cujo marcador não ocupa a fatia inteira: o
  /// ícone não pede, e um marcador de 180 px em volta de um ícone de 26 parece
  /// botão, não seleção. `null` ocupa a fatia menos [inset] de cada lado.
  final double Function(double slot)? widthFor;

  /// Quanto **cada borda** leva para chegar — os 300 ms que a barra de baixo
  /// sempre usou.
  static const Duration edge = Duration(milliseconds: 300);

  /// O atraso da borda de trás. É ele que estica a pílula; o gesto inteiro
  /// leva [edge] + [lag].
  static const Duration lag = Duration(milliseconds: 120);

  /// Rápida no começo e freando no fim: o indicador **chega**, em vez de parar
  /// seco.
  static const Curve curve = Curves.easeOutCubic;

  /// O gesto inteiro: a borda da frente e o atraso da de trás.
  static const Duration total = Duration(milliseconds: 420);

  /// A curva do **conteúdo** de uma fatia — rótulo, ícone —, em [total].
  ///
  /// Quem acende muda junto com a borda da frente, que chega primeiro. Quem
  /// apaga espera a borda de trás começar a sair: com os dois no mesmo tempo, o
  /// rótulo que saía já era branco enquanto a pílula branca ainda estava
  /// embaixo dele, e sumia por um instante — o mesmo "pisca" com outra roupa.
  static Curve contentCurve({required bool on}) => on
      ? const Interval(0, 300 / 420, curve: curve)
      : const Interval(120 / 420, 1, curve: curve);

  @override
  State<SlidingIndicator> createState() => _SlidingIndicatorState();
}

class _SlidingIndicatorState extends State<SlidingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SlidingIndicator.total,
    value: 1,
  );

  /// De onde o deslize atual partiu. `null` é indicador parado no alvo.
  IndicatorEdges? _from;

  /// As bordas do último quadro desenhado.
  ///
  /// É a origem de uma troca que chega **no meio do caminho**: partir da fatia
  /// antiga faria o indicador saltar para trás antes de seguir — um toque
  /// rápido em Ritmo e depois em Insucesso piscaria a pílula de volta em Rotas.
  IndicatorEdges? _drawn;

  @override
  void didUpdateWidget(SlidingIndicator old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;

    // Quem pediu ao sistema menos movimento recebe o indicador já no lugar.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _from = null;
      _controller.value = 1;
      return;
    }

    _from = _drawn;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IndicatorEdges _target(double width) {
    final slot = width / widget.count;
    final size = widget.widthFor?.call(slot) ?? slot - widget.inset * 2;
    final left = widget.index * slot + (slot - size) / 2;
    return (left: left, right: left + size);
  }

  /// As bordas neste instante do deslize.
  ///
  /// Cada borda tem a própria curva: a da frente começa já, a de trás espera
  /// [SlidingIndicator.lag]. "Frente" depende do sentido — indo para a
  /// direita é a borda direita que puxa.
  IndicatorEdges _edgesNow(IndicatorEdges target) {
    final from = _from;
    if (from == null || _controller.isCompleted) return target;

    final elapsed = _controller.value * SlidingIndicator.total.inMicroseconds;
    final edge = SlidingIndicator.edge.inMicroseconds;
    final lagged = elapsed - SlidingIndicator.lag.inMicroseconds;

    final lead = SlidingIndicator.curve.transform(
      (elapsed / edge).clamp(0.0, 1.0),
    );
    final trail = SlidingIndicator.curve.transform(
      (lagged / edge).clamp(0.0, 1.0),
    );

    final toRight = target.left > from.left;
    return (
      left: _lerp(from.left, target.left, toRight ? trail : lead),
      right: _lerp(from.right, target.right, toRight ? lead : trail),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _controller,
          // O desenho entra como `child` e não é montado dentro do builder:
          // senão cada quadro reconstruiria o gradiente e a sombra.
          child: widget.child,
          builder: (context, child) {
            final edges = _edgesNow(_target(constraints.maxWidth));
            // Guardado para a próxima troca partir daqui. É cache do que foi
            // desenhado, não estado da tela — por isso sem `setState`.
            _drawn = edges;

            return Stack(
              children: [
                Positioned(
                  left: edges.left,
                  width: edges.right - edges.left,
                  top: 0,
                  bottom: 0,
                  child: child!,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
