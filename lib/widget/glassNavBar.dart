import 'dart:ui';
import 'package:flutter/material.dart';

/// Item da barra de navegação glass.
class GlassNavItem {
  final IconData icon;
  final String label;
  const GlassNavItem({required this.icon, required this.label});
}

/// "Pílula" de vidro reutilizável (mesmo efeito da barra). Envolve qualquer
/// widget num fundo translúcido com blur do conteúdo atrás.
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
    this.blur = 18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Barra de navegação inferior em "vidro" (liquid glass), como pílula flutuante.
///
/// O efeito é renderizado pelo próprio Flutter (`BackdropFilter` + `ImageFilter.blur`),
/// então funciona igual no Android e no iOS. Para o blur captar o conteúdo, o
/// `Scaffold` que a usa deve ter `extendBody: true`.
class GlassNavBar extends StatelessWidget {
  final List<GlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Quantidade exibida no badge de pendentes (0 = oculto).
  final int pendingCount;

  /// Índice do item que recebe o badge de pendentes (-1 = nenhum).
  final int pendingIndex;

  /// Botão opcional ao lado da barra (ex.: FAB de nova venda), na mesma linha.
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
  static const double _blur = 18;
  static const double _height = 64;
  static const double _radius = 32;
  static const double _glassOpacity = 0.55; // opacidade do vidro claro

  @override
  Widget build(BuildContext context) {
    final Widget pill = ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_glassOpacity),
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
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
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    left: left,
                    top: top,
                    width: indicatorW,
                    height: indicatorH,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(children: List.generate(n, _buildItem)),
                  ),
                ],
              );
            },
          ),
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
    // em sincronia com o deslize do marcador.
    Widget icon = TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      tween: ColorTween(
        end: selected ? Colors.white : _accent.withOpacity(0.7),
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
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Center(child: icon),
      ),
    );
  }
}

/// Botão circular de vidro (mesmo efeito do GlassPill/GlassNavBar), pensado para
/// ficar ao lado da barra de navegação — ex.: o FAB de "nova venda".
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
    this.blur = 18,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Material(
            color: Colors.white.withOpacity(0.55),
            shape: CircleBorder(
              side: BorderSide(color: Colors.white.withOpacity(0.6), width: 1),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(child: Icon(icon, color: iconColor, size: 32)),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
