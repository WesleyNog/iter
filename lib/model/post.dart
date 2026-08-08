/// Uma publicação do mural: `posts/{postId}`, global.
///
/// O documento é pequeno de propósito — o feed é a única coisa do app que
/// cresce sem teto, e num `snapshots()` tudo que está no documento é baixado a
/// cada mudança. Texto, autor e data; a foto mora no Storage e aqui fica só o
/// caminho. Ver `docs/specs/amigos.md`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iter/model/newRouteModal.dart';

class Post {
  const Post({
    required this.id,
    required this.uid,
    required this.text,
    required this.createdAt,
    this.company,
    this.imagePath,
    this.deleted = false,
  });

  final String id;

  /// Quem publicou. **O único dado de autor no documento.**
  ///
  /// Nome, foto e apelido vêm de `profiles/{uid}`, sempre. Denormalizá-los
  /// aqui seria personificação de graça: a regra não tem como conferi-los
  /// contra a projeção, e qualquer um assinaria com o apelido de outro num
  /// mural global.
  final String uid;

  final String text;

  /// A empresa da rota que originou o post, quando há uma.
  final Company? company;

  /// `posts/{uid}/{postId}.jpg` — o **caminho** no Storage, não a URL.
  ///
  /// A URL do `getDownloadURL()` carrega um token, é servida sem autenticação
  /// e não passa pelas `storage.rules`: seria um link público e permanente,
  /// revogável só à mão no console. Guardando o caminho, quem decide quem vê
  /// continua sendo a regra. De quebra são ~55 bytes contra ~190.
  final String? imagePath;

  final DateTime createdAt;

  /// Apagado é **marcado**, nunca removido.
  ///
  /// O Firestore não apaga subcoleções em cascata: com `delete` de verdade as
  /// curtidas sobreviveriam ao post, e o id voltaria a ficar livre — um post
  /// novo herdaria as curtidas do anterior.
  final bool deleted;

  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  /// O corpo da **criação**, e só dela.
  ///
  /// Nome explícito porque não serve para editar: a regra libera `update`
  /// apenas para o tombstone, e `deleted` sai daqui sempre `false`.
  Map<String, dynamic> toCreateMap() {
    return {
      'uid': uid,
      'text': text,
      if (company != null) 'company': company!.name,
      if (imagePath != null) 'imagePath': imagePath,
      // A regra exige `createdAt == request.time`: sem o carimbo do servidor,
      // um post com data de 9999 lideraria o mural de todo mundo para sempre.
      'createdAt': FieldValue.serverTimestamp(),
      'deleted': false,
    };
  }

  factory Post.fromMap(String id, Map<String, dynamic> map) {
    return Post(
      id: id,
      uid: map['uid'] as String? ?? '',
      text: map['text'] as String? ?? '',
      // Sem fallback, ao contrário de `readEnum`: o campo é opcional, e
      // desenhar "Mercado Livre" num valor corrompido inventaria informação
      // onde o certo é não mostrar nada.
      company: _companyOf(map['company']),
      imagePath: map['imagePath'] as String?,
      // `serverTimestamp()` chega nulo no snapshot local que o Firestore
      // entrega antes de o servidor confirmar. Tratar como agora mantém o
      // post recém-publicado no topo, e não no fim.
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deleted: map['deleted'] as bool? ?? false,
    );
  }

  static Company? _companyOf(Object? raw) {
    if (raw is! String) return null;
    for (final company in Company.values) {
      if (company.name == raw) return company;
    }
    return null;
  }
}
