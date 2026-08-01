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

  final double height;
  final List<Widget> pages;

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
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < widget.pages.length; index++)
              _dot(isActive: index == _current),
          ],
        ),
      ],
    );
  }

  Widget _dot({required bool isActive}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 11 : 7,
      height: isActive ? 11 : 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? Colors.blue.shade600 : Colors.grey.shade300,
      ),
    );
  }
}
