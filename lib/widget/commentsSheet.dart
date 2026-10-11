import 'package:flutter/material.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/Utils/relativeTime.dart';
import 'package:iter/controller/blockController.dart';
import 'package:iter/controller/postController.dart';
import 'package:iter/controller/profileController.dart';
import 'package:iter/controller/reportController.dart';
import 'package:iter/model/comment.dart';
import 'package:iter/model/post.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/model/report.dart';
import 'package:iter/widget/appMenu.dart';
import 'package:iter/widget/blockDialog.dart';
import 'package:iter/widget/glassSurface.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/profileAvatar.dart';
import 'package:iter/widget/reportSheet.dart';
import 'package:uuid/uuid.dart';

/// A thread de um post.
///
/// Abre por cima do mural em vez de virar tela: o feed não perde a posição de
/// rolagem, e a contagem do card se corrige quando a folha fecha — o número do
/// servidor não sabe descontar os autores que você bloqueou, e o desta lista
/// sabe. Ver `docs/specs/amigos.md`.
Future<void> showCommentsSheet(
  BuildContext context, {
  required Post post,
  required String uid,
  required Map<String, PublicProfile?> profiles,
  required Set<String> blocked,
  required ValueChanged<int> onCount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Branco, como os cards do mural. O padrão do Material 3 é o lilás claro
    // do tema, e a folha parecia de outro app por cima do feed.
    backgroundColor: Colors.white,
    builder: (_) => _CommentsSheet(
      post: post,
      uid: uid,
      profiles: profiles,
      blocked: blocked,
      onCount: onCount,
    ),
  );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.post,
    required this.uid,
    required this.profiles,
    required this.blocked,
    required this.onCount,
  });

  final Post post;
  final String uid;

  /// O mesmo mapa da `FriendsScreen`, por referência.
  ///
  /// A folha lê o que já está lá e **escreve de volta** o que buscar: um cache
  /// próprio releria perfis que o mural acabou de trazer, e morreria ao fechar.
  final Map<String, PublicProfile?> profiles;

  final Set<String> blocked;

  /// Quantos comentários a folha realmente mostrou.
  final ValueChanged<int> onCount;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  /// Cópia local, e não a do widget: quem eu bloquear com a folha aberta tem de
  /// sumir dela na hora. O `Set` de cima vem de um stream que só repinta a tela
  /// de baixo.
  late final Set<String> _blocked = {...widget.blocked};

  final Set<String> _loadingProfiles = {};

  bool _sending = false;
  int _published = -1;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Avisa o card, uma vez por valor novo e **depois** do frame: mexer no
  /// estado do mural no meio do `build` desta folha é setState durante build.
  void _publish(int count) {
    if (count == _published) return;
    _published = count;

    final notify = widget.onCount;
    WidgetsBinding.instance.addPostFrameCallback((_) => notify(count));
  }

  /// Busca os perfis que faltam e devolve para o mapa compartilhado.
  ///
  /// `List` e não `Iterable` pela mesma razão de `missingProfiles`: `where()`
  /// é preguiçoso e reavaliaria o filtro depois de as marcas serem postas.
  void _prefetch(Iterable<String> uids) {
    final missing = <String>[];
    for (final uid in uids) {
      if (widget.profiles.containsKey(uid)) continue;
      if (_loadingProfiles.contains(uid)) continue;
      missing.add(uid);
    }
    if (missing.isEmpty) return;

    _loadingProfiles.addAll(missing);
    for (final uid in missing) {
      ProfileController.fetch(uid).then((profile) {
        if (!mounted) return;
        setState(() {
          widget.profiles[uid] = profile;
          _loadingProfiles.remove(uid);
        });
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await PostController.comment(
        widget.post.id,
        Comment(
          id: const Uuid().v4(),
          uid: widget.uid,
          text: text,
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      _controller.clear();
      // O stream entrega o próprio comentário na hora, pelo cache local do
      // Firestore; rolar até ele é o que confirma que foi.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      debugPrint('feed: comentário recusado: $e');
      if (!mounted) return;
      // O texto **fica** no campo: quem escreveu não perde o que escreveu
      // porque a rede caiu.
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível comentar. Tente de novo.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Comment comment) async {
    try {
      await PostController.deleteComment(
        postId: widget.post.id,
        commentId: comment.id,
      );
    } catch (e) {
      debugPrint('feed: não foi possível apagar o comentário: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível apagar. Tente de novo.',
      );
    }
  }

  Future<void> _report(Comment comment) async {
    final reason = await showReportSheet(context, isComment: true);
    if (reason == null || !mounted) return;

    try {
      await ReportController.send(
        Report(
          uid: widget.uid,
          postId: widget.post.id,
          commentId: comment.id,
          reason: reason,
        ),
      );
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'success',
        msg: 'Denúncia enviada. Obrigado.',
      );
    } catch (e) {
      debugPrint('feed: denúncia recusada: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível enviar a denúncia.',
      );
    }
  }

  Future<void> _block(String otherUid) async {
    final name = displayName(widget.profiles[otherUid]);
    final ok = await confirmBlock(context, name: name);
    if (ok != true || !mounted) return;

    try {
      await BlockController.block(me: widget.uid, other: otherUid);
      if (!mounted) return;
      setState(() => _blocked.add(otherUid));
      showNotification(
        context: context,
        type: 'success',
        msg: '$name foi bloqueado.',
      );
    } catch (e) {
      debugPrint('feed: bloqueio recusado: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível bloquear agora.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // O teclado empurra a folha em vez de cobrir o campo.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Comentários',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: _line),
            Expanded(child: _thread()),
            const Divider(height: 1, thickness: 1, color: _line),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _thread() {
    return StreamBuilder<List<Comment>>(
      stream: PostController.watchComments(widget.post.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Falha de regra do Firestore já sumiu silenciosamente neste projeto
          // antes.
          debugPrint('feed: thread indisponível: ${snapshot.error}');
          return _aviso('Não foi possível carregar os comentários.');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final comments = [
          for (final comment in snapshot.data ?? const <Comment>[])
            if (!_blocked.contains(comment.uid)) comment,
        ];

        _publish(comments.length);
        _prefetch([for (final comment in comments) comment.uid]);

        if (comments.isEmpty) {
          return _aviso('Ninguém comentou ainda. Diga alguma coisa.');
        }

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          itemCount: comments.length,
          itemBuilder: (context, index) => _tile(comments[index]),
        );
      },
    );
  }

  /// Um comentário: o avatar e um balão com o nome e o texto, e o "quando"
  /// embaixo do balão.
  ///
  /// O balão é o que separa um comentário do outro sem divisória — antes os
  /// nomes e os textos corriam numa coluna só, e numa thread de dez linhas
  /// não se via onde terminava cada um. O seu sai em azul-claro, como a sua
  /// linha no Ranking: achar-se na conversa não depende de ler os nomes.
  Widget _tile(Comment comment) {
    final author = widget.profiles[comment.uid];
    final name = displayName(author);
    final isMine = comment.uid == widget.uid;

    // O dono do post modera a própria thread: é a única moderação que existe
    // sem servidor, e é a diferença entre curtida e comentário.
    final canDelete = isMine || widget.post.uid == widget.uid;

    return Padding(
      key: ValueKey('comentario-${comment.id}'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(profile: author, radius: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  decoration: BoxDecoration(
                    color: isMine ? Colors.blue.shade50 : Colors.grey.shade100,
                    // O canto de cima à esquerda quase reto aponta para o
                    // avatar: o balão sai da pessoa.
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        comment.text,
                        style: const TextStyle(fontSize: 14.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
                  child: Text(
                    relativeWhen(comment.createdAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _menu(comment, isMine: isMine, canDelete: canDelete),
        ],
      ),
    );
  }

  Widget _menu(
    Comment comment, {
    required bool isMine,
    required bool canDelete,
  }) {
    final neutral = appMenuNeutral();
    final danger = appMenuDanger(context);

    return appMenuButton<String>(
      key: ValueKey('menu-comentario-${comment.id}'),
      tooltip: 'Opções',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey.shade500),
      itemBuilder: (_) => [
        if (canDelete)
          appMenuItem(
            key: const ValueKey('apagar-comentario'),
            value: 'apagar',
            icon: Icons.delete_outline_rounded,
            label: 'Apagar',
            ink: danger.ink,
            tile: danger.tile,
          ),
        if (!isMine) ...[
          appMenuItem(
            key: const ValueKey('denunciar-comentario'),
            value: 'denunciar',
            icon: Icons.flag_outlined,
            label: 'Denunciar',
            ink: neutral.ink,
            tile: neutral.tile,
          ),
          appMenuItem(
            key: const ValueKey('bloquear-comentario'),
            value: 'bloquear',
            icon: Icons.block_rounded,
            label: 'Bloquear',
            ink: danger.ink,
            tile: danger.tile,
          ),
        ],
      ],
      onSelected: (action) => switch (action) {
        'apagar' => _delete(comment),
        'denunciar' => _report(comment),
        'bloquear' => _block(comment.uid),
        _ => null,
      },
    );
  }

  /// O campo numa pílula cinza e o enviar num círculo azul — o mesmo azul do
  /// indicador das abas. Antes era texto solto sobre a folha, com uma seta
  /// cinza que não parecia botão nem quando estava ligada.
  Widget _composer() {
    final canSend = _controller.text.trim().isNotEmpty && !_sending;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('campo-comentario'),
                controller: _controller,
                maxLength: Comment.maxLength,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Escreva um comentário',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  // O teto da regra não pode virar surpresa no envio, mas o
                  // contador em cima de cada comentário seria ruído: só
                  // aparece quando o texto se aproxima do limite.
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Enviar',
              child: Material(
                color: canSend || _sending
                    ? GlassIndicator.accent
                    : Colors.grey.shade300,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const ValueKey('enviar-comentario'),
                  customBorder: const CircleBorder(),
                  onTap: canSend ? _send : null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aviso(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 36,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

/// O traço das divisórias da folha: o mesmo das seções e do card do post.
const _line = Color(0xFFEEE9F2);
