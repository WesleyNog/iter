import 'package:flutter/material.dart';
import 'package:iter/widget/glassSurface.dart';
import 'package:iter/widget/slidingIndicator.dart';

/// Item da barra de navegação glass.
class GlassNavItem {
  final IconData icon;

  /// Ainda não é desenhado — a barra é só de ícones. Fica declarado porque é o
  /// texto que entraria se um dia a barra ganhar rótulos.
  final String label;

  const GlassNavItem({required this.icon, required this.label});
}

/// "Pílula" de vidro reutilizável. Envolve qualquer widget no material do app.
///
/// Para o blur captar o conteúdo, quem usa deve deixar o conteúdo passar por
/// trás (ex: `extendBodyBehindAppBar: true`).
class GlassPill extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.radius = 22,
    this.blur = GlassSurface.defaultBlur,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      blur: blur,
      // Sem opacidade própria: usa o padrão do material. O 0,6 que tinha antes
      // era deriva, não escolha.
      borderRadius: BorderRadius.circular(radius),
      padding: padding,
      shadow: GlassSurface.pillShadow,
      child: child,
    );
  }
}

/// Barra de navegação inferior em vidro, como pílula flutuante.
///
/// O efeito é renderizado pelo próprio Flutter (`BackdropFilter`), sem pacote
/// nem shader, então funciona igual no Android e no iOS. Para o blur captar o
/// conteúdo, o `Scaffold` que a usa deve ter `extendBody: true`.
class GlassNavBar extends StatelessWidget {
  final List<GlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Quantidade exibida no badge de pendentes (0 = oculto).
  final int pendingCount;

  /// Índice do item que recebe o badge de pendentes (-1 = nenhum).
  final int pendingIndex;

  /// Botão opcional ao lado da barra (ex.: o "+" de criar), na mesma linha.
  ///
  /// É superfície **irmã**, não filha: aninhá-lo dentro da pílula empilharia
  /// dois `BackdropFilter` e borraria o fundo duas vezes.
  final Widget? trailing;

  const GlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.pendingCount = 0,
    this.pendingIndex = -1,
    this.trailing,
  });

  // ---- Aparência ajustável ----
  static const Color _accent = GlassIndicator.accent;
  static const double _height = 64;
  static const double _radius = 32;
  static const double _indicatorHeight = 44;

  /// A reação do ícone no tempo do marcador: são a mesma transição vista de
  /// dois jeitos, e tempos diferentes fariam a barra parecer dessincronizada.
  /// A curva vem de `SlidingIndicator.contentCurve`, que acende com a borda da
  /// frente e apaga com a de trás.
  static const Duration _motion = SlidingIndicator.total;

  @override
  Widget build(BuildContext context) {
    // Sem blur nem opacidade próprios: a barra é o material padrão do app.
    final Widget pill = GlassSurface(
      borderRadius: BorderRadius.circular(_radius),
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            // O marcador azul, o mesmo indicador das abas do topo de Amigos e
            // do critério do Ranking.
            Positioned(
              left: 0,
              right: 0,
              top: (_height - _indicatorHeight) / 2,
              height: _indicatorHeight,
              child: SlidingIndicator(
                count: items.length,
                index: currentIndex,
                widthFor: (slot) => (slot - 24).clamp(48.0, 88.0),
                child: const GlassIndicator(),
              ),
            ),
            Positioned.fill(
              child: Row(children: List.generate(items.length, _buildItem)),
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: trailing == null
            ? pill
            : Row(
                children: [
                  Expanded(child: pill),
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ),
      ),
    );
  }

  Widget _buildItem(int index) {
    final selected = index == currentIndex;

    // Cor do ícone faz cross-fade (branco quando sobre o marcador, azul fora)
    // em sincronia com o deslize. O que sai espera a borda de trás: azul antes
    // de o marcador sair de baixo dele seria azul sobre azul.
    final curve = SlidingIndicator.contentCurve(on: selected);
    Widget icon = TweenAnimationBuilder<Color?>(
      duration: _motion,
      curve: curve,
      tween: ColorTween(
        end: selected ? Colors.white : _accent.withValues(alpha: 0.7),
      ),
      builder: (context, color, _) =>
          Icon(items[index].icon, size: 26, color: color),
    );

    if (pendingIndex == index && pendingCount > 0) {
      icon = Badge(
        backgroundColor: Colors.red.shade500,
        label: Text(
          pendingCount.toString(),
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        child: icon,
      );
    }

    return Expanded(
      child: GestureDetector(
        // `opaque`: o ícone não preenche o slot, e sem isto o toque no vão
        // entre dois ícones não trocaria de aba.
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Center(
          // Um crescimento pequeno o bastante para se sentir e não se notar —
          // toque que responde parece toque que funcionou.
          child: AnimatedScale(
            scale: selected ? 1.06 : 1,
            duration: _motion,
            curve: curve,
            child: icon,
          ),
        ),
      ),
    );
  }
}

/// Botão circular de vidro, pensado para ficar ao lado da barra — o "+".
class GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final double size;

  /// Metade do diâmetro, no padrão: o "+" de 64 leva 32. O botão de filtros da
  /// Lista, de 48 para alinhar com o trilho, pede um ícone menor.
  final double iconSize;

  final double blur;
  final String? tooltip;

  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor = const Color(0xFF1976D2),
    this.size = 64,
    this.iconSize = 32,
    this.blur = GlassSurface.defaultBlur,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = GlassSurface(
      blur: blur,
      circle: true,
      shadow: const [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
      child: SizedBox(
        width: size,
        height: size,
        // `Material` transparente: o vidro já é o fundo, e uma cor aqui
        // taparia o blur que o `GlassSurface` acabou de aplicar.
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Icon(icon, color: iconColor, size: iconSize),
            ),
          ),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Botão quadrado de vidro, de cantos suaves — o do veículo, na `AppBar`.
///
/// O "+" é redondo porque é ação; este é quadrado porque mostra uma **coisa**
/// (o carro em uso), e uma imagem larga de carro dentro de um círculo ficava
/// pequena no meio de um disco cinza. Mesmo material das abas e do trilho de
/// empresas, na opacidade de superfície com conteúdo para ler.
class GlassTileButton extends StatelessWidget {
  const GlassTileButton({
    super.key,
    required this.child,
    required this.onTap,
    this.size = 44,
    this.radius = 14,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final double size;
  final double radius;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);

    final button = GlassSurface(
      opacity: 0.75,
      borderRadius: shape,
      // Mais rente que a `pillShadow`: o botão mora na `AppBar`, que recorta o
      // que passa da altura dela. Com 12 de desfoque e 4 de deslocamento a
      // sombra descia além dos 6 px que sobram embaixo e era cortada numa
      // linha reta — visto no iPhone.
      shadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 6,
          offset: Offset(0, 1),
        ),
      ],
      // Menos a borda de 1 px do vidro dos dois lados: [size] é o botão
      // inteiro, que é o que alinha com o resto da `AppBar`.
      child: SizedBox(
        width: size - 2,
        height: size - 2,
        // `Material` transparente pelo mesmo motivo do `GlassCircleButton`: o
        // vidro já é o fundo, e o toque precisa de onde pintar por cima dele.
        child: Material(
          color: Colors.transparent,
          borderRadius: shape,
          child: InkWell(
            borderRadius: shape,
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
