import 'package:flutter/material.dart';
import 'package:iter/widget/glassSurface.dart';
import 'package:iter/widget/slidingIndicator.dart';

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

/// Sobre o que o trilho está desenhado.
enum SegmentedTone {
  /// Trilho cinza sobre fundo claro — o filtro de empresa da lista.
  light,

  /// Trilho branco translúcido sobre a cabeça azul do Ranking. O rótulo aceso
  /// fica azul sobre a pílula branca; os apagados, brancos sobre o azul.
  onBlue,

  /// Trilho de vidro no topo de uma tela — o filtro de empresas da Lista, ao
  /// lado das abas de vidro de Amigos e do período. A pílula **continua
  /// branca**: os logos têm a cor das marcas, e o X azul da Amazon sumiria
  /// sobre a pílula azul das abas.
  glass,
}

/// Controle segmentado: um trilho com uma pílula branca no selecionado.
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
/// Dois modos: o construtor padrão acende exatamente um segmento,
/// [SegmentedSelector.multi] acende quantos o chamador mandar. Quem decide o
/// que está aceso é [_isOn], e só ele.
///
/// **A pílula é desenhada de um jeito em cada modo, e é de propósito.** Na
/// escolha única existe **uma** pílula, o [SlidingIndicator], que desliza até o
/// segmento novo. Antes cada segmento tinha a própria pílula animando em 150 ms,
/// e no toque a velha apagava enquanto a nova acendia: por um instante havia
/// duas meio acesas — o "pisca dois" do critério do Ranking. Na múltipla
/// escolha acender várias é o objetivo, então cada segmento continua com a sua,
/// e o toque só anima a do segmento tocado.
class SegmentedSelector<T> extends StatelessWidget {
  /// Escolha única: [selected] é o valor aceso, e só ele.
  const SegmentedSelector({
    super.key,
    required this.keyPrefix,
    required this.segments,
    required T selected,
    required this.onChanged,
    this.tone = SegmentedTone.light,
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
    this.tone = SegmentedTone.light,
  }) : assert(tone != SegmentedTone.onBlue),
       _single = null,
       _multiple = selected;

  /// Prefixo das `ValueKey` dos segmentos: `'filtro'` vira `filtro-amazon`.
  final String keyPrefix;

  final List<SegmentOption<T>> segments;
  final ValueChanged<T> onChanged;

  /// A múltipla escolha aceita `light` e `glass` — ela só existe no filtro de
  /// empresa, que nunca fica sobre o azul.
  final SegmentedTone tone;

  bool get _onBlue => tone == SegmentedTone.onBlue;
  bool get _glass => tone == SegmentedTone.glass;

  /// A altura do trilho de vidro: a mesma das abas de vidro e do botão de
  /// filtros ao lado dele, para os três alinharem.
  static const double _glassHeight = 48;

  /// A pílula acompanha a curva do trilho: dentro de uma cápsula, um canto de
  /// 9 px fica quadrado demais.
  double get _pillRadius => _glass ? (_glassHeight - 10) / 2 : 9;

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
    final selectedIndex = _multiple == null
        ? segments.indexWhere((option) => option.value == _single)
        : -1;

    final content = _multiple != null
        ? Row(children: [for (final option in segments) _multiSegment(option)])
        : Stack(
            children: [
              // Valor fora da lista: nenhuma pílula, em vez de uma acesa no
              // segmento errado.
              if (selectedIndex >= 0)
                Positioned.fill(
                  child: SlidingIndicator(
                    count: segments.length,
                    index: selectedIndex,
                    // O mesmo recuo do `margin` de cada segmento: a pílula
                    // assenta exatamente onde o toque cai.
                    inset: 2,
                    child: _pill(),
                  ),
                ),
              Row(
                children: [
                  for (final option in segments) _singleSegment(option),
                ],
              ),
            ],
          );

    if (_glass) {
      return GlassSurface(
        // Superfície com o que ler — a opacidade de texto do material.
        opacity: 0.75,
        borderRadius: BorderRadius.circular(_glassHeight / 2),
        padding: const EdgeInsets.all(4),
        shadow: GlassSurface.pillShadow,
        // 48 menos o recuo de 4 e a borda de 1 px do vidro, dos dois lados.
        child: SizedBox(height: _glassHeight - 10, child: content),
      );
    }

    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _onBlue
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }

  Widget _pill() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_pillRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _onBlue ? 0.18 : 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }

  /// Um segmento da escolha única: sem fundo próprio — quem acende é a pílula
  /// que desliza.
  ///
  /// O rótulo anima **junto** com ela (`SlidingIndicator.contentCurve`). A outra metade do
  /// "pisca dois" era o texto: a `Opacity` pulava para 1 no primeiro quadro, e
  /// o rótulo novo escurecia antes de a pílula dele existir. O
  /// `TweenAnimationBuilder` desenha um `Opacity` — continua sendo um por
  /// segmento, que é o que o teste do `CompanyFilter` conta.
  Widget _singleSegment(SegmentOption<T> option) {
    final isOn = _isOn(option.value);
    final offOpacity = _onBlue ? 1.0 : 0.45;
    final onColor = _onBlue ? const Color(0xFF0D47A1) : Colors.black87;
    final offColor = _onBlue
        ? Colors.white.withValues(alpha: 0.88)
        : Colors.black87;

    Widget tappable = GestureDetector(
      key: ValueKey('$keyPrefix-${option.keySuffix}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(option.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: isOn ? 1 : 0),
            duration: SlidingIndicator.total,
            curve: SlidingIndicator.contentCurve(on: isOn),
            child: option.child,
            builder: (context, t, child) => Opacity(
              opacity: offOpacity + (1 - offOpacity) * t,
              child:
                  child ??
                  _label(option.label, color: Color.lerp(offColor, onColor, t)),
            ),
          ),
        ),
      ),
    );

    if (option.child != null) {
      tappable = Tooltip(message: option.label, child: tappable);
    }

    return Expanded(child: tappable);
  }

  Widget _multiSegment(SegmentOption<T> option) {
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
          borderRadius: BorderRadius.circular(_pillRadius),
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

  static Widget _label(String text, {Color? color = Colors.black87}) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
    );
  }
}
