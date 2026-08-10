import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iter/controller/friendController.dart';
import 'package:iter/services/firebase.dart';

/// Bloqueio: `blocks/{uid}/list/{otherUid}`.
///
/// **A lista é do dono e só ele lê.** O bloqueado não descobre que foi
/// bloqueado — o convite dele apenas falha, do mesmo jeito que falharia sem
/// rede. Devolver "você foi bloqueado" seria entregar exatamente a informação
/// que faz a pessoa procurar outro caminho.
///
/// O id do documento é o dado, como em `friends` e `nicknames`: o corpo carrega
/// só `at`, e a regra o prende a `request.time`. Ver `docs/specs/amigos.md`.
class BlockController {
  static FirebaseFirestore get _db => FirestoreService.instance;

  /// O caminho é onde a segurança mora: a regra casa
  /// `blocks/{uid}/list/{otherId}` e decide sem ler o corpo. Trocar um nome
  /// aqui quebraria a autorização em silêncio.
  static String listPath(String uid) => 'blocks/$uid/list';

  static CollectionReference<Map<String, dynamic>> listOf(String uid) =>
      _db.collection(listPath(uid));

  static Map<String, dynamic> _stamp() => {'at': FieldValue.serverTimestamp()};

  /// Quem eu bloqueei.
  ///
  /// Um `Set` e não uma `List` porque o único consumidor é `contains`: o feed
  /// pergunta isso uma vez por post desenhado, e a lista de amigos uma vez por
  /// linha.
  static Stream<Set<String>> watch(String uid) => listOf(
    uid,
  ).snapshots().map((snapshot) => {for (final doc in snapshot.docs) doc.id});

  /// Bloqueia [other]: o marcador **e** o fim da relação, num commit só.
  ///
  /// Bloquear sem apagar a amizade deixaria a pessoa na lista, no ranking e
  /// com acesso aos números de carreira, que são de amigo. E um marcador de
  /// convite vivo continua autorizando recriar a aresta — a amizade
  /// ressuscitaria no primeiro aceite.
  ///
  /// `set` cego no marcador é seguro: a regra libera `create` **e** `update`
  /// sob a mesma condição, de propósito, então bloquear duas vezes não vira
  /// permission-denied.
  static Future<void> block({required String me, required String other}) async {
    if (me == other) return;

    final batch = _db.batch();
    batch.set(listOf(me).doc(other), _stamp());
    FriendController.severTies(batch, me: me, other: other);
    await batch.commit();
  }

  /// Desbloqueia. Não devolve a amizade: ela foi desfeita no bloqueio, e
  /// ressuscitá-la sozinha seria decidir pelo outro lado.
  static Future<void> unblock({required String me, required String other}) =>
      listOf(me).doc(other).delete();
}
