import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/post.dart';
import 'package:iter/services/postImage.dart';

Post _post({
  String text = 'Dia puxado',
  Company? company,
  String? imagePath,
}) {
  return Post(
    id: 'p1',
    uid: 'uid-ana',
    text: text,
    company: company,
    imagePath: imagePath,
    createdAt: DateTime(2026, 8, 7, 22),
  );
}

void main() {
  group('toCreateMap — o corpo que a regra aceita', () {
    test('post simples grava só o obrigatório', () {
      // A regra tem `hasOnly`: chave a mais e o servidor recusa a escrita
      // inteira. Empresa e foto ausentes não podem virar chaves nulas.
      final map = _post().toCreateMap();

      expect(map.keys.toSet(), {'uid', 'text', 'createdAt', 'deleted'});
      expect(map['deleted'], false);
    });

    test('empresa e foto entram quando existem', () {
      final map = _post(
        company: Company.shopee,
        imagePath: 'posts/uid-ana/p1.jpg',
      ).toCreateMap();

      expect(map['company'], 'shopee');
      expect(map['imagePath'], 'posts/uid-ana/p1.jpg');
    });

    test('a data é carimbo do servidor, nunca do aparelho', () {
      // Sem isto, um post com `createdAt` de 9999 lideraria o mural de todo
      // mundo para sempre — e `update` restrito impede até o autor de
      // corrigir. A regra confere `createdAt == request.time`.
      expect(_post().toCreateMap()['createdAt'], isA<FieldValue>());
    });

    test('nunca grava nome, foto ou apelido do autor', () {
      // Denormalizar o autor seria personificação de graça: a regra não tem
      // como conferir esses campos contra `profiles`.
      final keys = _post().toCreateMap().keys;

      expect(keys, isNot(contains('name')));
      expect(keys, isNot(contains('nickName')));
      expect(keys, isNot(contains('photoUrl')));
    });
  });

  group('fromMap — leitura defensiva', () {
    test('reconstrói o post', () {
      final post = Post.fromMap('p1', {
        'uid': 'uid-ana',
        'text': 'Dia puxado',
        'company': 'amazon',
        'imagePath': 'posts/uid-ana/p1.jpg',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 7, 22)),
        'deleted': false,
      });

      expect(post.uid, 'uid-ana');
      expect(post.company, Company.amazon);
      expect(post.hasImage, isTrue);
      expect(post.createdAt, DateTime(2026, 8, 7, 22));
    });

    test('empresa desconhecida vira null, não Mercado Livre', () {
      // `readEnum` cairia no fallback e desenharia uma empresa que o post não
      // tem. Campo opcional pede ausência, não chute.
      expect(Post.fromMap('p1', {'company': 'ifood'}).company, isNull);
      expect(Post.fromMap('p1', {'company': 123}).company, isNull);
      expect(Post.fromMap('p1', {}).company, isNull);
    });

    test('data ausente vira agora, para o post recém-criado ficar no topo', () {
      // `serverTimestamp()` chega nulo no snapshot local que o Firestore
      // entrega antes de o servidor confirmar.
      final antes = DateTime.now();
      final post = Post.fromMap('p1', {'uid': 'a'});

      expect(post.createdAt.isBefore(antes.subtract(const Duration(minutes: 1))),
          isFalse);
    });

    test('documento vazio não derruba a leitura', () {
      final post = Post.fromMap('p1', {});

      expect(post.uid, '');
      expect(post.text, '');
      expect(post.hasImage, isFalse);
      expect(post.deleted, isFalse);
    });

    test('tombstone é reconhecido', () {
      final post = Post.fromMap('p1', {'deleted': true, 'text': ''});

      expect(post.deleted, isTrue);
      expect(post.hasImage, isFalse);
    });

    test('caminho de imagem vazio não conta como imagem', () {
      expect(Post.fromMap('p1', {'imagePath': ''}).hasImage, isFalse);
    });
  });

  group('PostImage.pathFor — o caminho que a regra do Storage exige', () {
    test('é posts/{uid}/{postId}.jpg', () {
      // A `storage.rules` casa `posts/{userId}/{fileName}` e exige
      // `userId == auth.uid`, e a regra do Firestore confere o prefixo com
      // `matches('^posts/' + uid + '/.*')`. Mudar isto quebra as duas.
      expect(PostImage.pathFor('uid-ana', 'p1'), 'posts/uid-ana/p1.jpg');
    });
  });
}
