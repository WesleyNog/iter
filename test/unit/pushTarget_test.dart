import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/pushTarget.dart';
import 'package:iter/Utils/ranking.dart';

/// O que este arquivo protege é o toque na notificação: o mapa que chega do
/// servidor vira um destino, ou vira `null`. Roda sem Firebase porque
/// `Utils/pushTarget.dart` não importa `firebase_messaging` — se um dia
/// importar, este arquivo é o primeiro a quebrar, e é para isso que ele serve.
void main() {
  group('fromData — o mapa que chega do servidor', () {
    test('convite abre a lista de amigos, e diz quem convidou', () {
      final alvo = NotificationTarget.fromData({
        'tipo': 'convite',
        'de': 'uid-cleyton',
        'para': 'uid-wesley',
      });

      expect(alvo, isNotNull);
      expect(alvo!.kind, NotificationKind.convite);
      expect(alvo.destination, NotificationDestination.amigos);
      expect(alvo.fromUid, 'uid-cleyton');
      expect(alvo.toUid, 'uid-wesley');
      expect(alvo.opensThread, isFalse);
    });

    test('aceite também cai na lista de amigos', () {
      final alvo = NotificationTarget.fromData({
        'tipo': 'aceite',
        'de': 'uid-wesley',
      });

      expect(alvo!.destination, NotificationDestination.amigos);
    });

    test('ranking leva o critério e o mês', () {
      final alvo = NotificationTarget.fromData({
        'tipo': 'ranking',
        'de': 'uid-cleyton',
        'criterio': 'ritmo',
        'mes': '2026-08',
      });

      expect(alvo!.destination, NotificationDestination.ranking);
      expect(alvo.criterion, RankCriterion.ritmo);
      expect(alvo.month, '2026-08');
    });

    test('curtida leva ao mural, sem abrir a thread', () {
      // Não há o que ler numa curtida. Abrir a folha de comentários por cima
      // seria uma tela a mais entre o dedo e a informação.
      final alvo = NotificationTarget.fromData({
        'tipo': 'curtidas',
        'postId': 'post-1',
      });

      expect(alvo!.destination, NotificationDestination.feed);
      expect(alvo.postId, 'post-1');
      expect(alvo.opensThread, isFalse);
    });

    test('comentário abre a thread', () {
      final alvo = NotificationTarget.fromData({
        'tipo': 'comentarios',
        'de': 'uid-cleyton',
        'postId': 'post-1',
      });

      expect(alvo!.destination, NotificationDestination.feed);
      expect(alvo.opensThread, isTrue);
    });

    test('comentário sem postId não promete abrir thread nenhuma', () {
      // `opensThread` é o que a tela consulta antes de buscar o post. Dizer
      // `true` sem id mandaria a tela buscar `posts/null`.
      final alvo = NotificationTarget.fromData({'tipo': 'comentarios'});

      expect(alvo!.opensThread, isFalse);
      expect(alvo.destination, NotificationDestination.feed);
    });
  });

  group('o que não dá para saber vira null, nunca um palpite', () {
    test('tipo ausente devolve null', () {
      expect(NotificationTarget.fromData({'de': 'uid-cleyton'}), isNull);
    });

    test('tipo desconhecido devolve null', () {
      // O servidor de amanhã pode mandar um tipo que o app de hoje não conhece.
      // Escolher uma tela para ele seria jogar o usuário num lugar que não tem
      // relação com o aviso que ele tocou — a disciplina do `getWeather`, onde
      // "não descobri" nunca virou "está limpo".
      expect(NotificationTarget.fromData({'tipo': 'sorteio'}), isNull);
    });

    test('valor que não é string é ignorado, e não derruba o parse', () {
      // Todo valor de `data` no FCM é string. Um número aqui é engano de quem
      // mandou, e engano não pode virar exceção no aparelho.
      final alvo = NotificationTarget.fromData({
        'tipo': 'curtidas',
        'postId': 42,
        'de': null,
      });

      expect(alvo, isNotNull);
      expect(alvo!.postId, isNull);
      expect(alvo.fromUid, isNull);
    });

    test('string vazia é o mesmo que campo ausente', () {
      final alvo = NotificationTarget.fromData({
        'tipo': 'convite',
        'de': '   ',
      });

      expect(alvo!.fromUid, isNull);
    });

    test('critério irreconhecível não invalida o alvo', () {
      // O critério é campo secundário: sem ele a aba Ranking abre no padrão
      // dela, que é uma tela útil. Recusar o toque inteiro seria punir o
      // usuário por um erro do servidor.
      final alvo = NotificationTarget.fromData({
        'tipo': 'ranking',
        'criterio': 'dinheiro',
      });

      expect(alvo, isNotNull);
      expect(alvo!.criterion, isNull);
      expect(alvo.destination, NotificationDestination.ranking);
    });
  });

  group('identidade, e não igualdade de valor', () {
    test('dois alvos de mesmo conteúdo são objetos DIFERENTES', () {
      // Este teste existe para travar uma decisão, não para exercitar código.
      //
      // Dois convites seguidos produzem alvos de conteúdo idêntico. Se esta
      // classe ganhasse `==` de valor — ou se o parâmetro fosse um `bool`/`enum`
      // —, o `didUpdateWidget` da aba compararia igual e o segundo toque não
      // moveria nada: quem navegou para o Feed depois do primeiro convite
      // ficaria preso lá. É o mesmo raciocínio que impede `ValueKey` na
      // `RankingTab`.
      //
      // Se alguém sobrescrever `==` em `NotificationTarget`, é aqui que aparece.
      final dados = {'tipo': 'convite', 'de': 'uid-cleyton'};
      final primeiro = NotificationTarget.fromData(dados);
      final segundo = NotificationTarget.fromData(dados);

      expect(identical(primeiro, segundo), isFalse);
      expect(primeiro == segundo, isFalse);
    });
  });
}
