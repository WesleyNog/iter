import 'package:flutter/material.dart';

/// Carrossel de cards de gráfico, com as bolinhas de posição embaixo.
///
/// É ele quem tem o `PageController` — e o `dispose` junto. Na tela de
/// referência os controllers moravam na tela, um por carrossel, e cada
/// carrossel novo era mais um campo para lembrar de descartar.
///
/// A [height] é fixa e imposta aqui: `PageView` não tem altura própria, e o
/// gráfico dentro de cada página usa `Expanded` contando com essa medida.
class ChartCarousel extends StatefulWidget {
  const ChartCarousel({super.key, required this.height, required this.pages});

  /// Respiro entre o `PageView` e a fileira de bolinhas.
  static const double _dotsSpacing = 10;

  /// A fileira tem a altura da bolinha ativa, que é a maior das duas.
  static const double _activeDotSize = 11;
  static const double _inactiveDotSize = 7;

  final double height;
  final List<Widget> pages;

  /// Tudo o que o carrossel ocupa: a [height] do `PageView` mais o bloco de
  /// bolinhas, quando ele existe.
  ///
  /// Quem empilha os cards (`StackedScroll`) precisa desse número **antes** de
  /// desenhar, e por isso ele mora aqui: refazer a conta lá fora seria copiar o
  /// layout interno deste arquivo para outro. A cópia diverge no primeiro
  /// ajuste de espaçamento, e o sintoma seria a pilha encaixando alguns pixels
  /// fora do lugar — sem nada apontando para cá. As constantes acima são as
  /// mesmas que o `build` usa, então o número não pode discordar do desenho.
  ///
  /// Uma constante fixa de 21px erraria o carrossel de bairros, que tem uma
  /// página só e portanto não desenha bolinha nenhuma.
  double get totalHeight =>
      height + (pages.length > 1 ? _dotsSpacing + _activeDotSize : 0);

  @override
  State<ChartCarousel> createState() => _ChartCarouselState();
}

class _ChartCarouselState extends State<ChartCarousel> {
  final _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView(
            controller: _controller,
            onPageChanged: (index) => setState(() => _current = index),
            children: widget.pages,
          ),
        ),
        // Uma bolinha sozinha promete uma página que não existe. É a mesma
        // condição de `totalHeight`, e as duas têm de continuar iguais.
        if (widget.pages.length > 1) ...[
          const SizedBox(height: ChartCarousel._dotsSpacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < widget.pages.length; index++)
                _dot(isActive: index == _current),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dot({required bool isActive}) {
    final size = isActive
        ? ChartCarousel._activeDotSize
        : ChartCarousel._inactiveDotSize;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? Colors.blue.shade600 : Colors.grey.shade300,
      ),
    );
  }
}
