import 'package:flutter/material.dart';

/// A confirmação do bloqueio, escrita uma vez.
///
/// Existe como arquivo próprio porque três telas a chamam — o card do mural, a
/// folha de comentários e a lista de amigos — e bloquear **apaga a amizade e os
/// convites**. Uma frase que avisa disso em três versões seria três avisos
/// diferentes sobre a mesma consequência. Ver `docs/specs/amigos.md`.
Future<bool?> confirmBlock(BuildContext context, {required String name}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Bloquear $name?'),
      content: const Text(
        'Vocês deixam de ser amigos, os convites entre vocês somem e essa '
        'pessoa não vai mais conseguir te convidar nem comentar nas suas '
        'publicações.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: const ValueKey('confirmar-bloqueio'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Bloquear'),
        ),
      ],
    ),
  );
}
