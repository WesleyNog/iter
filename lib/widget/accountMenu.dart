import 'package:flutter/material.dart';
import 'package:iter/widget/appMenu.dart';

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
/// A superfície do menu é a de `appMenu.dart`, a mesma do post e do
/// comentário.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key, required this.busy, required this.onSelected});

  /// Saindo da conta: o ícone vira progresso e o menu não abre — um segundo
  /// "Sair" no meio do primeiro não tem o que fazer.
  final bool busy;

  final ValueChanged<AccountAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final neutral = appMenuNeutral();
    final danger = appMenuDanger(context);

    return appMenuButton<AccountAction>(
      key: const ValueKey('menu-conta'),
      tooltip: 'Conta',
      enabled: !busy,
      onSelected: onSelected,
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        appMenuItem(
          key: const ValueKey('menu-conta-signOut'),
          value: AccountAction.signOut,
          icon: Icons.logout_rounded,
          label: 'Sair',
          ink: neutral.ink,
          tile: neutral.tile,
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
        appMenuItem(
          key: const ValueKey('menu-conta-delete'),
          value: AccountAction.delete,
          icon: Icons.delete_outline_rounded,
          label: 'Excluir conta',
          ink: danger.ink,
          tile: danger.tile,
        ),
      ],
    );
  }
}
