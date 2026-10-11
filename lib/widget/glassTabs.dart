import 'package:flutter/material.dart';
import 'package:iter/widget/glassSurface.dart';
import 'package:iter/widget/segmentedSelector.dart';
import 'package:iter/widget/slidingIndicator.dart';

/// Abas de texto no vidro — Amigos / Ranking / Feed, no topo da aba Amigos.
///
/// Foram pedidas "parecidas com a barra de baixo", e são a barra de baixo com
/// texto: o mesmo `GlassSurface`, a mesma pílula azul ([GlassIndicator]) e o
/// mesmo [SlidingIndicator]. Antes eram um `SegmentedSelector` idêntico ao de
/// critério logo abaixo, e as duas barras iguais empilhadas não diziam qual
/// mandava na outra.
///
/// Reaproveita [SegmentOption] em vez de inventar outro tipo de opção: valor,
/// rótulo e sufixo de key são os mesmos três dados.
class GlassTabs<T> extends StatelessWidget {
  const GlassTabs({
    super.key,
    required this.keyPrefix,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  /// Prefixo das `ValueKey` das abas: `'aba'` vira `aba-ranking`.
  final String keyPrefix;

  final List<SegmentOption<T>> tabs;
  final T selected;

  /// Avisa a aba tocada, inclusive a já selecionada — engolir o toque faria a
  /// barra parecer travada, a mesma regra da `GlassNavBar`.
  final ValueChanged<T> onChanged;

  static const double _height = 48;

  /// O vidro, o recuo e a borda de 1 px do `GlassSurface` somados: o que sobra
  /// para a pílula e para o texto.
  static const double _inner = _height - 2 * (_padding + 1);
  static const double _padding = 4;

  @override
  Widget build(BuildContext context) {
    final index = tabs.indexWhere((tab) => tab.value == selected);

    return GlassSurface(
      // Superfície **com texto**: a opacidade que o `GlassSurface` documenta
      // para isso, porque letra sobre vidro claro precisa de mais fundo.
      opacity: 0.75,
      borderRadius: BorderRadius.circular(_height / 2),
      padding: const EdgeInsets.all(_padding),
      // A sombra da `GlassPill`: flutua sem disputar com a barra de baixo,
      // que tem a sombra mais funda do app.
      shadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
      child: SizedBox(
        height: _inner,
        child: Stack(
          children: [
            if (index >= 0)
              Positioned.fill(
                child: SlidingIndicator(
                  count: tabs.length,
                  index: index,
                  child: const GlassIndicator(radius: _inner / 2),
                ),
              ),
            Row(children: [for (final tab in tabs) _tab(tab)]),
          ],
        ),
      ),
    );
  }

  Widget _tab(SegmentOption<T> tab) {
    final isOn = tab.value == selected;

    return Expanded(
      child: GestureDetector(
        key: ValueKey('$keyPrefix-${tab.keySuffix}'),
        // `opaque`: o texto não preenche a aba, e sem isto o toque ao lado da
        // palavra cairia no vazio.
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(tab.value),
        child: Center(
          // A cor acompanha as bordas da pílula. Texto que fica branco antes de
          // a pílula chegar é branco sobre vidro claro, e texto que fica azul
          // antes de ela sair é azul sobre azul — ilegível por um instante, o
          // mesmo "pisca" do trilho antigo.
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: isOn
                  ? Colors.white
                  : GlassIndicator.accent.withValues(alpha: 0.7),
            ),
            duration: SlidingIndicator.total,
            curve: SlidingIndicator.contentCurve(on: isOn),
            builder: (context, color, _) => Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
