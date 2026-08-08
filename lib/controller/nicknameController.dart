import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iter/controller/profileController.dart';
import 'package:iter/services/firebase.dart';

/// Reserva de apelidos em `nicknames/{apelido}` → `{ uid }`.
///
/// O apelido é o **ID do documento**, então a unicidade é garantida pelo
/// próprio Firestore: as regras liberam `create` e `delete`, nunca `update`,
/// e `create` só passa quando o documento ainda não existe. Não existe a
/// janela de corrida do "consulta e depois grava".
class NicknameController {
  static const int minLength = 3;
  static const int maxLength = 20;

  /// Caracteres aceitos — precisa casar com o regex das regras de segurança.
  static final RegExp _allowed = RegExp(r'^[a-z0-9._-]{3,20}$');
  static final RegExp _invalidChars = RegExp(r'[^a-z0-9._-]');
  static final RegExp _repeatedDashes = RegExp(r'-{2,}');

  static const Map<String, String> _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirestoreService.instance.collection('nicknames');

  /// Referência do apelido — exposta para quem precisa montar um batch junto
  /// com outras escritas (ver [GoogleSignInService]).
  static DocumentReference<Map<String, dynamic>> docFor(String nickname) =>
      _collection.doc(nickname);

  /// Conteúdo gravado na reserva.
  static Map<String, dynamic> claimData(String uid) => {
    'uid': uid,
    'createdAt': DateTime.now().toIso8601String(),
  };

  /// Deixa o texto no formato aceito pelas regras: minúsculo, sem acento e
  /// só com `a-z 0-9 . _ -`.
  static String normalize(String raw) {
    final lower = raw.trim().toLowerCase();
    final withoutAccents = lower
        .split('')
        .map((char) => _accents[char] ?? char)
        .join();

    return withoutAccents
        .replaceAll(_invalidChars, '-')
        .replaceAll(_repeatedDashes, '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static bool isValid(String nickname) => _allowed.hasMatch(nickname);

  /// Monta um apelido a partir do nome ou do e-mail, com sufixo aleatório
  /// para reduzir colisão já na primeira tentativa.
  static String suggestFrom({String? displayName, String? email}) {
    var base = normalize(displayName?.split(' ').first ?? '');
    if (base.isEmpty) base = normalize(email?.split('@').first ?? '');
    if (base.isEmpty) base = 'user';

    // 5 caracteres do sufixo (`-abcd`) precisam caber no limite.
    final maxBase = maxLength - 5;
    if (base.length > maxBase) base = base.substring(0, maxBase);

    return '$base-${_randomSuffix()}';
  }

  /// `true` quando ninguém reservou o apelido ainda.
  ///
  /// Serve para dar retorno na tela; a garantia real vem do `create`.
  static Future<bool> isAvailable(String nickname) async {
    if (!isValid(nickname)) return false;
    final doc = await docFor(nickname).get();
    return !doc.exists;
  }

  /// Descobre de quem é o apelido — a busca por `@apelido` é esta leitura.
  static Future<String?> resolveUid(String nickname) async {
    final doc = await docFor(nickname).get();
    return doc.data()?['uid'] as String?;
  }

  /// Troca o apelido de [uid] em um único batch: cria a reserva nova, apaga a
  /// antiga e atualiza `user/{uid}`.
  ///
  /// Tudo ou nada: se o apelido já pertence a outra pessoa, o `create` é
  /// negado pelas regras e nada é alterado. Lança [FirebaseException] com
  /// `permission-denied` nesse caso.
  static Future<void> change({
    required String uid,
    required String newNickname,
    String? previous,
  }) async {
    final nickname = normalize(newNickname);
    if (!isValid(nickname)) {
      throw ArgumentError(
        'Apelido inválido: use de $minLength a $maxLength caracteres entre '
        'letras, números, ponto, hífen e underscore.',
      );
    }
    if (nickname == previous) return;

    final firestore = FirestoreService.instance;
    final batch = firestore.batch();

    batch.set(docFor(nickname), claimData(uid));
    if (previous != null && previous.isNotEmpty) {
      batch.delete(docFor(previous));
    }
    final now = DateTime.now().toIso8601String();
    batch.update(firestore.collection('user').doc(uid), {
      'nickName': nickname,
      // Carimbo da troca: é o que uma futura regra de carência ("só troca a
      // cada X dias") ou de cobrança vai consultar. Ausente = nunca trocou.
      'nickNameChangedAt': now,
      'updatedAt': now,
    });

    // A vitrine pública carrega uma cópia do apelido, e cópia que atualiza
    // depois é cópia que discorda no meio: entre um commit e outro a busca
    // acharia o uid pelo apelido novo e o perfil mostraria o antigo. Vai no
    // mesmo batch — a regra usa `getAfter` justamente para enxergar a reserva
    // criada aqui em cima.
    ProfileController.addNicknameToBatch(batch, uid: uid, nickName: nickname);

    await batch.commit();
  }

  static String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(
      4,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
