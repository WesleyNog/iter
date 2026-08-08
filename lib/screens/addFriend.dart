import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/friendship.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/controller/friendController.dart';
import 'package:iter/controller/nicknameController.dart';
import 'package:iter/controller/profileController.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/profileDialog.dart';

/// Busca de amigo pelo `@apelido` exato.
///
/// **Só o apelido exato, de propósito.** Buscar por nome listaria todos os
/// "Wesley" da plataforma, e a lista de resultados seria um diretório de
/// entregadores para qualquer um folhear. Aqui, sem o apelido não há resultado
/// — e `nicknames` tem `list` fechado justamente para o dump não substituir a
/// busca. Ver `docs/specs/amigos.md`.
class AddFriend extends StatefulWidget {
  const AddFriend({super.key, required this.uid});

  final String uid;

  @override
  State<AddFriend> createState() => _AddFriendState();
}

class _AddFriendState extends State<AddFriend> {
  final _controller = TextEditingController();

  FriendshipStatus _status = FriendshipStatus.vazio;
  PublicProfile? _found;
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final typed = _controller.text;

    if (typed.trim().isEmpty) {
      setState(() {
        _status = FriendshipStatus.vazio;
        _found = null;
      });
      return;
    }

    // Nem `resolveUid` nem `isAvailable` normalizam. Sem isto, `Maria.S7`
    // bateria em `nicknames/Maria.S7` — documento que não existe — e a tela
    // diria "ninguém usa esse apelido" para um apelido que existe.
    final nickname = searchableNickname(typed);
    if (nickname == null) {
      setState(() {
        _status = FriendshipStatus.apelidoInvalido;
        _found = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _found = null;
    });

    try {
      final uid = await NicknameController.resolveUid(nickname);
      if (!mounted) return;

      if (uid == null) {
        setState(() {
          _status = FriendshipStatus.naoEncontrado;
          _searching = false;
        });
        return;
      }

      final profile = await ProfileController.fetch(uid);
      if (!mounted) return;

      // As três de uma vez: são independentes, e em série custariam três
      // idas à rede para desenhar um botão só.
      final relations = await Future.wait([
        _has(FriendController.friendsOf(widget.uid), uid),
        _has(FriendController.outgoingOf(widget.uid), uid),
        _has(FriendController.incomingOf(widget.uid), uid),
      ]);
      if (!mounted) return;

      final status = resolveFriendship(
        isMe: uid == widget.uid,
        hasProfile: profile != null,
        isFriend: relations[0],
        invitedByMe: relations[1],
        invitedMe: relations[2],
      );

      setState(() {
        _status = status;
        _found = profile;
        _searching = false;
      });
    } catch (e) {
      debugPrint('busca de amigo falhou: $e');
      if (!mounted) return;
      // Sem rede, regra não publicada e apelido inexistente são **coisas
      // diferentes**. Colapsar os três em "não encontrado" é a mesma mentira
      // do sol desenhado quando a API do clima caía.
      setState(() {
        _status = FriendshipStatus.falha;
        _searching = false;
      });
    }
  }

  Future<bool> _has(
    CollectionReference<Map<String, dynamic>> collection,
    String id,
  ) async {
    return (await collection.doc(id).get()).exists;
  }

  void _openProfile() {
    final profile = _found;
    if (profile == null) return;

    final label = _status.actionLabel;

    showProfileDialog(
      context,
      name: profile.name,
      nickName: profile.nickName,
      photoUrl: profile.photoUrl,
      stats:
          ProfileController.fetchCareer(profile.uid).then(
            (stats) => stats ?? const ProfileStats(
              routes: 0,
              deliveredPackages: 0,
              stops: 0,
            ),
          ),
      // Sem ação possível o botão nasce desabilitado — `null` no `onPressed`,
      // não um callback vazio que pareceria não funcionar.
      actionLabel: label ?? 'Você',
      onAction: label == null ? null : () => _act(profile.uid),
    );
  }

  Future<void> _act(String otherUid) async {
    final status = _status;
    Navigator.of(context).pop();

    final ok = await FriendController.tryRun(() {
      return switch (status) {
        FriendshipStatus.semRelacao => FriendController.invite(
          from: widget.uid,
          to: otherUid,
        ),
        FriendshipStatus.convidou => FriendController.accept(
          me: widget.uid,
          other: otherUid,
        ),
        FriendshipStatus.convidado => FriendController.cancel(
          me: widget.uid,
          other: otherUid,
        ),
        FriendshipStatus.amigo => FriendController.remove(
          me: widget.uid,
          other: otherUid,
        ),
        _ => Future<void>.value(),
      };
    });

    if (!mounted) return;

    if (!ok) {
      // A falha não muda o rótulo do botão: o estado volta a ser o que era.
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível concluir. Tente de novo.',
      );
      return;
    }

    showNotification(
      context: context,
      type: 'success',
      msg: switch (status) {
        FriendshipStatus.semRelacao => 'Convite enviado.',
        FriendshipStatus.convidou => 'Vocês agora são amigos.',
        FriendshipStatus.convidado => 'Convite cancelado.',
        FriendshipStatus.amigo => 'Amizade desfeita.',
        _ => 'Pronto.',
      },
    );

    await _search();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar amigo')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(),
            const SizedBox(height: 20),
            Expanded(child: _result()),
          ],
        ),
      ),
    );
  }

  Widget _field() {
    return TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        prefixText: '@',
        hintText: 'apelido do colega',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: IconButton(
          key: const ValueKey('buscar-amigo'),
          icon: const Icon(Icons.search),
          onPressed: _search,
        ),
      ),
    );
  }

  Widget _result() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }

    final profile = _found;
    if (_status.hasProfile && profile != null) {
      return Align(
        alignment: Alignment.topCenter,
        child: _card(profile),
      );
    }

    final message = _status.message;
    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }

  Widget _card(PublicProfile profile) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        key: const ValueKey('resultado-amigo'),
        onTap: _openProfile,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.blue.shade50,
          backgroundImage: profile.photoUrl == null
              ? null
              : NetworkImage(profile.photoUrl!),
          child: profile.photoUrl != null
              ? null
              : Text(
                  profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        title: Text(
          profile.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: profile.nickName == null
            ? null
            : Text('@${profile.nickName}'),
        trailing: Text(
          _status.actionLabel ?? 'Você',
          style: TextStyle(
            fontSize: 12.5,
            color: _status.actionLabel == null
                ? Colors.grey
                : Colors.blue.shade700,
          ),
        ),
      ),
    );
  }
}
