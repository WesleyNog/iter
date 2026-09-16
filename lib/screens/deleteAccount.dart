import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iter/services/authService.dart';
import 'package:iter/widget/notificationPush.dart';

/// Excluir a conta. Ver `docs/specs/exclusao-de-conta.md`.
///
/// Diz o que some e o que fica **antes** de pedir qualquer coisa: a lista do
/// que continua é curta, mas é a parte que alguém descobriria depois e com
/// razão chamaria de pegadinha.
///
/// O botão só acende depois da caixa marcada, e o Google ainda pede a conta de
/// novo — dois gestos deliberados para uma coisa que não tem volta.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    required this.email,
    this.onDelete = GoogleSignInService.deleteAccount,
  });

  /// A conta Google que o seletor vai pedir, para a pessoa não escolher outra.
  final String? email;

  /// `false` quando a pessoa desiste no seletor. Injetável para o teste de
  /// widget não depender do Firebase.
  final Future<bool> Function() onDelete;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _understood = false;
  bool _deleting = false;

  Future<void> _delete() async {
    // Capturado antes do `await`: depois do sucesso esta tela sai da pilha e o
    // `context` dela deixa de valer para mostrar qualquer coisa.
    final navigator = Navigator.of(context);
    setState(() => _deleting = true);

    try {
      final deleted = await widget.onDelete();
      if (!deleted) {
        if (mounted) setState(() => _deleting = false);
        return;
      }

      // O `AuthGate` já trocou a Home pelo login — **embaixo** desta tela, que
      // foi empilhada com `push`. Sem o `popUntil`, a pessoa ficaria olhando a
      // tela de uma conta que não existe mais.
      navigator.popUntil((route) => route.isFirst);

      // O aviso vai no contexto do Navigator, que continua de pé.
      final rootContext = navigator.context;
      if (!rootContext.mounted) return;
      showNotification(
        context: rootContext,
        type: 'success',
        msg: 'Conta excluída.',
      );
    } catch (e) {
      debugPrint('exclusão de conta falhou: $e');
      if (!mounted) return;
      setState(() => _deleting = false);
      showNotification(
        context: context,
        type: 'error',
        msg: deleteAccountErrorMessage(e, email: widget.email),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Excluir conta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Isso apaga a sua conta do iter, e não tem volta.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            const _Section(
              title: 'O que é apagado',
              icon: Icons.delete_outline,
              items: [
                'Rotas, veículos, abastecimentos e manutenções',
                'Seu perfil, o @apelido e as estatísticas',
                'Amizades, convites e bloqueios',
                'Suas curtidas e seus comentários',
                'Suas publicações e as fotos delas somem do mural',
              ],
            ),
            const SizedBox(height: 16),
            const _Section(
              title: 'O que continua, sem identificar você',
              icon: Icons.visibility_off_outlined,
              items: [
                'Os preços que você informou nos postos, que ajudam a média '
                    'de todo mundo',
                'As denúncias que você fez, para a moderação',
              ],
            ),
            if (widget.email != null) ...[
              const SizedBox(height: 20),
              Text(
                'Para confirmar, o Google vai pedir a conta ${widget.email}.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const ValueKey('entendo-exclusao'),
              value: _understood,
              onChanged: _deleting
                  ? null
                  : (value) => setState(() => _understood = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Entendo que isso não pode ser desfeito'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('excluir-conta'),
                style: FilledButton.styleFrom(
                  backgroundColor: danger,
                  foregroundColor: theme.colorScheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _understood && !_deleting ? _delete : null,
                icon: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_forever),
                label: const Text('Excluir minha conta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4),
            child: Text('• $item', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// A frase de cada falha.
///
/// Todas terminam dizendo que a conta **não** foi excluída, e isso é verdade
/// em todos os casos: a única escrita que apaga é o `user.delete()`, e ele é o
/// último passo — o que falha antes dele não apagou nada, e ele mesmo falhando
/// não apaga.
String deleteAccountErrorMessage(Object error, {String? email}) {
  const unchanged = 'Sua conta não foi excluída.';

  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'user-mismatch':
        return 'Essa não é a conta Google do seu perfil. '
            'Escolha ${email ?? 'a mesma conta'}. $unchanged';
      case 'network-request-failed':
        return 'Sem conexão. $unchanged Tente de novo quando tiver sinal.';
      case 'requires-recent-login':
        return 'O Google pediu para confirmar de novo. $unchanged '
            'Tente mais uma vez.';
    }
  }

  return 'Não foi possível excluir a conta. $unchanged Tente novamente.';
}
