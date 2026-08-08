import 'package:flutter/material.dart';

/// Uma opção do trilho.
///
/// [child] é o que aparece dentro da pílula — um ícone, um logo. Quando é
/// `null`, o [label] é desenhado como texto, e aí o tooltip não entra: o
/// rótulo já está na tela e o balão viraria ruído.
class SegmentOption<T> {
  const SegmentOption({
    required this.value,
    required this.label,
    required this.keySuffix,
    this.child,
  });

  final T value;

  /// Rótulo do tooltip, e o texto desenhado quando não há [child].
  final String label;

  /// Sufixo da `ValueKey` do segmento — o prefixo vem do trilho.
  final String keySuffix;

  final Widget? child;
}

/// Controle segmentado: um trilho cinza com uma pílula branca no selecionado.
///
/// Saiu de dentro do `CompanyFilter`, que era o único controle desse formato
/// no app e sabia demais sobre empresa. A generalização é o caminho que o
/// `polimento-glass.md` já registrou: copiar superfície gerou quatro widgets
/// com três opacidades diferentes, e polir um só criava a quinta variante.
///
/// Todos os segmentos são `Expanded` — dividem a largura igualmente e não
/// rolam. Com quatro ou cinco isso é confortável; acima disso, o rótulo de
/// texto começa a apertar antes de o trilho ficar feio.
class SegmentedSelector<T> extends StatelessWidget {
  const SegmentedSelector({
    super.key,
    required this.keyPrefix,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  /// Prefixo das `ValueKey` dos segmentos: `'filtro'` vira `filtro-todas`.
  final String keyPrefix;

  final List<SegmentOption<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [for (final option in segments) _segment(option)],
      ),
    );
  }

  Widget _segment(SegmentOption<T> option) {
    final isSelected = option.value == selected;

    Widget tappable = GestureDetector(
      key: ValueKey('$keyPrefix-${option.keySuffix}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(option.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        // Apagar o não selecionado deixa claro qual está ativo sem precisar de
        // fundo colorido em cada opção.
        //
        // Um `Opacity` por segmento e nenhum fora deles: o teste do
        // `CompanyFilter` conta os da árvore inteira. `AnimatedOpacity`
        // também não serve — ele não é um `Opacity`.
        child: Center(
          child: Opacity(
            opacity: isSelected ? 1 : 0.45,
            child: option.child ?? _label(option.label),
          ),
        ),
      ),
    );

    if (option.child != null) {
      tappable = Tooltip(message: option.label, child: tappable);
    }

    return Expanded(child: tappable);
  }

  static Widget _label(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }
}
