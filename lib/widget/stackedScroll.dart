import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Um card da pilha: a altura que ele ocupa e o que desenhar.
///
/// A altura vem de fora porque quem sabe medi-la é o próprio card — ver
/// `ChartCarousel.totalHeight`. Medi-la aqui exigiria layout em duas passadas,
/// e a pilha precisa do número **antes** de desenhar qualquer coisa.
class StackedCard {
  const StackedCard({this.key, required this.height, required this.child});

  /// Identidade do card na pilha.
  ///
  /// Vai no filho **direto** do `Stack`, e não no widget de dentro: é ali que o
  /// Flutter casa elementos entre dois builds. Medido — com a chave um nível
  /// abaixo, reordenar a lista faz cada carrossel perder a página em que
  /// estava, exatamente como se não houvesse chave nenhuma.
  final Key? key;

  final double height;
  final Widget child;
}

/// Rolagem em que cada card **encaixa no topo** ao chegar lá, e o seguinte
/// desliza por cima deixando uma faixa do anterior aparecendo.
///
/// No fim da rolagem o topo é uma pilha de bordas — uma por card já passado —
/// que diz quantos blocos ficaram para trás sem ocupar espaço de conteúdo.
/// Cada card que fica para trás encolhe um degrau, e encolhe de novo a cada
/// card novo que pousa em cima: é o que separa a pilha de um bloco só de cor.
///
/// Só apresentação: não sabe o que há dentro dos cards e não muda nada do que
/// eles mostram.
class StackedScroll extends StatefulWidget {
  const StackedScroll({
    super.key,
    required this.cards,
    this.gap = 20,
    this.peek = 12,
    this.shrink = 0.03,
    this.shrinkRange = 72,
    this.padding = EdgeInsets.zero,
  });

  final List<StackedCard> cards;

  /// Espaço entre dois cards enquanto eles ainda rolam soltos.
  final double gap;

  /// Quanto de cada card encaixado continua aparecendo. É a altura da faixa.
  final double peek;

  /// Quanto o card perde de tamanho a cada nível de profundidade na pilha.
  ///
  /// Zero desliga o efeito e devolve a pilha de faixas todas do mesmo tamanho.
  final double shrink;

  /// Em quantos pixels **finais** da cobertura o card encolhe o seu degrau.
  ///
  /// O encolhimento é concentrado no fim de propósito. Espalhado pela cobertura
  /// inteira, o card do topo da pilha passaria a maior parte da rolagem mais
  /// estreito do que o card que o está cobrindo — os ombros dele aparecendo de
  /// fora, que é o contrário do empilhamento. Nos últimos pixels o card já é
  /// quase só a faixa, e a diferença de largura lê como profundidade.
  final double shrinkRange;

  final EdgeInsets padding;

  @override
  State<StackedScroll> createState() => _StackedScrollState();
}

class _StackedScrollState extends State<StackedScroll> {
  /// Só é usado quando não há um controller primário na árvore.
  final _fallback = ScrollController();

  @override
  void dispose() {
    _fallback.dispose();
    super.dispose();
  }

  /// O controller primário quando existe um, senão o próprio.
  ///
  /// A rolagem antiga não declarava controller e por isso **herdava** o
  /// primário — é dele que depende o gesto de tocar na barra de status para
  /// voltar ao topo. Criar um controller próprio e parar por aí levaria esse
  /// gesto embora sem nada na tela denunciando; medido, o app tem um primário
  /// na árvore. Aqui a pilha precisa escutar a rolagem para posicionar os
  /// cards, então ela declara — mas declara o mesmo que herdaria.
  ScrollController _controllerOf(BuildContext context) =>
      PrimaryScrollController.maybeOf(context) ?? _fallback;

  /// Onde cada card ficaria se nada encaixasse.
  List<double> get _naturalTops {
    final tops = <double>[];
    var acc = widget.padding.top;
    for (final card in widget.cards) {
      tops.add(acc);
      acc += card.height + widget.gap;
    }
    return tops;
  }

  /// Altura total do conteúdo rolável.
  ///
  /// Sem o espaçamento depois do último card: ele viraria espaço morto no fim
  /// da tela, e o `padding.bottom` já é quem responde por esse respiro.
  double get _contentHeight {
    var total = widget.padding.top + widget.padding.bottom;
    for (var index = 0; index < widget.cards.length; index++) {
      total += widget.cards[index].height;
      if (index < widget.cards.length - 1) total += widget.gap;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();

    final naturalTops = _naturalTops;
    final controller = _controllerOf(context);
    final horizontal = EdgeInsets.only(
      left: widget.padding.left,
      right: widget.padding.right,
    );

    return SingleChildScrollView(
      controller: controller,
      child: SizedBox(
        height: _contentHeight,
        // A ordem dos filhos é a ordem de pintura, e é ela que faz o card novo
        // **cobrir** o encaixado em vez de sumir atrás dele. Inverter a lista
        // inverteria o efeito inteiro.
        child: Stack(
          children: [
            for (var index = 0; index < widget.cards.length; index++)
              Positioned.fill(
                key: widget.cards[index].key,
                child: AnimatedBuilder(
                  animation: controller,
                  // O card vai como `child`, e não montado dentro do `builder`:
                  // assim só o `Transform` é reconstruído a cada pixel de
                  // rolagem. Montá-lo ali reconstruiria os gráficos inteiros,
                  // com os seus `PageView`, a cada quadro.
                  child: Padding(
                    padding: horizontal,
                    child: SizedBox(
                      height: widget.cards[index].height,
                      child: widget.cards[index].child,
                    ),
                  ),
                  builder: (context, child) {
                    final offset = controller.hasClients
                        ? controller.offset
                        : 0.0;

                    return Transform.translate(
                      offset: Offset(0, _topOf(index, naturalTops, offset)),
                      child: Align(
                        alignment: Alignment.topCenter,
                        // A escala é ancorada no **topo** do card, e não no
                        // centro: o topo é a faixa, a única parte que ainda
                        // aparece. Ancorada no centro, encolher desceria a
                        // faixa junto e a distância entre duas faixas deixaria
                        // de ser o `peek` — a pilha se desmancharia sozinha.
                        //
                        // `Transform` é transformação de pintura: nada é
                        // remedido, e o gráfico lá dentro não refaz layout
                        // nenhum por causa do encolhimento.
                        child: Transform.scale(
                          scale: _scaleOf(index, naturalTops, offset),
                          alignment: Alignment.topCenter,
                          // A faixa que sobra de um card coberto é o **topo** do
                          // card, e o topo do card é o topo do `PageView` dele —
                          // ninguém a cobre, então ela continuava recebendo
                          // toque. Medido: arrastar de lado na faixa trocava a
                          // página de um carrossel invisível, e o usuário só
                          // descobria ao rolar de volta. Ignorando o ponteiro, o
                          // arrasto vertical passa direto para a rolagem, que é
                          // o único gesto que a faixa deve aceitar.
                          child: IgnorePointer(
                            ignoring: _isCovered(index, naturalTops, offset),
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Onde o card [index] é desenhado, em coordenada **do conteúdo**.
  ///
  /// `offset +` é o detalhe que decide tudo: o conteúdo do
  /// `SingleChildScrollView` já vem deslocado por `-offset`, então a posição de
  /// encaixe também tem de ser medida a partir do conteúdo. Escrito como
  /// `max(index * peek, natural - offset)` o card "encaixa" e continua subindo
  /// junto com a rolagem — e o pior é que a distância **entre** os cards fica
  /// certa, então só a posição absoluta denuncia o erro.
  double _topOf(int index, List<double> naturalTops, double offset) {
    // Enquanto o card está longe do topo, o natural vence e ele rola solto;
    // quando a rolagem o alcança, o encaixe vence e ele para.
    return math.max(
      offset + widget.padding.top + index * widget.peek,
      naturalTops[index],
    );
  }

  /// Quanto do card [index] ainda aparece, do topo dele ao topo do seguinte.
  ///
  /// Solto, é a altura inteira mais o `gap`; coberto, é a faixa.
  double _visibleOf(int index, List<double> naturalTops, double offset) =>
      _topOf(index + 1, naturalTops, offset) -
      _topOf(index, naturalTops, offset);

  /// O quanto o card [index] já foi coberto pelo seguinte, de 0 a 1.
  double _coverOf(int index, List<double> naturalTops, double offset) {
    if (index >= widget.cards.length - 1) return 0;

    final sobra = _visibleOf(index, naturalTops, offset) - widget.peek;
    return (1 - sobra / widget.shrinkRange).clamp(0.0, 1.0);
  }

  /// A escala do card [index]: um degrau menor por card empilhado sobre ele.
  ///
  /// A profundidade é **contínua** — a soma de quanto cada card daqui para
  /// baixo já foi coberto — e não a contagem de quantos encaixaram. Contada em
  /// número inteiro, a pilha inteira daria um pulo de tamanho no quadro em que
  /// o card seguinte pousa; somada assim, ela acompanha o dedo. Como os cards
  /// encaixam em ordem, cada parcela só começa a crescer quando a anterior
  /// chegou a 1, e a soma anda de degrau em degrau sem nunca voltar.
  ///
  /// A conta é multiplicativa: cada nível tira uma fração do tamanho **atual**,
  /// nunca do original. `1 - shrink * profundidade` zera a escala no nível
  /// `1/shrink` e a inverte depois dele — e este widget não sabe quantos cards
  /// vai receber. De quebra, os degraus vão ficando menores conforme afundam,
  /// que é como uma pilha de verdade recua.
  double _scaleOf(int index, List<double> naturalTops, double offset) {
    if (widget.shrink <= 0) return 1;

    var depth = 0.0;
    for (var i = index; i < widget.cards.length - 1; i++) {
      depth += _coverOf(i, naturalTops, offset);
    }

    return math.pow(1 - widget.shrink, depth).toDouble();
  }

  /// Do card sobrou **só a faixa**.
  ///
  /// A régua é o que ainda aparece, e não se há sobreposição: durante a
  /// transição o card seguinte já invade alguns pixels do de cima, e um card
  /// 96% visível tem de continuar aceitando o arrasto das suas páginas. O
  /// primeiro rascunho desligava o toque nessa invasão inicial, e o teste é que
  /// mostrou o exagero.
  ///
  /// Quando o que resta é a faixa, não há o que tocar — e é aí que o arrasto
  /// horizontal deixa de fazer sentido, porque ele mexeria num carrossel que
  /// ninguém está vendo.
  bool _isCovered(int index, List<double> naturalTops, double offset) {
    if (index == widget.cards.length - 1) return false;

    // Meio pixel de folga: as posições saem de contas com `double`, e a faixa
    // exata vira 11.999999 com facilidade.
    return _visibleOf(index, naturalTops, offset) <= widget.peek + 0.5;
  }
}
