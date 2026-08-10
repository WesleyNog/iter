/// Um comentário: `posts/{postId}/comments/{id}`.
///
/// **Texto livre de uma pessoa aparecendo embaixo do post de outra.** É a
/// diferença entre curtida e comentário, e a razão de esta subcoleção só ter
/// nascido depois do bloqueio e da denúncia — quem publica assume o que
/// escreve, quem é comentado não escolheu. Ver `docs/specs/amigos.md`.
///
/// Como o post, guarda só o `uid`: nome, foto e apelido vêm de
/// `profiles/{uid}`, sempre. Denormalizá-los aqui seria personificação de
/// graça, porque a regra não tem como conferi-los contra a projeção.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  const Comment({
    required this.id,
    required this.uid,
    required this.text,
    required this.createdAt,
  });

  /// O mesmo teto do post, e o mesmo da regra de segurança.
  static const int maxLength = 500;

  final String id;
  final String uid;
  final String text;
  final DateTime createdAt;

  /// O corpo da criação, e só dela: a regra nega `update` de propósito —
  /// comentário que pode ser reescrito depois de alguém responder não é
  /// comentário.
  Map<String, dynamic> toCreateMap() {
    return {
      'uid': uid,
      'text': text,
      // A regra exige `createdAt == request.time`, pelo mesmo motivo do post:
      // sem o carimbo do servidor, um comentário datado de 9999 fixa-se no fim
      // da thread para sempre.
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory Comment.fromMap(String id, Map<String, dynamic> map) {
    return Comment(
      id: id,
      uid: map['uid'] as String? ?? '',
      text: map['text'] as String? ?? '',
      // `serverTimestamp()` chega nulo no snapshot local que o Firestore
      // entrega antes de o servidor confirmar. Tratar como agora é o que
      // mantém o comentário recém-escrito no **fim** da thread; nulo ordenado
      // como valor faria ele saltar para o topo e voltar sozinho um segundo
      // depois.
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
