import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:iter/controller/postController.dart';
import 'package:iter/model/post.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/screens/addPost.dart';
import 'package:iter/services/postImage.dart';
import 'package:iter/widget/postCard.dart';

/// O mural: o que todos os entregadores publicaram.
///
/// Página de 20, `get()` com puxar-para-baixo em vez de `snapshots()` — um
/// listener no mural reentrega o documento a cada curtida de qualquer pessoa,
/// e cada reentrega é leitura cobrada. Ver `docs/specs/amigos.md`.
///
/// Os perfis dos autores vêm da `FriendsScreen`, no mesmo mapa que a lista de
/// amigos e o ranking usam. Um cache próprio aqui morreria a cada troca de aba
/// e releria perfis que o mapa de cima já tinha.
class FeedTab extends StatefulWidget {
  const FeedTab({
    super.key,
    required this.uid,
    required this.profiles,
    required this.onNeedProfiles,
    required this.bottomGap,
  });

  final String uid;
  final Map<String, PublicProfile?> profiles;
  final ValueChanged<Iterable<String>> onNeedProfiles;
  final double bottomGap;

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  /// Quantas páginas seguidas de tombstone o feed atravessa sozinho antes de
  /// desistir. Sem teto, um mural com mil apagados viraria uma corrente de
  /// leituras bloqueante na abertura.
  static const int _maxChainedPages = 5;

  final _posts = <Post>[];
  final _likes = <String, int>{};
  final _liked = <String>{};

  /// URL resolvida do Storage, por post.
  ///
  /// Fica aqui e **não** no card: montar o `Future` dentro do `build` o refaz
  /// a cada rebuild, e o `FutureBuilder` volta ao estado de carregando — a
  /// foto piscava a cada curtida e a cada perfil que chegava, e o cache de
  /// disco nunca era consultado porque a própria URL era resolvida de novo.
  final _imageUrls = <String, String?>{};

  /// Curtidas que o usuário mexeu e cuja escrita ainda não assentou.
  ///
  /// O merge de `_fetchLikes` pula estes ids: sem isso, uma contagem lida
  /// **antes** do toque sobrescreve o otimismo e o coração fica cheio com o
  /// número escondido.
  final _dirtyLikes = <String>{};

  final _scroll = ScrollController();

  DocumentSnapshot? _last;
  bool _loading = false;
  bool _done = false;
  bool _failed = false;

  /// Invalida o que está em voo.
  ///
  /// Sem isto, puxar para atualizar durante uma carga descartava o refresh
  /// (o guard `_loading` barrava) e deixava a página em voo aterrissar sobre
  /// a lista já limpa: o mural passava a começar no post 21 e os mais
  /// recentes ficavam inalcançáveis.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 400) _load();
  }

  Future<void> _refresh() async {
    setState(() {
      _generation++;
      _posts.clear();
      _imageUrls.clear();
      _last = null;
      _done = false;
      _loading = false;
      _failed = false;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    final gen = _generation;

    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      // Atravessa páginas inteiras de tombstone sem devolver o controle: se
      // os 20 mais recentes estão apagados, a lista fica vazia e nenhum
      // evento de rolagem pediria a página seguinte. O mural mentiria
      // "ninguém publicou ainda" sobre uma coleção cheia.
      final fresh = <Post>[];
      var pages = 0;

      while (pages < _maxChainedPages && !_done) {
        final snapshot = await PostController.page(after: _last);
        if (!mounted || gen != _generation) return;

        pages++;
        if (snapshot.docs.length < PostController.pageSize) _done = true;
        if (snapshot.docs.isNotEmpty) _last = snapshot.docs.last;

        fresh.addAll(PostController.parse(snapshot));
        if (fresh.isNotEmpty) break;
      }

      setState(() {
        _posts.addAll(fresh);
        _loading = false;
      });

      widget.onNeedProfiles([for (final post in fresh) post.uid]);
      await _fetchMedia(fresh, gen);
      await _fetchLikes(fresh, gen);
    } catch (e) {
      debugPrint('feed: não foi possível carregar: $e');
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _fetchMedia(List<Post> page, int gen) async {
    final withImage = [
      for (final post in page)
        if (post.hasImage) post,
    ];
    if (withImage.isEmpty) return;

    final urls = await Future.wait(
      withImage.map((post) => PostImage.urlFor(post.imagePath!)),
    );
    if (!mounted || gen != _generation) return;

    setState(() {
      for (var i = 0; i < withImage.length; i++) {
        _imageUrls[withImage[i].id] = urls[i];
      }
    });
  }

  Future<void> _fetchLikes(List<Post> page, int gen) async {
    final ids = [for (final post in page) post.id];
    if (ids.isEmpty) return;

    final counts = await Future.wait(ids.map(PostController.likeCount));
    final mine = await PostController.likedAmong(ids, widget.uid);
    if (!mounted || gen != _generation) return;

    setState(() {
      for (var i = 0; i < ids.length; i++) {
        // O que o usuário acabou de tocar manda: o número do servidor foi
        // lido antes da escrita e faria o coração voltar atrás.
        if (_dirtyLikes.contains(ids[i])) continue;
        _likes[ids[i]] = counts[i];
        mine.contains(ids[i]) ? _liked.add(ids[i]) : _liked.remove(ids[i]);
      }
    });
  }

  /// Otimista, e é obrigatório: `count()` não funciona com listener, então o
  /// número não se mexeria sozinho e o coração pareceria não responder.
  ///
  /// Uma escrita por post de cada vez. Dois toques rápidos mandariam um `set`
  /// e um `delete` simultâneos, e o rollback do que falhasse aplicaria um
  /// delta cego sobre um estado que já mudou — o contador ficava errado até o
  /// fim da sessão.
  Future<void> _toggleLike(Post post, bool liked) async {
    if (_dirtyLikes.contains(post.id)) return;

    final beforeLiked = _liked.contains(post.id);
    final beforeCount = _likes[post.id] ?? 0;

    setState(() {
      _dirtyLikes.add(post.id);
      liked ? _liked.add(post.id) : _liked.remove(post.id);
      _likes[post.id] = (beforeCount + (liked ? 1 : -1)).clamp(0, 1 << 30);
    });

    try {
      await PostController.setLike(
        postId: post.id,
        uid: widget.uid,
        liked: liked,
      );
      if (!mounted) return;
      setState(() => _dirtyLikes.remove(post.id));
    } catch (e) {
      debugPrint('feed: curtida recusada: $e');
      if (!mounted) return;
      // Volta ao estado exato de antes, e não ao delta inverso: mostrar
      // curtido o que o servidor recusou é mentira.
      setState(() {
        _dirtyLikes.remove(post.id);
        beforeLiked ? _liked.add(post.id) : _liked.remove(post.id);
        _likes[post.id] = beforeCount;
      });
    }
  }

  Future<void> _erase(Post post) async {
    try {
      await PostController.erase(post);
      if (!mounted) return;
      setState(() {
        _posts.removeWhere((p) => p.id == post.id);
        _likes.remove(post.id);
        _liked.remove(post.id);
        _imageUrls.remove(post.id);
      });
    } catch (e) {
      debugPrint('feed: não foi possível apagar: $e');
    }
  }

  /// Publicar mora **dentro** do mural, não no menu `+`.
  ///
  /// Um botão flutuante cairia no mesmo canto do `+` da navBar, que o
  /// `extendBody` da Home deixa por cima do conteúdo; e é aqui que dá para
  /// recarregar a lista quando o post volta publicado.
  Future<void> _compose() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddPost(uid: widget.uid)),
    );
    if (published == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: _refresh, child: _body());
  }

  Widget _body() {
    if (_posts.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      // Com o controller mesmo vazio: o overscroll ainda pede a próxima
      // página, e o `RefreshIndicator` precisa de algo rolável.
      return ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomGap),
        children: [
          _composer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 32),
            child: Text(
              _failed
                  ? 'Não foi possível carregar o mural.'
                  : 'Ninguém publicou ainda. Seja o primeiro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomGap),
      itemCount: _posts.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _composer();

        if (index == _posts.length + 1) {
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          // O espaço onde o anúncio entra, quando entrar: um a cada N posts.
          // Ver `docs/specs/amigos.md`.
          return const SizedBox(height: 8);
        }

        final post = _posts[index - 1];
        return PostCard(
          post: post,
          author: widget.profiles[post.uid],
          imageUrl: _imageUrls[post.id],
          imageLoading: post.hasImage && !_imageUrls.containsKey(post.id),
          likes: _likes[post.id] ?? 0,
          liked: _liked.contains(post.id),
          isMine: post.uid == widget.uid,
          onLike: (liked) => _toggleLike(post, liked),
          onDelete: () => _erase(post),
        );
      },
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: const ValueKey('publicar-post'),
        onTap: _compose,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 10),
              Text(
                'Como foi o dia?',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
