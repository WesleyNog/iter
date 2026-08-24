import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/friendShare.dart';

void main() {
  group('o que sai do app', () {
    test('o QR carrega o apelido, e só ele', () {
      expect(friendQrPayload('meu-yzwy'), 'iter://amigo/meu-yzwy');
    });

    test('a mensagem diz o que fazer com o apelido', () {
      // Sem link clicável, "@meu-yzwy" sozinho não é instrução nenhuma para
      // quem recebe — e quem recebe pode nem ter o app.
      final texto = friendShareText('meu-yzwy', name: 'Wesley Nogueira');

      expect(texto, contains('@meu-yzwy'));
      expect(texto, contains('Wesley Nogueira'));
      expect(texto, contains('Adicionar amigo'));
    });

    test('sem nome, a mensagem continua completa', () {
      final texto = friendShareText('meu-yzwy');

      expect(texto, startsWith('Me adiciona no iter: @meu-yzwy'));
      expect(texto, contains('Adicionar amigo'));
    });

    test('nome em branco não deixa um espaço pendurado', () {
      expect(
        friendShareText('meu-yzwy', name: '   '),
        startsWith('Me adiciona'),
      );
    });
  });

  group('o que entra pela câmera', () {
    test('o payload do próprio app', () {
      expect(nicknameFromScan('iter://amigo/meu-yzwy'), 'meu-yzwy');
    });

    test('o @apelido escrito à mão num QR genérico', () {
      expect(nicknameFromScan('@meu-yzwy'), 'meu-yzwy');
      expect(nicknameFromScan('  @meu-yzwy  '), 'meu-yzwy');
    });

    test('texto solto não vira busca, mesmo parecendo um apelido', () {
      // O caso que a escrita do teste revelou: `normalize` troca espaço por
      // hífen e tira acento, então "Promoção 50" vira `promocao-50` e **passa**
      // na régua do apelido. Sem o `@`, o cartaz da parede do galpão viraria
      // uma busca, e a tela diria "ninguém usa esse apelido".
      expect(nicknameFromScan('Promoção 50'), isNull);
      expect(nicknameFromScan('meu-yzwy'), isNull);
      expect(nicknameFromScan('NOTA FISCAL 12345'), isNull);
    });

    test('normaliza como a busca normaliza', () {
      // A mesma régua de `searchableNickname`: sem ela, `Maria.S7` bateria em
      // um documento que não existe e a tela diria "ninguém usa esse apelido".
      expect(nicknameFromScan('@Maria.S7'), 'maria.s7');
      expect(nicknameFromScan('iter://amigo/Maria.S7'), 'maria.s7');
    });

    test('esquema alheio é recusado, não raspado', () {
      // O caso que faria a feature parecer quebrada: a câmera lê o QR da
      // encomenda, o app pega o último pedaço da URL e busca por "promo".
      expect(nicknameFromScan('https://loja.com/promo'), isNull);
      expect(nicknameFromScan('https://iter-mn.web.app/u/meu-yzwy'), isNull);
      expect(nicknameFromScan('WIFI:S:Galpao;T:WPA;P:senha123;;'), isNull);
      expect(nicknameFromScan('mailto:alguem@example.com'), isNull);
    });

    test('esquema certo com caminho errado também é recusado', () {
      expect(nicknameFromScan('iter://rota/123'), isNull);
      expect(nicknameFromScan('iter://amigo'), isNull);
      expect(nicknameFromScan('iter://amigo/'), isNull);
    });

    test('apelido inválido não vira busca', () {
      // Curto, longo e com caractere fora da régua: nem vale ir à rede.
      expect(nicknameFromScan('@ab'), isNull);
      expect(nicknameFromScan('@${'a' * 21}'), isNull);
      expect(nicknameFromScan(''), isNull);
      expect(nicknameFromScan('   '), isNull);
    });

    test('a leitura desfaz o que o compartilhamento faz', () {
      // A volta completa: o que o QR de alguém carrega é exatamente o que a
      // câmera de outra pessoa precisa devolver.
      const apelido = 'wesley-efmg';
      expect(nicknameFromScan(friendQrPayload(apelido)), apelido);
    });
  });
}
