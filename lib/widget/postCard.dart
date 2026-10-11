import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/relativeTime.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/post.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/model/newRouteModal.dart' show Company;
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/appMenu.dart';
import 'package:iter/widget/profileAvatar.dart';
import 'package:iter/widget/sectionCard.dart';

/// Um post no mural.
///
/// Recebe o autor em vez de buscá-lo: o feed faz **um** prefetch de perfis
/// para um `Map`, e uma leitura por card seria N idas à rede a cada rolagem.
/// [author] em `null` é projeção ainda não publicada — desenha o genérico, e
/// nunca linha em branco.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.author,
    required this.imageUrl,
    required this.imageLoading,
    required this.likes,
    required this.liked,
    required this.comments,
    required this.isMine,
    required this.onLike,
    required this.onComment,
    this.onDelete,
    this.onReport,
    this.onBlock,
  });

  final Post post;
  final PublicProfile? author;

  /// URL já resolvida do Storage. `null` com [imageLoading] falso significa
  /// **"não deu para saber"** — foto apagada, sem rede, regra negada.
  ///
  /// Resolvida pela lista e não aqui: montar o `Future` no `build` o refazia
  /// a cada rebuild e a foto voltava ao placeholder a cada curtida.
  final String? imageUrl;
  final bool imageLoading;

  final int likes;
  final bool liked;

  /// Quantos comentários, na abertura da tela. Corrige-se quando a folha da
  /// thread fecha: o `count()` do servidor não sabe descontar quem você
  /// bloqueou, e a lista da folha sabe.
  final int comments;

  final bool isMine;
  final ValueChanged<bool> onLike;
  final VoidCallback onComment;

  /// As três ações do menu. `null` esconde a linha — o dono não se denuncia
  /// nem se bloqueia, e ninguém apaga o post do outro.
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('post-${post.id}'),
      padding: const EdgeInsets.only(bottom: 14),
      // O card branco do placar do Ranking e das seções de Amigos: a aba
      // inteira fala a mesma língua. O cinza-claro de antes sumia contra o
      // fundo lilás e o post parecia solto na tela.
      child: DecoratedBox(
        decoration: SectionCard.decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            if (post.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  post.text,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            if (post.hasImage)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _image(),
                ),
              ),
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFEEE9F2),
            ),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final name = displayName(author);
    final company = post.company;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 12),
      child: Row(
        children: [
          ProfileAvatar(profile: author, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      relativeWhen(post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    // A empresa vai junto do "quando", como selo do post — no
                    // canto direito ela flutuava longe do autor e disputava
                    // lugar com o menu.
                    if (company != null) ...[
                      const SizedBox(width: 8),
                      _companyChip(company),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _menu(context),
        ],
      ),
    );
  }

  Widget _companyChip(Company company) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.asset(
        companyLogo(company),
        height: 13,
        // Ícone, não nada: sumir faria "post da Shopee com asset faltando"
        // ficar idêntico a "post sem empresa". É o mesmo fallback do routeCard
        // e do companySummaryCard.
        errorBuilder: (_, _, _) => Icon(
          Icons.local_shipping_outlined,
          size: 13,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  /// O menu do card.
  ///
  /// Antes desta entrega ele só existia no post **próprio**, e só para apagar:
  /// num post alheio não havia gesto nenhum. Num mural global isso é o mesmo
  /// que dizer que ninguém tem o que reclamar — por isso denunciar e bloquear
  /// nascem aqui, e nascem antes do comentário.
  Widget _menu(BuildContext context) {
    final neutral = appMenuNeutral();
    final danger = appMenuDanger(context);

    final items = <PopupMenuEntry<String>>[
      if (isMine && onDelete != null)
        appMenuItem(
          key: const ValueKey('apagar-post'),
          value: 'apagar',
          icon: Icons.delete_outline_rounded,
          label: 'Apagar publicação',
          ink: danger.ink,
          tile: danger.tile,
        ),
      if (!isMine && onReport != null)
        appMenuItem(
          key: const ValueKey('denunciar-post'),
          value: 'denunciar',
          icon: Icons.flag_outlined,
          label: 'Denunciar publicação',
          ink: neutral.ink,
          tile: neutral.tile,
        ),
      // Bloquear desfaz a amizade e os convites: é do lado que não volta.
      if (!isMine && onBlock != null)
        appMenuItem(
          key: const ValueKey('bloquear-post'),
          value: 'bloquear',
          icon: Icons.block_rounded,
          label: 'Bloquear',
          ink: danger.ink,
          tile: danger.tile,
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return appMenuButton<String>(
      key: ValueKey('menu-${post.id}'),
      tooltip: 'Opções',
      icon: Icon(Icons.more_horiz, size: 20, color: Colors.grey.shade600),
      itemBuilder: (_) => items,
      onSelected: (action) {
        switch (action) {
          case 'apagar':
            _confirmDelete(context);
          case 'denunciar':
            onReport?.call();
          case 'bloquear':
            onBlock?.call();
        }
      },
    );
  }

  Widget _image() {
    final url = imageUrl;

    if (url == null) {
      // Carregando e "não deu para saber" desenham o mesmo espaço: o post
      // continua legível pelo texto, e um erro vermelho no meio do mural
      // seria pior que uma foto que não veio.
      return Container(
        height: 180,
        width: double.infinity,
        color: Colors.grey.shade100,
        child: imageLoading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Icon(
                Icons.image_not_supported_outlined,
                color: Colors.grey.shade400,
              ),
      );
    }

    // `cached_network_image` e não `Image.network`: este só guarda em
    // memória, e fechar o app rebaixaria o mural inteiro — a banda do
    // Storage é o maior custo desta feature.
    return CachedNetworkImage(
      imageUrl: url,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, _) =>
          Container(height: 180, color: Colors.grey.shade100),
      errorWidget: (_, _, _) => Container(
        height: 180,
        color: Colors.grey.shade100,
        child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          _pill(
            key: ValueKey('curtir-${post.id}'),
            tooltip: liked ? 'Descurtir' : 'Curtir',
            onTap: () => onLike(!liked),
            count: likes,
            active: liked,
            // O coração cheio entra crescendo: toque que responde parece
            // toque que funcionou. Só o ícone se move — o número troca seco.
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: child,
              ),
              child: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(liked),
                color: liked ? Colors.red.shade400 : Colors.grey.shade600,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _pill(
            key: ValueKey('comentar-${post.id}'),
            tooltip: 'Comentários',
            onTap: onComment,
            count: comments,
            active: false,
            icon: Icon(
              Icons.mode_comment_outlined,
              color: Colors.grey.shade600,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }

  /// Um botão de ação em pílula: ícone e contagem juntos, e o toque cobre os
  /// dois — antes o número ficava fora do botão e tocar nele não fazia nada.
  ///
  /// Zero não desenha número: "0" debaixo de um post novo é ruído.
  Widget _pill({
    required Key key,
    required String tooltip,
    required VoidCallback onTap,
    required int count,
    required bool active,
    required Widget icon,
  }) {
    final shape = BorderRadius.circular(20);

    return Tooltip(
      message: tooltip,
      child: Material(
        // Curtido, a pílula ganha o vermelho bem claro do coração: o estado
        // se lê de longe, sem depender de distinguir o ícone cheio do vazado.
        color: active ? Colors.red.shade50 : Colors.transparent,
        borderRadius: shape,
        child: InkWell(
          key: key,
          borderRadius: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.red.shade400
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar publicação?'),
        content: const Text('Ela some do mural para todo mundo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (ok == true) onDelete?.call();
  }
}
