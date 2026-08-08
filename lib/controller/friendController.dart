import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/services/firebase.dart';

/// Amizades e convites: `friends/{uid}/list` e `friendRequests/{uid}/*`.
///
/// **O id do documento é o dado.** Quem convidou e quem foi convidado estão
/// nos caminhos, não no corpo — mesma técnica de `nicknames/{apelido}`, e é o
/// que deixa a regra de segurança decidir sem precisar ler nada. O corpo
/// carrega só `at`, e a regra o prende a `request.time`.
///
/// Nome, foto e apelido **nunca** saem daqui: vêm de `profiles/{uid}`. Metade
/// destas arestas é escrita pela outra pessoa. Ver `docs/specs/amigos.md`.
class FriendController {
  static FirebaseFirestore get _db => FirestoreService.instance;

  /// Os caminhos são funções puras porque é neles que a segurança mora: a
  /// regra casa `friends/{uid}/list/{friendId}` e decide sem ler o corpo.
  /// Trocar um nome aqui quebraria a autorização em silêncio, e é a única
  /// parte do controller que um teste sem Firebase alcança.
  static String friendsPath(String uid) => 'friends/$uid/list';

  static String incomingPath(String uid) => 'friendRequests/$uid/incoming';

  static String outgoingPath(String uid) => 'friendRequests/$uid/outgoing';

  static CollectionReference<Map<String, dynamic>> friendsOf(String uid) =>
      _db.collection(friendsPath(uid));

  static CollectionReference<Map<String, dynamic>> incomingOf(String uid) =>
      _db.collection(incomingPath(uid));

  static CollectionReference<Map<String, dynamic>> outgoingOf(String uid) =>
      _db.collection(outgoingPath(uid));

  /// O corpo de toda aresta e de todo convite.
  ///
  /// `serverTimestamp()` e não `DateTime.now()`, saindo do padrão ISO-string
  /// do resto do app de propósito: `at` ordena a lista **do outro**, e quem o
  /// escreve é ele. A regra confere `at == request.time`, então um convidado
  /// não consegue se fixar no topo da minha lista com `9999-12-31`.
  static Map<String, dynamic> _stamp() => {'at': FieldValue.serverTimestamp()};

  static Stream<List<String>> watchFriends(String uid) =>
      friendsOf(uid).snapshots().map(_uidsNewestFirst);

  static Stream<List<String>> watchIncoming(String uid) =>
      incomingOf(uid).snapshots().map(_uidsNewestFirst);

  static Stream<List<String>> watchOutgoing(String uid) =>
      outgoingOf(uid).snapshots().map(_uidsNewestFirst);

  /// Convida alguém.
  ///
  /// Duas escritas num batch só: a caixa de entrada do outro e o meu próprio
  /// marcador de enviado. As duas pontas existem porque só o dono lê a própria
  /// caixa — sem `outgoing` eu não saberia o que enviei — e porque é o
  /// `outgoing` que prova o meu consentimento quando ele aceitar.
  static Future<void> invite({
    required String from,
    required String to,
  }) async {
    if (from == to) return;

    final batch = _db.batch();
    batch.set(incomingOf(to).doc(from), _stamp());
    batch.set(outgoingOf(from).doc(to), _stamp());
    await batch.commit();
  }

  /// Aceita o convite de [other].
  ///
  /// Um commit com as duas arestas e os **quatro** caminhos de marcador. Os
  /// quatro porque um convite mútuo — os dois se convidaram antes de qualquer
  /// aceite — deixa marcador nos dois lados, e apagar só o par consultado
  /// faria o outro continuar vendo convite pendente de quem já é amigo.
  /// Apagar documento inexistente é no-op, e a regra de `delete` não olha
  /// `resource`, então não é preciso saber quais existem.
  ///
  /// `set` cego nas arestas é seguro: a regra libera `create` **e** `update`
  /// sob a mesma condição, de propósito. Ler antes só adicionaria uma corrida.
  static Future<void> accept({
    required String me,
    required String other,
  }) async {
    if (me == other) return;

    final batch = _db.batch();

    // As duas nascem no mesmo commit ou nenhuma nasce: a regra exige a irmã
    // com `existsAfter`. É o que impede meia amizade.
    batch.set(friendsOf(me).doc(other), _stamp());
    batch.set(friendsOf(other).doc(me), _stamp());

    _clearRequests(batch, me: me, other: other);

    await batch.commit();
  }

  /// Recusa o convite de [other]: some com o par nos dois lados.
  static Future<void> decline({
    required String me,
    required String other,
  }) async {
    final batch = _db.batch();
    _clearRequests(batch, me: me, other: other);
    await batch.commit();
  }

  /// Retira um convite que eu enviei. É a mesma limpeza da recusa, vista do
  /// outro lado — por isso não há um segundo método.
  static Future<void> cancel({
    required String me,
    required String other,
  }) => decline(me: me, other: other);

  /// Desfaz a amizade.
  ///
  /// Apaga as duas arestas **e** qualquer marcador que tenha sobrado: um
  /// marcador vivo continua autorizando recriar a aresta, e a amizade
  /// ressuscitaria depois do desfazer.
  ///
  /// A regra não exige simetria no `delete`, ao contrário do `create`: prender
  /// a remoção acrescentaria um modo de falha a um caminho onde não há
  /// consentimento em jogo.
  static Future<void> remove({
    required String me,
    required String other,
  }) async {
    final batch = _db.batch();

    batch.delete(friendsOf(me).doc(other));
    batch.delete(friendsOf(other).doc(me));
    _clearRequests(batch, me: me, other: other);

    await batch.commit();
  }

  /// Os quatro caminhos que um convite entre duas pessoas pode ocupar.
  static void _clearRequests(
    WriteBatch batch, {
    required String me,
    required String other,
  }) {
    batch.delete(incomingOf(me).doc(other));
    batch.delete(outgoingOf(other).doc(me));
    batch.delete(incomingOf(other).doc(me));
    batch.delete(outgoingOf(me).doc(other));
  }

  static List<String> _uidsNewestFirst(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return sortByStamp([
      for (final doc in snapshot.docs) (uid: doc.id, at: _stampOf(doc)),
    ]);
  }

  /// `serverTimestamp()` chega `null` no snapshot local que o Firestore
  /// entrega **antes** do servidor confirmar. Tratar como "agora" mantém o
  /// convite recém-criado no topo em vez de mandá-lo para o fim da lista.
  static DateTime _stampOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final raw = doc.data()['at'];
    return raw is Timestamp ? raw.toDate() : DateTime.now();
  }

  /// Mais recente primeiro, desempatando pelo uid para a ordem não dançar
  /// entre dois rebuilds com os mesmos dados.
  static List<String> sortByStamp(List<({String uid, DateTime at})> entries) {
    final sorted = [...entries]
      ..sort((a, b) {
        final byDate = b.at.compareTo(a.at);
        return byDate != 0 ? byDate : a.uid.compareTo(b.uid);
      });
    return [for (final entry in sorted) entry.uid];
  }

  /// Os convites que ainda são convites.
  ///
  /// Marcador que sobrou de um aceite não pode virar linha na seção de
  /// convites: o botão diria "Aceitar" para quem já é amigo, e o toque bateria
  /// numa aresta que já existe. A lista de amigos manda.
  static List<String> pendingOnly(
    List<String> incoming,
    List<String> friends,
  ) {
    final known = friends.toSet();
    return [for (final uid in incoming) if (!known.contains(uid)) uid];
  }

  /// Melhor esforço: um convite que falha não pode derrubar a tela.
  static Future<bool> tryRun(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (e) {
      debugPrint('amigos: operação recusada ou sem rede: $e');
      return false;
    }
  }
}
