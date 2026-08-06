import 'dart:ui';

import 'package:flutter/material.dart';

/// O material de vidro do app, num lugar só.
///
/// Existe porque a mesma composição — recorte, `BackdropFilter`, preenchimento
/// translúcido, borda e sombra — estava copiada em quatro widgets, e já tinha
/// divergido em três opacidades e duas APIs de cor. Polir um sem os outros só
/// criaria a quinta variante.
///
/// O efeito é `BackdropFilter` do próprio Flutter, sem pacote nem shader: roda
/// igual no Android e no iOS. Para o blur ter o que borrar, o conteúdo precisa
/// passar por trás — na Home é o `extendBody: true` do `Scaffold`.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur = defaultBlur,
    this.opacity = defaultOpacity,
    this.borderRadius,
    this.circle = false,
    this.padding,
    this.shadow,
  });

  /// Os dois números do material, num lugar só.
  ///
  /// Quem compõe vidro referencia estas constantes em vez de repetir o valor:
  /// foi repetindo que a opacidade virou três números diferentes antes desta
  /// refatoração.
  ///
  /// [defaultBlur] subiu de 18 para 24 no aparelho — 18 deixava o vidro raso
  /// demais sobre os cards de gráfico. É o parâmetro mais caro da composição:
  /// o custo do `BackdropFilter` cresce com o sigma, e esta barra repinta a
  /// cada frame de scroll. Subir muito além disto se paga em frames.
  static const double defaultBlur = 24;
  static const double defaultOpacity = 0.45;

  final Widget child;

  final double blur;

  /// Quanto do vidro é branco — quanto **menor**, mais o fundo atravessa.
  ///
  /// O padrão serve para superfície de **ícone**. Nasceu em 0,55 e desceu para
  /// 0,45 no aparelho: sobre os cards azuis dos gráficos, o valor antigo lia
  /// como folha branca fosca em vez de vidro.
  ///
  /// Superfície com **texto** sobe para ~0,75: letra sobre vidro claro precisa
  /// de mais fundo para ficar legível, e essa diferença é justificada, não
  /// deriva.
  final double opacity;

  /// Ignorado quando [circle] é `true`.
  final BorderRadius? borderRadius;

  final bool circle;

  final EdgeInsetsGeometry? padding;

  /// `null` usa a sombra padrão, que é o que faz a pílula parecer flutuar.
  final List<BoxShadow>? shadow;

  static const _defaultRadius = 24.0;

  /// Espessura da borda em gradiente.
  static const _border = 1.0;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(_defaultRadius);
    final shape = circle ? BoxShape.circle : BoxShape.rectangle;

    final filtered = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: _bordered(radius, shape),
    );

    return Container(
      // A sombra fica **fora** do recorte: dentro dele seria cortada junto com
      // o resto e a pílula deixaria de flutuar.
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: circle ? null : radius,
        boxShadow: shadow ?? _defaultShadow,
      ),
      child: circle
          ? ClipOval(child: filtered)
          : ClipRRect(borderRadius: radius, child: filtered),
    );
  }

  /// Borda clara em cima e quase transparente embaixo — é o que lê como
  /// **espessura**, enquanto a borda branca uniforme lê como contorno.
  ///
  /// São dois containers porque `Border.all` só aceita cor sólida: o de fora
  /// carrega o gradiente e o de dentro o preenchimento, separados por
  /// [_border].
  Widget _bordered(BorderRadius radius, BoxShape shape) {
    return Container(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: circle ? null : radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.75),
            Colors.white.withValues(alpha: 0.15),
          ],
        ),
      ),
      padding: const EdgeInsets.all(_border),
      child: Container(
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: circle ? null : radius,
          color: Colors.white.withValues(alpha: opacity),
        ),
        child: Stack(
          children: [
            // Pintado antes do filho: o brilho é a superfície, o conteúdo fica
            // sobre ela. Por cima, clarearia os ícones.
            Positioned.fill(child: _specular(radius, shape)),
            Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ],
        ),
      ),
    );
  }

  /// Brilho especular no topo — o detalhe que mais dá sensação de vidro, e o
  /// mais barato: é um gradiente **estático**, não repinta durante o scroll.
  ///
  /// O `IgnorePointer` é **defensivo**, não carrega peso hoje: `DecoratedBox`
  /// não faz hit test de si mesmo, então esta camada já não roubaria toque
  /// sozinha (verificado removendo-o — o teste de toque continuou passando).
  ///
  /// Ele fica porque a edição que quebraria isto é banal: trocar `DecoratedBox`
  /// por `Container(color:)` ou por um `AnimatedContainer` para animar o brilho
  /// põe de pé uma camada que cobre a barra inteira e engole o toque dos
  /// ícones — a barra ficaria bonita e não navegaria.
  Widget _specular(BorderRadius radius, BoxShape shape) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: circle ? null : radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.45),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, 0.45],
          ),
        ),
      ),
    );
  }

  static const _defaultShadow = [
    BoxShadow(
      color: Color(0x1F000000), // preto a 12%
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}
