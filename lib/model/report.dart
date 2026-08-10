/// Uma denúncia: `reports/{alvo}__{quem denunciou}`.
///
/// **Não há servidor, então o documento é o canal.** Ninguém lê esta coleção
/// pelo app — nem quem denunciou: uma lista de denúncias legível é a lista de
/// quem delatou quem, e entre entregadores que se conhecem do galpão isso é
/// pior do que o conteúdo denunciado. Quem modera lê no console do Firebase e
/// marca o post com `deleted: true`, que é escrita de admin e não passa pelas
/// regras. Ver `docs/specs/amigos.md`.
///
/// Por isso não existe `fromMap` aqui: nada neste app volta a ler o documento.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Os motivos, em lista fechada.
///
/// Lista fechada e não texto livre porque o campo existe para **triar a fila**;
/// um campo de texto que só o dono do app lê seria um canal de recado que
/// ninguém pediu — e o primeiro lugar onde alguém escreveria o nome e o
/// telefone de outra pessoa. O `name` de cada valor é literalmente o que a
/// regra aceita: renomear um deles quebra a denúncia em produção.
enum ReportReason {
  spam('Spam ou propaganda'),
  ofensa('Ofensa ou assédio'),
  improprio('Conteúdo impróprio'),
  golpe('Golpe ou informação falsa'),
  outro('Outro motivo');

  const ReportReason(this.label);

  final String label;
}

class Report {
  const Report({
    required this.uid,
    required this.postId,
    required this.reason,
    this.commentId,
  });

  /// Quem denunciou. A regra confere contra `request.auth.uid`.
  final String uid;

  final String postId;

  /// `null` denuncia o post inteiro. **A ausência é que diz qual é o alvo** —
  /// um campo `tipo` seria preenchido pelo cliente de um jeito e apontaria
  /// para outro.
  final String? commentId;

  final ReportReason reason;

  /// `p_{postId}__{quem}` ou `c_{postId}_{commentId}__{quem}` — a técnica de
  /// `nicknames/{apelido}` outra vez: uma denúncia por pessoa por alvo,
  /// garantida pela **forma** do dado, sem contador e sem corrida. A regra
  /// confere o id contra o corpo, então mudar esta linha sem mudar a regra
  /// derruba a denúncia inteira.
  ///
  /// O prefixo separa os dois espaços de nomes, e não é zelo: os ids de post e
  /// de comentário são **escolhidos pelo cliente**. Sem ele, bastava publicar
  /// um comentário com o id de um post para a denúncia de um sobrescrever a do
  /// outro em silêncio, numa coleção onde `delete: if false` promete que nada
  /// se perde. O `_` só serve de separador porque a regra recusa id de post e
  /// de comentário que o contenha.
  String get id => commentId == null
      ? 'p_${postId}__$uid'
      : 'c_${postId}_${commentId}__$uid';

  Map<String, dynamic> toCreateMap() {
    return {
      'uid': uid,
      'postId': postId,
      if (commentId != null) 'commentId': commentId,
      'reason': reason.name,
      // Como todo carimbo que a regra confere: `request.time`, nunca o relógio
      // de quem escreve.
      'at': FieldValue.serverTimestamp(),
    };
  }
}
