import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/report.dart';

Report _report({String? commentId, ReportReason reason = ReportReason.ofensa}) {
  return Report(
    uid: 'uid-bia',
    postId: 'p1',
    commentId: commentId,
    reason: reason,
  );
}

void main() {
  group('o id é o dado', () {
    test('denúncia de post é p_{postId}__{quem denunciou}', () {
      // A regra confere o id contra o corpo. Uma denúncia por pessoa por
      // alvo, garantida pela forma do dado — a técnica de nicknames outra vez.
      expect(_report().id, 'p_p1__uid-bia');
    });

    test('denúncia de comentário carrega os dois ids, e o prefixo', () {
      expect(_report(commentId: 'c9').id, 'c_p1_c9__uid-bia');
    });

    test('post e comentário não dividem o mesmo espaço de nomes', () {
      // Os dois ids são escolhidos pelo cliente. Sem o prefixo, um comentário
      // publicado com o id de um post fazia a denúncia de um sobrescrever a do
      // outro em silêncio — numa coleção onde `delete: if false` promete que
      // nada se perde.
      const denunciaDoPost = Report(
        uid: 'uid-bia',
        postId: 'p1',
        reason: ReportReason.ofensa,
      );
      const denunciaDoComentarioHomonimo = Report(
        uid: 'uid-bia',
        postId: 'q9',
        commentId: 'p1',
        reason: ReportReason.ofensa,
      );

      expect(denunciaDoPost.id, isNot(denunciaDoComentarioHomonimo.id));
    });

    test('duas pessoas denunciando o mesmo alvo são dois documentos', () {
      const outra = Report(
        uid: 'uid-zeca',
        postId: 'p1',
        reason: ReportReason.spam,
      );

      expect(_report().id, isNot(outra.id));
    });
  });

  group('toCreateMap — o corpo que a regra aceita', () {
    test('denúncia de post não carrega a chave commentId', () {
      // A regra tem `hasOnly`, mas o que decide o alvo é a **ausência** da
      // chave: um `commentId: null` explícito passaria no hasOnly e faria a
      // regra procurar o comentário `null`.
      final map = _report().toCreateMap();

      expect(map.keys.toSet(), {'uid', 'postId', 'reason', 'at'});
      expect(map.containsKey('commentId'), isFalse);
    });

    test('denúncia de comentário carrega os dois ids', () {
      // O `postId` fica junto porque é ele que dá o caminho do comentário — a
      // regra confere `posts/{postId}/comments/{commentId}`.
      final map = _report(commentId: 'c9').toCreateMap();

      expect(map['postId'], 'p1');
      expect(map['commentId'], 'c9');
    });

    test('o motivo vai como o `name` do enum, que é o que a regra lista', () {
      expect(
        _report(reason: ReportReason.golpe).toCreateMap()['reason'],
        'golpe',
      );
    });
  });

  test('todo motivo cabe na lista fechada da regra', () {
    // Renomear um valor do enum quebra a denúncia em produção sem quebrar
    // nenhum teste de tela: a regra recusa o que não estiver aqui.
    const naRegra = {'spam', 'ofensa', 'improprio', 'golpe', 'outro'};

    expect({for (final reason in ReportReason.values) reason.name}, naRegra);
  });

  test('todo motivo tem rótulo em pt-BR para a folha mostrar', () {
    for (final reason in ReportReason.values) {
      expect(reason.label.trim(), isNotEmpty, reason: 'motivo ${reason.name}');
    }
  });
}
