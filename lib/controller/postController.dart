import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/model/post.dart';
import 'package:iter/services/firebase.dart';
import 'package:iter/services/postImage.dart';

/// O mural: `posts` global, `iter/{uid}/posts` como espelho do dono.
///
/// **A primeira query com `where`/`orderBy` do projeto.** Todos os outros
/// controllers baixam a coleção inteira e ordenam em Dart, o que aqui seria
/// baixar o mural do app a cada abertura. Ver `docs/specs/amigos.md`.
class PostController {
  static FirebaseFirestore get _db => FirestoreService.instance;

  static CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection('posts');

  static CollectionReference<Map<String, dynamic>> mirrorOf(String uid) =>
      _db.collection('iter').doc(uid).collection('posts');

  static CollectionReference<Map<String, dynamic>> likesOf(String postId) =>
      _collection.doc(postId).collection('likes');

  /// Quantos posts por página. Vinte é o que cabe em duas ou três rolagens, e
  /// é o número com que a conta de custo da spec foi feita.
  static const int pageSize = 20;

  /// Uma página do mural, da mais recente para a mais antiga.
  ///
  /// `get()` e não `snapshots()`: um listener no mural reentrega o documento a
  /// cada curtida de qualquer pessoa, e cada reentrega é uma leitura cobrada.
  /// O feed atualiza no puxar-para-baixo, que é o que um mural precisa.
  ///
  /// Devolve o snapshot cru porque a próxima página começa depois do último
  /// documento — e guardar o documento do SDK dentro de `Post` amarraria o
  /// modelo ao Firestore.
  ///
  /// `orderBy('createdAt')` sozinho usa o índice automático de campo único:
  /// **não** precisa de índice composto. Somar `where('deleted', ...)` é que
  /// precisaria, e por isso o tombstone é filtrado no cliente — os apagados
  /// são poucos, e um índice para escondê-los sairia mais caro que baixá-los.
  static Future<QuerySnapshot<Map<String, dynamic>>> page({
    DocumentSnapshot? after,
  }) {
    var query = _collection
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    return query.get();
  }

  static List<Post> parse(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final posts = <Post>[];
    for (final doc in snapshot.docs) {
      try {
        final post = Post.fromMap(doc.id, doc.data());
        if (!post.deleted) posts.add(post);
      } catch (e) {
        // Um documento fora do formato não derruba o mural inteiro.
        debugPrint('Post ${doc.id} ignorado: $e');
      }
    }
    return posts;
  }

  /// Publica: o global e o espelho do dono, no mesmo `WriteBatch`.
  ///
  /// É o par que `StationController.report()` já faz com `gastop` + `precos`,
  /// e é o que resolve "minhas postagens" sem query nem índice na coleção
  /// global.
  ///
  /// A imagem sobe **antes** do batch: o documento guarda o caminho, e um
  /// caminho apontando para objeto inexistente é pior do que um post sem
  /// foto. Se o batch falhar depois, sobra um objeto órfão — é o lado barato
  /// de errar, e a limpeza é melhor esforço.
  static Future<void> publish(Post post) async {
    final batch = _db.batch();
    final body = post.toCreateMap();

    batch.set(_collection.doc(post.id), body);
    batch.set(mirrorOf(post.uid).doc(post.id), body);

    await batch.commit();
  }

  /// Apaga: marca o tombstone nos dois lados e some com a imagem.
  ///
  /// **Nunca `delete`.** O Firestore não apaga subcoleções em cascata: as
  /// curtidas sobreviveriam ao post, o id voltaria a ficar livre e um post
  /// novo herdaria a thread do anterior. A regra nega `delete` de propósito.
  static Future<void> erase(Post post) async {
    final tombstone = {'deleted': true, 'text': '', 'imagePath': null};

    final batch = _db.batch();
    batch.update(_collection.doc(post.id), tombstone);
    batch.update(mirrorOf(post.uid).doc(post.id), tombstone);
    await batch.commit();

    // Depois do commit: a foto órfã custa armazenamento, o documento que
    // aponta para foto inexistente custa uma imagem quebrada na tela.
    final path = post.imagePath;
    if (path != null) await PostImage.remove(path);
  }

  /// Curte ou descurte. O id do documento é quem curtiu, então não há
  /// contador para conciliar nem como curtir duas vezes.
  static Future<void> setLike({
    required String postId,
    required String uid,
    required bool liked,
  }) {
    final doc = likesOf(postId).doc(uid);
    return liked
        ? doc.set({'uid': uid, 'at': FieldValue.serverTimestamp()})
        : doc.delete();
  }

  /// Quantas curtidas um post tem.
  ///
  /// `count()` é uma agregação: lê entradas de índice, não os documentos —
  /// uma leitura cobrada por lote de mil. **Não funciona com listener nem
  /// offline**, então o número é o da abertura da tela; a curtida do próprio
  /// usuário se resolve otimista, sem reler.
  static Future<int> likeCount(String postId) async {
    try {
      final snapshot = await likesOf(postId).count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('feed: contagem de curtidas de $postId falhou: $e');
      return 0;
    }
  }

  /// Quais dos posts da página eu já curti.
  ///
  /// Uma leitura por post, em paralelo. `collectionGroup('likes').where('uid',
  /// ...)` faria isso numa leitura só, e é para essa porta que a curtida
  /// guarda o `uid` redundante no corpo — mas exigiria uma regra nova em
  /// `/{path=**}/likes/` e um índice de collection group versionado. Vinte
  /// leituras por página contra 50 mil por dia de cota gratuita não paga esse
  /// aparato agora; o campo fica, e a troca é de uma função só.
  static Future<Set<String>> likedAmong(
    Iterable<String> postIds,
    String uid,
  ) async {
    try {
      final ids = postIds.toList();
      final docs = await Future.wait(
        ids.map((id) => likesOf(id).doc(uid).get()),
      );

      return {
        for (var i = 0; i < ids.length; i++)
          if (docs[i].exists) ids[i],
      };
    } catch (e) {
      debugPrint('feed: curtidas do usuário não vieram: $e');
      return {};
    }
  }
}
