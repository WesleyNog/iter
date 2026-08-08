import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/post.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/model/publicProfile.dart';

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
    required this.isMine,
    required this.onLike,
    this.onDelete,
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
  final bool isMine;
  final ValueChanged<bool> onLike;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('post-${post.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          if (post.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(post.text, style: const TextStyle(fontSize: 14.5)),
            ),
          if (post.hasImage) _image(),
          _actions(),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final name = displayName(author);
    final photo = author?.photoUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.blue.shade50,
            // Cacheado em disco, como a foto do post: o avatar é justamente a
            // imagem que se repete, e `NetworkImage` só guarda em memória.
            backgroundImage: hasPhoto(photo)
                ? CachedNetworkImageProvider(photo!)
                : null,
            child: hasPhoto(photo)
                ? null
                : Text(
                    displayInitial(name),
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
                Text(
                  _when(post.createdAt),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (post.company != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Image.asset(
                companyLogo(post.company!),
                height: 18,
                // Ícone, não nada: sumir faria "post da Shopee com asset
                // faltando" ficar idêntico a "post sem empresa". É o mesmo
                // fallback do routeCard e do companySummaryCard.
                errorBuilder: (_, _, _) => Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          if (isMine && onDelete != null)
            IconButton(
              key: ValueKey('apagar-${post.id}'),
              tooltip: 'Apagar',
              iconSize: 18,
              icon: Icon(Icons.more_horiz, color: Colors.grey.shade600),
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
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
        color: Colors.grey.shade200,
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
      placeholder: (_, _) => Container(height: 180, color: Colors.grey.shade200),
      errorWidget: (_, _, _) => Container(
        height: 180,
        color: Colors.grey.shade200,
        child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            key: ValueKey('curtir-${post.id}'),
            tooltip: liked ? 'Descurtir' : 'Curtir',
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? Colors.red.shade400 : Colors.grey.shade600,
              size: 20,
            ),
            onPressed: () => onLike(!liked),
          ),
          if (likes > 0)
            Text(
              '$likes',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
        ],
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

  /// `agora`, `há 3h`, `06/08` — a data cheia só quando o post sai da semana.
  static String _when(DateTime at) {
    final diff = DateTime.now().difference(at);

    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays < 7) return 'há ${diff.inDays}d';

    final day = at.day.toString().padLeft(2, '0');
    final month = at.month.toString().padLeft(2, '0');
    return '$day/$month';
  }
}
