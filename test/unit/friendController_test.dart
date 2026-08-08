import 'package:flutter_test/flutter_test.dart';
import 'package:iter/controller/friendController.dart';

void main() {
  group('sortByStamp — a ordem da lista', () {
    test('mais recente primeiro', () {
      final ordem = FriendController.sortByStamp([
        (uid: 'antigo', at: DateTime(2026, 1, 10)),
        (uid: 'novo', at: DateTime(2026, 8, 7)),
        (uid: 'meio', at: DateTime(2026, 5, 2)),
      ]);

      expect(ordem, ['novo', 'meio', 'antigo']);
    });

    test('empate resolve pelo uid, para a ordem não dançar', () {
      final momento = DateTime(2026, 8, 7, 10);
      final ordem = FriendController.sortByStamp([
        (uid: 'zeca', at: momento),
        (uid: 'ana', at: momento),
        (uid: 'bia', at: momento),
      ]);

      expect(ordem, ['ana', 'bia', 'zeca']);
    });

    test('lista vazia devolve lista vazia', () {
      expect(FriendController.sortByStamp([]), isEmpty);
    });
  });

  group('pendingOnly — convite de quem já é amigo não é convite', () {
    test('tira da caixa quem já está na lista', () {
      // O marcador que sobra de um aceite mal terminado: sem este filtro, o
      // botão diria "Aceitar" para quem já é amigo e o toque bateria numa
      // aresta que já existe.
      expect(
        FriendController.pendingOnly(['ana', 'bia', 'zeca'], ['bia']),
        ['ana', 'zeca'],
      );
    });

    test('sem amigo nenhum, tudo continua pendente', () {
      expect(
        FriendController.pendingOnly(['ana', 'bia'], []),
        ['ana', 'bia'],
      );
    });

    test('todos já amigos esvazia a caixa', () {
      expect(
        FriendController.pendingOnly(['ana', 'bia'], ['bia', 'ana']),
        isEmpty,
      );
    });

    test('preserva a ordem que chegou', () {
      expect(
        FriendController.pendingOnly(['zeca', 'ana', 'bia'], ['ana']),
        ['zeca', 'bia'],
      );
    });
  });

  group('caminhos das coleções', () {
    test('a aresta e o convite moram sob o uid do dono', () {
      // O id do documento é o dado: a regra decide olhando o caminho, então
      // trocar esses nomes quebra a segurança em silêncio.
      expect(FriendController.friendsPath('abc'), 'friends/abc/list');
      expect(
        FriendController.incomingPath('abc'),
        'friendRequests/abc/incoming',
      );
      expect(
        FriendController.outgoingPath('abc'),
        'friendRequests/abc/outgoing',
      );
    });
  });
}
