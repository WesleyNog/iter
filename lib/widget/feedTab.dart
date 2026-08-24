import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/feedAds.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/controller/blockController.dart';
import 'package:iter/controller/postController.dart';
import 'package:iter/controller/reportController.dart';
import 'package:iter/model/post.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/model/report.dart';
import 'package:iter/screens/addPost.dart';
import 'package:iter/services/postImage.dart';
import 'package:iter/widget/blockDialog.dart';
import 'package:iter/widget/commentsSheet.dart';
import 'package:iter/widget/feedAdSlot.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/postCard.dart';
import 'package:iter/widget/reportSheet.dart';

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
    required this.blocked,
    required this.onNeedProfiles,
    required this.bottomGap,
  });

  final String uid;
  final Map<String, PublicProfile?> profiles;

  /// Quem eu bloqueei. Filtro de **cliente**: o mural é global e a regra não
  /// tem como esconder documento de quem lista a coleção. O que a regra
  /// garante é o outro lado — bloqueado não comenta e não convida.
  final Set<String> blocked;

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
  final _comments = <String, int>{};

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

  /// Bloquear na aba Amigos tem de limpar o mural que já está carregado.
  ///
  /// O filtro do `_load` só alcança as páginas seguintes; sem isto, quem eu
  /// acabei de bloquear continuaria na tela até eu puxar para atualizar — e
  /// "bloqueei e ele continua aí" é a tela dizendo que o bloqueio não pegou.
  @override
  void didUpdateWidget(FeedTab old) {
    super.didUpdateWidget(old);
    if (old.blocked.length == widget.blocked.length) return;

    final blocked = _posts.where((p) => widget.blocked.contains(p.uid));
    if (blocked.isEmpty) return;
    setState(() => _posts.removeWhere((p) => widget.blocked.contains(p.uid)));
  }

  /// Sem os autores bloqueados. Aplicado no **carregamento**, não no desenho:
  /// contar curtidas e comentários de post que não vai aparecer é leitura
  /// cobrada por nada.
  List<Post> _allowed(Iterable<Post> posts) => [
    for (final post in posts)
      if (!widget.blocked.contains(post.uid)) post,
  ];

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

        fresh.addAll(_allowed(PostController.parse(snapshot)));
        if (fresh.isNotEmpty) break;
      }

      setState(() {
        _posts.addAll(fresh);
        _loading = false;
      });

      widget.onNeedProfiles([for (final post in fresh) post.uid]);
      await _fetchMedia(fresh, gen);
      await _fetchCounters(fresh, gen);
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

  /// Curtidas e comentários da página, em paralelo.
  ///
  /// Três agregações por post — curtidas, comentários e a minha curtida —, e
  /// nenhuma delas funciona com listener: `count()` só responde por chamada
  /// direta ao servidor. Os números são os da abertura da tela, e é isso que a
  /// atualização otimista da curtida e o retorno da folha de comentários
  /// corrigem.
  Future<void> _fetchCounters(List<Post> page, int gen) async {
    final ids = [for (final post in page) post.id];
    if (ids.isEmpty) return;

    final likes = await Future.wait(ids.map(PostController.likeCount));
    final comments = await Future.wait(ids.map(PostController.commentCount));
    final mine = await PostController.likedAmong(ids, widget.uid);
    if (!mounted || gen != _generation) return;

    setState(() {
      for (var i = 0; i < ids.length; i++) {
        _comments[ids[i]] = comments[i];

        // O que o usuário acabou de tocar manda: o número do servidor foi
        // lido antes da escrita e faria o coração voltar atrás.
        if (_dirtyLikes.contains(ids[i])) continue;
        _likes[ids[i]] = likes[i];
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
      setState(() => _forget(post.id));
    } catch (e) {
      debugPrint('feed: não foi possível apagar: $e');
    }
  }

  /// Tira o post da lista e dos mapas. Sempre dentro de um `setState`.
  void _forget(String id) {
    _posts.removeWhere((p) => p.id == id);
    _likes.remove(id);
    _liked.remove(id);
    _comments.remove(id);
    _imageUrls.remove(id);
  }

  /// A thread do post.
  ///
  /// A contagem volta da folha porque ela é a única que sabe o número certo: o
  /// `count()` do servidor inclui os comentários de quem eu bloqueei, e a
  /// folha os filtra.
  Future<void> _openComments(Post post) {
    return showCommentsSheet(
      context,
      post: post,
      uid: widget.uid,
      profiles: widget.profiles,
      blocked: widget.blocked,
      onCount: (total) {
        if (!mounted) return;
        setState(() => _comments[post.id] = total);
      },
    );
  }

  Future<void> _report(Post post) async {
    final reason = await showReportSheet(context, isComment: false);
    if (reason == null || !mounted) return;

    try {
      await ReportController.send(
        Report(uid: widget.uid, postId: post.id, reason: reason),
      );
      if (!mounted) return;

      // Some da **minha** lista agora. Denunciar e continuar vendo o post é a
      // tela dizendo que nada aconteceu — e nada aconteceu mesmo, porque quem
      // modera é uma pessoa e ela lê depois.
      //
      // Não persiste de propósito: guardar "posts que fulano escondeu" é mais
      // uma coleção e mais uma leitura por abertura, para resolver o que
      // bloquear já resolve de vez. Reabrir o app traz o post de volta, até
      // alguém moderar.
      setState(() => _forget(post.id));
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

  Future<void> _block(Post post) async {
    final name = displayName(widget.profiles[post.uid]);
    final ok = await confirmBlock(context, name: name);
    if (ok != true || !mounted) return;

    try {
      await BlockController.block(me: widget.uid, other: post.uid);
      if (!mounted) return;

      // Todos os posts dele, não só este: bloquear é sobre a pessoa.
      setState(() {
        for (final id in [
          for (final p in _posts)
            if (p.uid == post.uid) p.id,
        ]) {
          _forget(id);
        }
      });
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

  /// Publicar mora **dentro** do mural, não no menu `+`.
  ///
  /// Um botão flutuante cairia no mesmo canto do `+` da navBar, que o
  /// `extendBody` da Home deixa por cima do conteúdo; e é aqui que dá para
  /// recarregar a lista quando o post volta publicado.
  Future<void> _compose() async {
    final published = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => AddPost(uid: widget.uid)));
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

    // A lista com os anúncios já no lugar, montada **uma vez por build** e não
    // dentro do `itemBuilder`.
    //
    // `feedWithAds` é determinística, então chamá-la aqui devolve sempre o
    // mesmo resultado para os mesmos posts — é isso que dispensa guardar a
    // sequência num campo do State e invalidá-la nos quatro lugares onde
    // `_posts` muda. Decidir a cadência lá dentro seria o defeito oposto: o
    // builder roda a cada rebuild, e esta tela reconstrói a cada curtida, a
    // cada foto resolvida e a cada perfil que chega do prefetch — o anúncio
    // mudaria de lugar debaixo do dedo de quem rola. Ver
    // `docs/specs/anuncios-no-feed.md`.
    final slots = feedWithAds(_posts);

    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomGap),
      // Uma aritmética só, e num lugar só: o compositor na frente, o rodapé
      // atrás. Antes eram três constantes literais (`+ 2`, `+ 1`, `- 1`) em
      // três linhas deste mesmo builder, e qualquer item novo entre os posts
      // quebrava as três de uma vez.
      itemCount: slots.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _composer();

        if (index == slots.length + 1) {
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const SizedBox(height: 8);
        }

        // **A `key` vai na raiz de cada item**, e não só dentro do `PostCard`.
        //
        // O `ListView` casa elemento com widget pela raiz; a
        // `ValueKey('post-…')` que já existia mora um nível abaixo, dentro do
        // build do card, e portanto não contava. Enquanto tudo na lista era
        // `StatelessWidget` isso funcionava por sorte. Um anúncio tem estado —
        // objeto `Ad`, view nativa —, e casar posicionalmente um anúncio com
        // um card depois de apagar um post do meio é exatamente o caso em que
        // a falta de key aparece.
        //
        // `switch` sobre o tipo selado, e não `is` mais `as`: é o compilador
        // cobrando o caso novo no dia em que um terceiro tipo de item entrar
        // na lista. Com o `as`, um `FeedSlot` novo compilaria e estouraria em
        // execução, na tela de outra pessoa.
        return switch (slots[index - 1]) {
          AdSlot(:final anchorId) => FeedAdSlot(key: ValueKey('ad-$anchorId')),
          PostSlot(:final post) => _card(post),
        };
      },
    );
  }

  Widget _card(Post post) {
    final isMine = post.uid == widget.uid;

    return PostCard(
      key: ValueKey('post-${post.id}'),
      post: post,
      author: widget.profiles[post.uid],
      imageUrl: _imageUrls[post.id],
      imageLoading: post.hasImage && !_imageUrls.containsKey(post.id),
      likes: _likes[post.id] ?? 0,
      liked: _liked.contains(post.id),
      comments: _comments[post.id] ?? 0,
      isMine: isMine,
      onLike: (liked) => _toggleLike(post, liked),
      onComment: () => _openComments(post),
      onDelete: () => _erase(post),
      // Ninguém se denuncia nem se bloqueia: no post próprio o menu tem uma
      // linha só.
      onReport: isMine ? null : () => _report(post),
      onBlock: isMine ? null : () => _block(post),
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
