/// Para onde o toque numa notificação leva.
///
/// Função pura sobre o mapa `data` da mensagem, e **sem importar
/// `firebase_messaging`** de propósito: o que decide o destino é dado, não
/// plataforma, e é isso que deixa esta parte ser testada sem subir Firebase —
/// a mesma disciplina de `Utils/routeFilter.dart` e `Utils/ranking.dart`.
///
/// Ver `docs/specs/notificacoes.md`.
library;

import 'package:iter/Utils/ranking.dart';

/// O que aconteceu. O valor de `tipo` no `data` da mensagem é o `name` destes.
enum NotificationKind {
  /// Alguém te convidou para ser amigo.
  convite,

  /// Alguém aceitou o convite que você mandou.
  aceite,

  /// Um amigo te ultrapassou no ranking do mês.
  ranking,

  /// Sua publicação bateu um marco de curtidas.
  curtidas,

  /// Comentaram na sua publicação, ou ela bateu um marco de comentários.
  comentarios,
}

/// A sub-tela da aba Amigos que o toque abre.
///
/// Enum próprio em vez de `FriendsTab`, que mora em `screens/friendsScreen.dart`:
/// importar tela dentro de `Utils/` inverteria as camadas e traria Flutter para
/// um arquivo que existe justamente para não precisar dele. A tradução para
/// `FriendsTab` é um `switch` exaustivo na tela, que o analisador cobra.
enum NotificationDestination { amigos, ranking, feed }

/// Um toque a ser consumido.
///
/// **Identidade, nunca igualdade de valor.** Esta classe não sobrescreve `==`
/// nem `hashCode`, e não pode passar a sobrescrever: dois convites seguidos
/// produzem alvos de conteúdo idêntico, e com igualdade de valor o segundo
/// toque não moveria nada — se o usuário navegou para outra aba depois do
/// primeiro, o `didUpdateWidget` compararia igual e ignoraria. Um `bool` ou um
/// `enum` simples no lugar desta classe tem o mesmo defeito, e foi por isso que
/// ela existe.
class NotificationTarget {
  const NotificationTarget({
    required this.kind,
    this.fromUid,
    this.toUid,
    this.postId,
    this.criterion,
    this.month,
  });

  final NotificationKind kind;

  /// Quem causou. Ausente nos marcos, onde **não há um autor a nomear**: na
  /// décima curtida, apontar a última pessoa credita quem não fez o marco.
  final String? fromUid;

  /// Para quem a mensagem foi enviada.
  ///
  /// A função já sabe disso e mandar custa zero — e é a segunda trava do
  /// celular emprestado: quem consome descarta o alvo que não é da sessão
  /// atual, mesmo que o token tenha sobrevivido a uma troca de conta.
  final String? toUid;

  /// A publicação, nos eventos de curtida e comentário.
  final String? postId;

  /// O critério em que fui ultrapassado.
  ///
  /// Reaproveita o enum do ranking em vez de repetir os três nomes: uma segunda
  /// lista dos mesmos critérios divergiria na primeira vez que alguém editasse
  /// só uma.
  final RankCriterion? criterion;

  /// `yyyy-MM` do balde disputado.
  final String? month;

  /// Onde este toque pousa.
  NotificationDestination get destination => switch (kind) {
    NotificationKind.convite || NotificationKind.aceite =>
      NotificationDestination.amigos,
    NotificationKind.ranking => NotificationDestination.ranking,
    NotificationKind.curtidas ||
    NotificationKind.comentarios => NotificationDestination.feed,
  };

  /// Se o toque deve abrir a thread do post, e não só o mural.
  ///
  /// Só no comentário: quem foi comentado quer ler o que escreveram. Na curtida
  /// não há o que ler, e abrir a folha por cima seria uma tela a mais entre o
  /// dedo e a informação.
  bool get opensThread =>
      kind == NotificationKind.comentarios && postId != null;

  /// Lê o `data` de uma mensagem.
  ///
  /// **`Map<String, dynamic>` porque é esse o tipo real de `RemoteMessage.data`**
  /// — declarar `Map<String, String>` obrigaria o chamador a converter, e a
  /// conversão só estoura no aparelho, no dia em que algum valor não vier como
  /// string. Aqui cada campo é lido com `_texto`, que devolve `null` para
  /// qualquer coisa que não seja `String`.
  ///
  /// Devolve `null` quando não dá para saber o destino — tipo ausente ou
  /// desconhecido. É a disciplina do `getWeather`: "não sei" não pode virar um
  /// palpite, e o palpite aqui seria jogar o usuário numa tela que não tem nada
  /// a ver com o aviso que ele tocou.
  static NotificationTarget? fromData(Map<String, dynamic> data) {
    final kind = _kindOf(_texto(data['tipo']));
    if (kind == null) return null;

    return NotificationTarget(
      kind: kind,
      fromUid: _texto(data['de']),
      toUid: _texto(data['para']),
      postId: _texto(data['postId']),
      // Critério irreconhecível **não** invalida o alvo: a aba Ranking abre no
      // critério padrão dela, que é uma tela útil. Recusar o toque inteiro por
      // causa de um campo secundário seria punir o usuário por um erro do
      // servidor.
      criterion: _criterionOf(_texto(data['criterio'])),
      month: _texto(data['mes']),
    );
  }

  static NotificationKind? _kindOf(String? raw) {
    if (raw == null) return null;
    for (final kind in NotificationKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }

  static RankCriterion? _criterionOf(String? raw) {
    if (raw == null) return null;
    for (final criterion in RankCriterion.values) {
      if (criterion.name == raw) return criterion;
    }
    return null;
  }

  /// Todo valor de `data` no FCM é string; qualquer outra coisa é engano de
  /// quem mandou, e engano não vira dado.
  static String? _texto(Object? raw) {
    if (raw is! String) return null;
    final texto = raw.trim();
    return texto.isEmpty ? null : texto;
  }
}
