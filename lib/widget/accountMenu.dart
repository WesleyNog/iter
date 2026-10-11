import 'package:flutter/material.dart';

/// O que o menu da conta, na `AppBar`, oferece.
enum AccountAction { signOut, delete }

/// O "⋮" da `AppBar` e o menu que ele abre: Sair e Excluir conta.
///
/// Menu e não o botão de sair direto: a Play exige que excluir a conta seja
/// fácil de achar, e ao lado do "Sair" é onde as pessoas procuram. Ver
/// `docs/specs/exclusao-de-conta.md`.
///
/// Saiu da `HomeScreen` para ter teste: aquela tela abre o Firestore no
/// `initState`, e nada que mora dentro dela é alcançável por teste de widget.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key, required this.busy, required this.onSelected});

  /// Saindo da conta: o ícone vira progresso e o menu não abre — um segundo
  /// "Sair" no meio do primeiro não tem o que fazer.
  final bool busy;

  final ValueChanged<AccountAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;

    return PopupMenuButton<AccountAction>(
      key: const ValueKey('menu-conta'),
      tooltip: 'Conta',
      enabled: !busy,
      onSelected: onSelected,
      // Embaixo do botão, e não por cima dele: o menu abria tapando o próprio
      // "⋮" e metade das abas.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      // Branco de verdade. O Material 3 tinge o menu com a cor primária do
      // tema — o lilás do `deepPurple` —, e era isso que o deixava acinzentado
      // ao lado do branco das abas e do vidro.
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: const Color(0x400D47A1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      constraints: const BoxConstraints(minWidth: 220),
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        _item(
          AccountAction.signOut,
          icon: Icons.logout_rounded,
          label: 'Sair',
          ink: Colors.grey.shade800,
          tile: Colors.grey.shade100,
        ),
        // A divisória separa o que se desfaz no próximo login do que não se
        // desfaz nunca: os dois itens colados convidavam o toque errado.
        const PopupMenuDivider(
          height: 9,
          thickness: 1,
          indent: 16,
          endIndent: 16,
          color: Color(0xFFEEE9F2),
        ),
        _item(
          AccountAction.delete,
          icon: Icons.delete_outline_rounded,
          label: 'Excluir conta',
          ink: danger,
          tile: danger.withValues(alpha: 0.1),
        ),
      ],
    );
  }

  /// Ícone num quadrado de cantos suaves, como o botão do veículo ao lado: o
  /// menu fala a mesma língua da `AppBar` que o abriu.
  PopupMenuItem<AccountAction> _item(
    AccountAction value, {
    required IconData icon,
    required String label,
    required Color ink,
    required Color tile,
  }) {
    return PopupMenuItem(
      key: ValueKey('menu-conta-${value.name}'),
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
}
