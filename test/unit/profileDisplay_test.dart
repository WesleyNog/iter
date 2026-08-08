import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/model/publicProfile.dart';

PublicProfile _profile({String name = '', String? nickName}) {
  return PublicProfile(
    uid: 'uid-ana',
    name: name,
    nickName: nickName,
    updatedAt: '2026-08-07T10:00:00.000',
  );
}

void main() {
  group('displayName — a regra que estava copiada em três telas', () {
    test('nome ganha do apelido', () {
      expect(displayName(_profile(name: 'Ana', nickName: 'ana.a1')), 'Ana');
    });

    test('sem nome, o apelido vira o título', () {
      expect(displayName(_profile(nickName: 'ana.a1')), '@ana.a1');
    });

    test('sem perfil nenhum, o genérico', () {
      expect(displayName(null), 'Entregador');
    });

    test('o nome vem aparado', () {
      // O ranking devolvia `profile!.name` cru depois de testar o aparado:
      // um perfil com espaço à esquerda saía diferente em cada tela, e a
      // inicial do avatar virava um círculo em branco.
      expect(displayName(_profile(name: '  Ana  ')), 'Ana');
    });

    test('apelido em branco não é apelido', () {
      // As três telas desenhavam um "@" pelado. O resto do app já protegia
      // contra isso; estas não protegiam.
      expect(displayName(_profile(nickName: '')), 'Entregador');
      expect(displayName(_profile(nickName: '   ')), 'Entregador');
    });

    test('o fallback só entra quando o perfil não tem apelido', () {
      expect(
        displayName(null, nickNameFallback: 'maria.s7'),
        '@maria.s7',
      );
      expect(
        displayName(_profile(nickName: 'ana.a1'), nickNameFallback: 'x'),
        '@ana.a1',
      );
    });
  });

  group('displayInitial — a letra do avatar', () {
    test('ignora o @, senão todo perfil sem nome teria a mesma', () {
      expect(displayInitial('@ana.a1'), 'A');
      expect(displayInitial('Ana Souza'), 'A');
    });

    test('vazio não quebra', () {
      expect(displayInitial(''), '?');
      expect(displayInitial('   '), '?');
      expect(displayInitial('@'), '?');
    });

    test('emoji conta como um caractere só', () {
      expect(displayInitial('👷 Ana'), '👷');
    });
  });

  group('hasPhoto — string vazia não é ausência', () {
    test('vazio é o mesmo que não ter', () {
      // `NetworkImage('')` lança "No host specified in URI" dentro do
      // pipeline de imagem e deixa o círculo vazio **sem** a letra.
      expect(hasPhoto(null), isFalse);
      expect(hasPhoto(''), isFalse);
      expect(hasPhoto('   '), isFalse);
    });

    test('url de verdade passa', () {
      expect(hasPhoto('https://lh3.googleusercontent.com/foto'), isTrue);
    });
  });
}
