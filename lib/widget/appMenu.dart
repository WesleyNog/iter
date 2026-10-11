import 'package:flutter/material.dart';

/// O menu "⋮"/"⋯" do app: branco, cantos de 18, cada item com o ícone num
/// quadrado de cantos suaves.
///
/// Nasceu no menu da conta e passou a servir também o do post e o do
/// comentário. Três menus montando a mesma superfície à mão divergem na
/// primeira vez que alguém ajusta um só — é a deriva que o `GlassSurface`
/// fechou para o vidro.
PopupMenuButton<T> appMenuButton<T>({
  Key? key,
  required String tooltip,
  required Widget icon,
  required PopupMenuItemBuilder<T> itemBuilder,
  required PopupMenuItemSelected<T> onSelected,
  bool enabled = true,
  EdgeInsetsGeometry padding = const EdgeInsets.all(8),
}) {
  return PopupMenuButton<T>(
    key: key,
    tooltip: tooltip,
    enabled: enabled,
    padding: padding,
    onSelected: onSelected,
    itemBuilder: itemBuilder,
    icon: icon,
    // Embaixo do botão, e não por cima dele: o menu abria tapando o próprio
    // botão e o que estava ao lado.
    position: PopupMenuPosition.under,
    offset: const Offset(0, 6),
    // Branco de verdade. O Material 3 tinge o menu com a cor primária do tema
    // — o lilás do `deepPurple` —, e era isso que o deixava acinzentado ao
    // lado do branco das abas, dos cards e do vidro.
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 10,
    shadowColor: const Color(0x400D47A1),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    menuPadding: const EdgeInsets.symmetric(vertical: 6),
    constraints: const BoxConstraints(minWidth: 220),
  );
}

/// Um item do menu: ícone num quadrado tingido e o rótulo na mesma cor.
///
/// [ink] e [tile] vêm de quem chama porque o significado é dele: cinza para o
/// que se desfaz, a cor de erro do tema para o que não volta.
PopupMenuItem<T> appMenuItem<T>({
  Key? key,
  required T value,
  required IconData icon,
  required String label,
  required Color ink,
  required Color tile,
}) {
  return PopupMenuItem<T>(
    key: key,
    value: value,
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tile,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: ink),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

/// As duas tintas de item que o app usa: a neutra e a de perigo.
({Color ink, Color tile}) appMenuNeutral() =>
    (ink: Colors.grey.shade800, tile: Colors.grey.shade100);

({Color ink, Color tile}) appMenuDanger(BuildContext context) {
  final error = Theme.of(context).colorScheme.error;
  return (ink: error, tile: error.withValues(alpha: 0.1));
}
