import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/comment.dart';

void main() {
  group('toCreateMap — o corpo que a regra aceita', () {
    test('grava só uid, text e createdAt', () {
      // A regra tem `hasAll` e `hasOnly`: chave a mais e o servidor recusa a
      // escrita inteira.
      final map = Comment(
        id: 'c1',
        uid: 'uid-bia',
        text: 'Boa, parceiro!',
        createdAt: DateTime(2026, 8, 9, 12),
      ).toCreateMap();

      expect(map.keys.toSet(), {'uid', 'text', 'createdAt'});
      expect(map['uid'], 'uid-bia');
      expect(map['text'], 'Boa, parceiro!');
    });

    test('o carimbo é do servidor, nunca o relógio de quem escreve', () {
      // `createdAt == request.time` na regra: sem isso, um comentário datado
      // de 9999 fixa-se no fim da thread para sempre.
      final map = Comment(
        id: 'c1',
        uid: 'uid-bia',
        text: 'oi',
        createdAt: DateTime(1970),
      ).toCreateMap();

      expect(map['createdAt'], isA<FieldValue>());
    });

    test('o teto é o mesmo da regra', () {
      expect(Comment.maxLength, 500);
    });
  });

  group('fromMap', () {
    test('lê o que o Firestore devolve', () {
      final comment = Comment.fromMap('c1', {
        'uid': 'uid-ana',
        'text': 'Chegou tarde?',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 9, 7, 30)),
      });

      expect(comment.id, 'c1');
      expect(comment.uid, 'uid-ana');
      expect(comment.text, 'Chegou tarde?');
      expect(comment.createdAt, DateTime(2026, 8, 9, 7, 30));
    });

    test('carimbo ainda não confirmado vira AGORA, não a época zero', () {
      // `serverTimestamp()` chega nulo no snapshot local que o Firestore
      // entrega antes de o servidor confirmar. Virar 1970 mandaria o
      // comentário recém-escrito para o topo da thread e o traria de volta
      // sozinho um segundo depois.
      final antes = DateTime.now().subtract(const Duration(seconds: 5));
      final comment = Comment.fromMap('c1', {
        'uid': 'uid-ana',
        'text': 'oi',
        'createdAt': null,
      });

      expect(comment.createdAt.isAfter(antes), isTrue);
    });

    test('documento capenga não derruba a thread', () {
      // Um comentário sem campo nenhum tem de virar objeto vazio, não exceção:
      // a lista inteira sumiria por causa de um documento.
      final comment = Comment.fromMap('c1', {});

      expect(comment.uid, '');
      expect(comment.text, '');
    });
  });
}
