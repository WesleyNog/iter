import 'package:flutter/material.dart';
import 'package:iter/model/publicProfile.dart';

/// Uma linha da lista de amigos ou da caixa de convites.
///
/// Recebe o perfil em vez de buscá-lo: uma leitura por tile seria N idas ao
/// Firestore a cada rolagem, e montar stream dentro do `build` é a armadilha
/// que este projeto já registrou. Quem lista faz **um** prefetch.
///
/// [profile] em `null` significa **projeção ainda não publicada** — o estado
/// de quem já usava o app antes desta entrega e não reabriu, ou de uma conta
/// apagada do lado do Google. Aí a linha desenha o `@apelido` e uma inicial
/// genérica, nunca espaço em branco.
class FriendTile extends StatelessWidget {
  const FriendTile({
    super.key,
    required this.uid,
    required this.profile,
    this.nickNameFallback,
    this.onTap,
    this.trailing,
  });

  final String uid;
  final PublicProfile? profile;
  final String? nickNameFallback;
  final VoidCallback? onTap;
  final Widget? trailing;

  String get _name {
    final name = profile?.name.trim() ?? '';
    if (name.isNotEmpty) return name;

    final nick = profile?.nickName ?? nickNameFallback;
    return nick == null ? 'Entregador' : '@$nick';
  }

  String? get _handle {
    final nick = profile?.nickName ?? nickNameFallback;
    if (nick == null) return null;
    // Sem nome, o apelido já é o título: repetir embaixo seria ruído.
    return (profile?.name.trim().isEmpty ?? true) ? null : '@$nick';
  }

  @override
  Widget build(BuildContext context) {
    final photo = profile?.photoUrl;

    return ListTile(
      key: ValueKey('amigo-$uid'),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.blue.shade50,
        backgroundImage: photo == null ? null : NetworkImage(photo),
        child: photo != null
            ? null
            : Text(
                _name.replaceAll('@', '').characters.firstOrNull
                        ?.toUpperCase() ??
                    '?',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      title: Text(
        _name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: _handle == null
          ? null
          : Text(
              _handle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
      trailing: trailing,
    );
  }
}
