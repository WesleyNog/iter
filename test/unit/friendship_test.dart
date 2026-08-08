import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/friendship.dart';

FriendshipStatus _resolve({
  bool isMe = false,
  bool hasProfile = true,
  bool isFriend = false,
  bool invitedByMe = false,
  bool invitedMe = false,
}) {
  return resolveFriendship(
    isMe: isMe,
    hasProfile: hasProfile,
    isFriend: isFriend,
    invitedByMe: invitedByMe,
    invitedMe: invitedMe,
  );
}

void main() {
  group('resolveFriendship — a relação', () {
    test('sem nenhuma relação, oferece adicionar', () {
      expect(_resolve(), FriendshipStatus.semRelacao);
    });

    test('eu convidei', () {
      expect(_resolve(invitedByMe: true), FriendshipStatus.convidado);
    });

    test('ele me convidou', () {
      expect(_resolve(invitedMe: true), FriendshipStatus.convidou);
    });

    test('já é amigo', () {
      expect(_resolve(isFriend: true), FriendshipStatus.amigo);
    });

    test('sou eu, mesmo com convite ou amizade gravada', () {
      expect(_resolve(isMe: true), FriendshipStatus.souEu);
      expect(
        _resolve(isMe: true, isFriend: true, invitedMe: true),
        FriendshipStatus.souEu,
      );
    });

    test('apelido existe e perfil não é diferente de não encontrado', () {
      // O estado normal de quem já usava o app antes desta entrega e ainda não
      // reabriu. Dizer "ninguém usa esse apelido" aqui seria falso.
      expect(_resolve(hasProfile: false), FriendshipStatus.naoPublicado);
    });

    test('amizade vence convite pendente', () {
      // Marcador que sobrou de um aceite não pode fazer o botão voltar a
      // "Aceitar": o segundo aceite bateria numa aresta que já existe, e
      // `set` sobre documento existente é `update`.
      expect(
        _resolve(isFriend: true, invitedMe: true),
        FriendshipStatus.amigo,
      );
      expect(
        _resolve(isFriend: true, invitedByMe: true),
        FriendshipStatus.amigo,
      );
      expect(
        _resolve(isFriend: true, invitedByMe: true, invitedMe: true),
        FriendshipStatus.amigo,
      );
    });

    test('convite mútuo resolve para aceitar, e só para um estado', () {
      // Os dois se convidaram antes de qualquer aceite: quatro marcadores no
      // banco, um único botão na tela. Oferecer "Cancelar" deixaria os dois
      // esperando o outro resolver.
      expect(
        _resolve(invitedByMe: true, invitedMe: true),
        FriendshipStatus.convidou,
      );
    });
  });

  group('actionLabel — o que o botão diz', () {
    test('cada relação tem o próprio rótulo', () {
      expect(FriendshipStatus.semRelacao.actionLabel, 'Adicionar');
      expect(FriendshipStatus.convidou.actionLabel, 'Aceitar convite');
      expect(FriendshipStatus.convidado.actionLabel, 'Cancelar convite');
      expect(FriendshipStatus.amigo.actionLabel, 'Remover amigo');
    });

    test('estado sem ação devolve null, para o botão nascer desabilitado', () {
      // `null` e não `''`: é o `VoidCallback` nulo que desabilita o
      // `FilledButton` de verdade, em vez de deixá-lo clicável sem efeito.
      for (final status in [
        FriendshipStatus.vazio,
        FriendshipStatus.apelidoInvalido,
        FriendshipStatus.naoEncontrado,
        FriendshipStatus.naoPublicado,
        FriendshipStatus.souEu,
        FriendshipStatus.falha,
      ]) {
        expect(status.actionLabel, isNull, reason: '$status');
      }
    });
  });

  group('message — as três causas que parecem a mesma tela vazia', () {
    test('não encontrado, não publicado e falha dizem coisas diferentes', () {
      final frases = {
        FriendshipStatus.naoEncontrado.message,
        FriendshipStatus.naoPublicado.message,
        FriendshipStatus.falha.message,
      };

      expect(frases.length, 3, reason: 'as três não podem coincidir');
      expect(frases.any((f) => f == null), isFalse);
    });

    test('quem tem perfil na tela não precisa de frase', () {
      expect(FriendshipStatus.semRelacao.message, isNull);
      expect(FriendshipStatus.amigo.message, isNull);
      expect(FriendshipStatus.convidado.message, isNull);
      expect(FriendshipStatus.convidou.message, isNull);
    });
  });

  group('hasProfile — se há perfil para desenhar', () {
    test('só os estados de relação desenham perfil', () {
      expect(FriendshipStatus.semRelacao.hasProfile, isTrue);
      expect(FriendshipStatus.amigo.hasProfile, isTrue);
      expect(FriendshipStatus.convidado.hasProfile, isTrue);
      expect(FriendshipStatus.convidou.hasProfile, isTrue);
      expect(FriendshipStatus.souEu.hasProfile, isTrue);

      expect(FriendshipStatus.vazio.hasProfile, isFalse);
      expect(FriendshipStatus.apelidoInvalido.hasProfile, isFalse);
      expect(FriendshipStatus.naoEncontrado.hasProfile, isFalse);
      expect(FriendshipStatus.naoPublicado.hasProfile, isFalse);
      expect(FriendshipStatus.falha.hasProfile, isFalse);
    });
  });

  group('missingProfiles — quem ainda falta buscar', () {
    test('devolve quem não foi resolvido nem está carregando', () {
      expect(
        missingProfiles(
          ['ana', 'bia', 'zeca'],
          known: {'bia'},
          loading: {'zeca'},
        ),
        ['ana'],
      );
    });

    test('não repete uid que aparece duas vezes na entrada', () {
      // O mesmo autor em dois convites não pode virar duas buscas.
      expect(
        missingProfiles(
          ['ana', 'bia', 'ana'],
          known: {},
          loading: {},
        ),
        ['ana', 'bia'],
      );
    });

    test('perfil que resolveu para null não é pedido de novo', () {
      // `known` são as chaves do mapa, e a chave existe mesmo com valor nulo:
      // quem não tem projeção publicada não pode ser buscado a cada rolagem.
      expect(missingProfiles(['ana'], known: {'ana'}, loading: {}), isEmpty);
    });

    test('percorrer o resultado duas vezes devolve a mesma coisa', () {
      // O bug que este teste existe para impedir: `uids.where(...)` é
      // preguiçoso e reavalia o filtro a cada iteração. Marcar os uids como
      // "carregando" na primeira passada fazia a segunda enxergar as próprias
      // marcas e devolver vazio — nenhum perfil era buscado, e todo mundo
      // aparecia como "Entregador".
      final loading = <String>{};
      final missing = missingProfiles(
        ['ana', 'bia'],
        known: {},
        loading: loading,
      );

      loading.addAll(missing);

      expect(missing, ['ana', 'bia']);
      expect(missing.toList(), ['ana', 'bia']);
    });
  });

  group('searchableNickname — normalizar antes da rede', () {
    test('maiúscula e acento viram o apelido gravado', () {
      // `resolveUid` não normaliza. Sem isto, `Maria.S7` bateria em
      // `nicknames/Maria.S7` e a tela diria "ninguém usa esse apelido" para um
      // apelido que existe.
      expect(searchableNickname('Maria.S7'), 'maria.s7');
      expect(searchableNickname('  JOÃO.P3  '), 'joao.p3');
    });

    test('espaço vira hífen, que é onde o apelido foi parar', () {
      // `normalize` é a mesma função que `suggestFrom` usa para *gerar* o
      // apelido, então quem digita o nome com espaço cai exatamente no
      // documento que existe. Não é tolerância: é simetria.
      expect(searchableNickname('maria silva'), 'maria-silva');
    });

    test('curto demais, vazio ou longo demais não vai à rede', () {
      expect(searchableNickname('ab'), isNull);
      expect(searchableNickname(''), isNull);
      expect(searchableNickname('   '), isNull);
      expect(searchableNickname('a' * 21), isNull);
      // Normaliza para vazio: não há o que procurar.
      expect(searchableNickname('!!!'), isNull);
    });

    test('apelido já normalizado passa intacto', () {
      expect(searchableNickname('wesley.n4'), 'wesley.n4');
      expect(searchableNickname('joao-p_3'), 'joao-p_3');
    });
  });
}
