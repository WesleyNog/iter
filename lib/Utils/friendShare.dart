/// O convite que sai do app: o texto que vai para a folha de
/// compartilhamento e o conteúdo do QR Code.
///
/// Fica em `Utils/` e não na tela porque é a **fronteira** da feature: tudo
/// que sai do app por aqui vira mensagem em rede alheia, e tudo que entra vem
/// de uma câmera lendo um quadrado que qualquer um pode ter gerado. As duas
/// pontas são função pura, testável sem câmera e sem Firestore.
///
/// **O que sai é o `@apelido`, e só ele.** Nunca o uid, nunca o nome do
/// documento `user/{uid}`: o apelido já é a chave pública da busca — é o que a
/// `AddFriend` pede — e resolver apelido → uid passa por `nicknames/{apelido}`,
/// que a regra deixa ler por id. Colocar o uid no QR não abriria nada que já
/// não esteja aberto, mas espalharia por print e captura de tela o
/// identificador que as regras usam como sujeito; o apelido é trocável, o uid
/// não. Ver `docs/specs/amigos.md`.
library;

import 'package:iter/Utils/friendship.dart';

/// `iter://amigo/<apelido>` — o esquema do próprio app.
///
/// **Não é um `https://` porque ainda não existe página nenhuma para ele
/// apontar.** Um link quebrado compartilhado em rede social é pior do que
/// apelido nenhum: quem toca vê erro e conclui que o app é que está quebrado.
/// O caminho para o link de verdade é uma página no Firebase Hosting
/// (`iter-mn.web.app`) e está registrado como dívida; quando existir, é esta
/// função e [nicknameFromScan] que mudam, e mais nada — por isso o formato
/// mora aqui e não interpolado dentro de um widget.
String friendQrPayload(String nickName) => 'iter://amigo/$nickName';

/// A mensagem que a folha de compartilhamento manda para o WhatsApp, o e-mail
/// ou a área de transferência.
///
/// Carrega a **instrução** junto com o apelido, e é de propósito: sem link
/// clicável, receber "@meu-yzwy" sozinho não diz o que fazer com aquilo. Quem
/// recebe pode nem ter o app.
String friendShareText(String nickName, {String? name}) {
  final quem = name == null || name.trim().isEmpty
      ? 'Me adiciona no iter'
      : 'Sou ${name.trim()} no iter';

  return '$quem: @$nickName\n'
      'Busque por esse apelido em Amigos › Adicionar amigo.';
}

/// O apelido que veio de uma leitura de QR, ou `null` quando o código não é
/// um convite deste app.
///
/// **Recusar é o caso comum**, não a exceção: a câmera lê etiqueta de encomenda,
/// QR de Wi-Fi, link de nota fiscal e o cartaz da parede do galpão. Devolver o
/// último pedaço de qualquer URL transformaria `https://loja.com/promo` em uma
/// busca por "promo" — e a tela diria "ninguém usa esse apelido", culpando o
/// apelido por um código que nunca foi um convite.
///
/// Só aceita código que **se declara** um convite: o payload de
/// [friendQrPayload] ou um `@apelido`. Texto solto não entra, e essa foi uma
/// correção durante a escrita dos testes: `NicknameController.normalize`
/// transforma espaço em hífen e acento em letra simples, então "Promoção 50"
/// vira `promocao-50`, que **passa** na régua `^[a-z0-9._-]{3,20}$`. O cartaz
/// do galpão viraria uma busca, e a tela responderia "ninguém usa esse
/// apelido" — culpando o apelido por um código que nunca foi um convite. O `@`
/// é o que separa "isto é um apelido" de "isto é uma frase".
String? nicknameFromScan(String raw) {
  final texto = raw.trim();
  if (texto.isEmpty) return null;

  // `Uri.tryParse` engole quase tudo — 'meu-yzwy' vira um Uri de caminho
  // relativo, sem esquema. Por isso a decisão é pelo **esquema**, e só depois
  // pelo caminho.
  final uri = Uri.tryParse(texto);
  if (uri != null && uri.scheme.isNotEmpty) {
    if (uri.scheme.toLowerCase() != 'iter') return null;

    // `iter://amigo/<apelido>`: o apelido é o último pedaço não vazio.
    final partes = [
      uri.host,
      ...uri.pathSegments,
    ].where((p) => p.isNotEmpty).toList();
    if (partes.length < 2 || partes.first.toLowerCase() != 'amigo') return null;

    return searchableNickname(partes.last);
  }

  // `@apelido`. O `@` não faz parte do id do documento em `nicknames` — é o
  // enfeite da tela —, mas aqui ele é a declaração de que aquilo é um apelido,
  // e não uma frase que por acaso sobrevive à normalização.
  if (!texto.startsWith('@')) return null;

  return searchableNickname(texto.substring(1));
}
