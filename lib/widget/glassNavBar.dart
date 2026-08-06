import 'package:flutter/material.dart';
import 'package:iter/widget/glassSurface.dart';

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
      shadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
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
  static const Color _accent = Color(0xFF1976D2); // azul da marca
  static const double _height = 64;
  static const double _radius = 32;

  /// Deslize do marcador e reação do ícone na mesma duração e curva: são a
  /// mesma transição vista de dois jeitos, e tempos diferentes fariam a barra
  /// parecer dessincronizada.
  static const Duration _motion = Duration(milliseconds: 300);
  static const Curve _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    // Sem blur nem opacidade próprios: a barra é o material padrão do app.
    final Widget pill = GlassSurface(
      borderRadius: BorderRadius.circular(_radius),
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final n = items.length;
            final slot = constraints.maxWidth / n;
            const indicatorH = 44.0;
            final indicatorW = (slot - 24).clamp(48.0, 88.0);
            final left = currentIndex * slot + (slot - indicatorW) / 2;
            const top = (_height - indicatorH) / 2;

            return Stack(
              children: [
                // Marcador azul que desliza horizontalmente entre os itens.
                AnimatedPositioned(
                  duration: _motion,
                  curve: _curve,
                  left: left,
                  top: top,
                  width: indicatorW,
                  height: indicatorH,
                  child: _indicator(),
                ),
                Positioned.fill(
                  child: Row(children: List.generate(n, _buildItem)),
                ),
              ],
            );
          },
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

  /// Gradiente curto e sombra rente: o marcador passa a parecer **apoiado
  /// sobre** o vidro, em vez de recortado nele.
  Widget _indicator() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_accent, Color.lerp(_accent, Colors.black, 0.14)!],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(int index) {
    final selected = index == currentIndex;

    // Cor do ícone faz cross-fade (branco quando sobre o marcador, azul fora)
    // em sincronia com o deslize.
    Widget icon = TweenAnimationBuilder<Color?>(
      duration: _motion,
      curve: _curve,
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
            curve: _curve,
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
  final double blur;
  final String? tooltip;

  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor = const Color(0xFF1976D2),
    this.size = 64,
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
            child: Center(child: Icon(icon, color: iconColor, size: 32)),
          ),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
