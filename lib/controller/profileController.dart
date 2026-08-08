import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/Utils/monthStats.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/services/firebase.dart';

/// `profiles/{uid}` e `profiles/{uid}/stats/*` — o que outro entregador
/// consegue ver de você.
///
/// A projeção existe porque `user/{uid}` guarda CPF, e-mail, telefone e data
/// de nascimento, e nunca pode abrir. Ver `docs/specs/amigos.md`.
class ProfileController {
  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirestoreService.instance.collection('profiles');

  static DocumentReference<Map<String, dynamic>> docFor(String uid) =>
      _collection.doc(uid);

  static CollectionReference<Map<String, dynamic>> statsOf(String uid) =>
      docFor(uid).collection('stats');

  /// Quantos meses a janela do ranking cobre.
  static const int windowMonths = 12;

  /// O documento da carreira, o que o dialog de perfil mostra.
  static const String careerBucket = 'all';

  /// A vitrine de alguém. **`null` significa "ainda não publicado"**, não
  /// "não existe".
  ///
  /// É o estado de todo usuário anterior a esta entrega que não reabriu o
  /// app, e a tela de busca tem de dizer isso em vez de "ninguém usa esse
  /// apelido" — que seria falso. Mesma disciplina do `getWeather`.
  static Future<PublicProfile?> fetch(String uid) async {
    try {
      final doc = await docFor(uid).get();
      final data = doc.data();
      return data == null ? null : PublicProfile.fromMap(data);
    } catch (e) {
      debugPrint('profiles/$uid ilegível: $e');
      return null;
    }
  }

  /// Os números de carreira de alguém, para o dialog de perfil.
  ///
  /// `null` quando o documento não existe — quem tem perfil mas ainda não
  /// publicou estatística não é o mesmo que quem rodou zero rotas, e o dialog
  /// já sabe desenhar `—`.
  static Future<ProfileStats?> fetchCareer(String uid) async {
    try {
      final doc = await statsOf(uid).doc(careerBucket).get();
      final data = doc.data();
      return data == null ? null : ProfileStats.fromMap(data);
    } catch (e) {
      debugPrint('profiles/$uid/stats/$careerBucket ilegível: $e');
      return null;
    }
  }

  /// O balde de um mês de alguém, para o ranking.
  static Future<MonthStats?> fetchMonth(String uid, String month) async {
    try {
      final doc = await statsOf(uid).doc(month).get();
      final data = doc.data();
      return data == null ? null : MonthStats.fromMap(data);
    } catch (e) {
      debugPrint('profiles/$uid/stats/$month ilegível: $e');
      return null;
    }
  }

  /// Monta a projeção a partir do [User] do FirebaseAuth.
  ///
  /// **Do `User`, nunca de `user/{uid}`.** Aquele documento tem `name` e
  /// `photoUrl` congelados desde o primeiro login — `_createUserIfNeeded`
  /// volta cedo quando ele já existe — e ninguém notou porque nenhuma tela os
  /// lê. Copiar de lá seria herdar foto velha para sempre.
  static PublicProfile projectionOf(
    User user, {
    String? nickName,
    DateTime? now,
  }) {
    return PublicProfile(
      uid: user.uid,
      // O e-mail não entra na projeção; é só o último recurso para não
      // publicar um perfil sem nome nenhum.
      name: _displayName(user),
      nickName: nickName,
      photoUrl: user.photoURL,
      updatedAt: (now ?? DateTime.now()).toIso8601String(),
    );
  }

  static String _displayName(User user) {
    final name = user.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;

    final email = user.email ?? '';
    final handle = email.split('@').first.trim();
    return handle.isEmpty ? 'Entregador' : handle;
  }

  /// Publica a vitrine, a carreira e a janela de meses, numa escrita só.
  ///
  /// Chamado na **abertura do app**, não no login: `signInWithGoogle()` só
  /// roda quando a `LoginScreen` o chama, e quem já tem sessão cai direto na
  /// Home pelo `AuthGate`. Pendurar aqui é o que faz o backfill de quem já
  /// existe acontecer sozinho — e é exatamente a razão de `user/{uid}` estar
  /// congelado desde o primeiro dia.
  ///
  /// A janela vai inteira, zeros incluídos: são doze escritas por abertura,
  /// contra a alternativa de deixar documento velho num mês que esvaziou.
  ///
  /// Falhar aqui **não pode derrubar a sessão**. A projeção é conveniência
  /// para os outros; o app do dono funciona sem ela — a mesma escolha do
  /// `StationController.report`.
  static Future<void> publish({
    required User user,
    required List<NewRouteModal> routes,
    String? nickName,
    DateTime? now,
  }) async {
    final reference = now ?? DateTime.now();
    final batch = FirestoreService.instance.batch();

    batch.set(
      docFor(user.uid),
      projectionOf(user, nickName: nickName, now: reference).toMap(),
    );

    batch.set(statsOf(user.uid).doc(careerBucket), {
      ...profileStats(routes).toMap(),
      'updatedAt': reference.toIso8601String(),
    });

    final buckets = monthlyStats(
      routes,
      reference: reference,
      months: windowMonths,
    );
    for (final entry in buckets.entries) {
      batch.set(statsOf(user.uid).doc(entry.key), {
        ...entry.value.toMap(),
        'updatedAt': reference.toIso8601String(),
      });
    }

    try {
      await batch.commit();
    } catch (e) {
      debugPrint('profiles: não foi possível publicar o perfil: $e');
    }
  }

  /// Republica a carreira e os meses que uma rota mexeu.
  ///
  /// Chamado depois de gravar ou apagar rota. Não é [publish]: aquele
  /// reescreve a vitrine e a janela inteira, e aqui só dois números mudaram —
  /// uma leitura e duas escritas contra catorze.
  ///
  /// [months] costuma ter um item, e tem **dois** quando uma edição mudou a
  /// data da rota: o mês de onde ela saiu também precisa ser recontado, senão
  /// fica somando uma rota que não está mais lá.
  static Future<void> refreshAfterRoute({
    required String uid,
    required List<NewRouteModal> routes,
    required Iterable<DateTime> months,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toIso8601String();
    final keys = {for (final month in months) monthKey(month): month};

    final batch = FirestoreService.instance.batch();

    batch.set(statsOf(uid).doc(careerBucket), {
      ...profileStats(routes).toMap(),
      'updatedAt': at,
    });

    for (final entry in keys.entries) {
      batch.set(statsOf(uid).doc(entry.key), {
        ...monthStatsOf(routes, entry.value).toMap(),
        'updatedAt': at,
      });
    }

    try {
      await batch.commit();
    } catch (e) {
      debugPrint('profiles/$uid: números públicos não republicados: $e');
    }
  }

  /// Atualiza só o apelido da projeção, dentro do batch de quem chama.
  ///
  /// Existe para `NicknameController.change()` trocar o apelido e a vitrine na
  /// mesma escrita — a projeção é cópia de exibição, e cópia que atualiza
  /// depois é cópia que discorda no meio.
  ///
  /// `merge: true` porque aqui não há `User` em mãos: reescrever o documento
  /// inteiro apagaria nome e foto.
  ///
  /// Exige que [publish] já tenha rodado alguma vez. A regra tem `hasAll` de
  /// `uid`, `name` e `updatedAt`, e num `merge` o servidor avalia o documento
  /// **resultante** — sem a projeção existir, o merge não completa a lista e a
  /// escrita é negada, derrubando o batch da troca junto. Na prática a
  /// projeção sempre existe: ela é publicada na abertura do app.
  static void addNicknameToBatch(
    WriteBatch batch, {
    required String uid,
    required String nickName,
    DateTime? now,
  }) {
    batch.set(docFor(uid), {
      'nickName': nickName,
      'updatedAt': (now ?? DateTime.now()).toIso8601String(),
    }, SetOptions(merge: true));
  }
}
