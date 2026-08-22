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
///
/// Dois modos e um desenho só: o construtor padrão acende exatamente um
/// segmento, [SegmentedSelector.multi] acende quantos o chamador mandar. Quem
/// decide isso é [_isOn], e só ele — desenhar cada modo do seu jeito é a mesma
/// cópia de superfície registrada no parágrafo acima, agora dentro de um
/// arquivo só.
class SegmentedSelector<T> extends StatelessWidget {
  /// Escolha única: [selected] é o valor aceso, e só ele.
  const SegmentedSelector({
    super.key,
    required this.keyPrefix,
    required this.segments,
    required T selected,
    required this.onChanged,
  }) : _single = selected,
       _multiple = null;

  /// Múltipla escolha: [selected] é o conjunto do que está aceso.
  ///
  /// [onChanged] muda de sentido aqui — passa a ser "o usuário tocou NESTE", e
  /// nunca "este acabou de ser marcado". Quem alterna é o chamador
  /// (`RouteFilter.toggleCompany`), porque é ele quem sabe se marcar a Amazon
  /// soma ou substitui. O trilho não guarda estado: tocar num segmento aceso o
  /// devolve aceso, até chegar um conjunto novo.
  ///
  /// Conjunto vazio deixa **todos apagados**. No filtro de empresa vazio quer
  /// dizer "passa tudo", então o trilho sozinho parece filtro que não deixa
  /// nada passar — quem desfaz isso é a tela, não este widget: `filtros.md`
  /// resolve no estado vazio da lista, que nunca fica em branco sem dizer por
  /// quê.
  const SegmentedSelector.multi({
    super.key,
    required this.keyPrefix,
    required this.segments,
    required Set<T> selected,
    required this.onChanged,
  }) : _single = null,
       _multiple = selected;

  /// Prefixo das `ValueKey` dos segmentos: `'filtro'` vira `filtro-amazon`.
  final String keyPrefix;

  final List<SegmentOption<T>> segments;
  final ValueChanged<T> onChanged;

  /// O valor aceso na escolha única. Só é lido quando [_multiple] é `null`.
  final T? _single;

  /// O conjunto aceso na múltipla escolha, e o discriminador entre os modos.
  final Set<T>? _multiple;

  /// O único juiz de "este segmento está aceso", nos dois modos.
  ///
  /// A escolha única compara, em vez de guardar `{_single}` e perguntar
  /// `contains`, porque `T` pode ser anulável. Com um conjunto só, "modo único
  /// com `null` selecionado" e "múltipla escolha sem nada marcado" precisariam
  /// ser distinguidos, e `{null}` não separa os dois. Por isso o discriminador
  /// é [_multiple], nulo apenas fora da múltipla escolha: o predicado continua
  /// certo quando o valor selecionado é `null`.
  bool _isOn(T value) {
    final multiple = _multiple;
    return multiple == null ? value == _single : multiple.contains(value);
  }

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
    final isOn = _isOn(option.value);

    Widget tappable = GestureDetector(
      key: ValueKey('$keyPrefix-${option.keySuffix}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(option.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isOn ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isOn
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        // Apagar o que não está aceso deixa claro o que está ativo sem precisar
        // de fundo colorido em cada opção.
        //
        // Um `Opacity` por segmento e nenhum fora deles: o teste do
        // `CompanyFilter` conta os da árvore inteira. `AnimatedOpacity`
        // também não serve — ele não é um `Opacity`.
        child: Center(
          child: Opacity(
            opacity: isOn ? 1 : 0.45,
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
