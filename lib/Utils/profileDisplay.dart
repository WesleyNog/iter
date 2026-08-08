/// Como desenhar um [PublicProfile] na tela.
///
/// Existe porque a mesma regra estava copiada em três lugares — o tile de
/// amigo, a linha do ranking e o card do mural — e as três já divergiam.
library;

import 'package:flutter/widgets.dart';
import 'package:iter/model/publicProfile.dart';

/// O nome a desenhar: nome, senão `@apelido`, senão o genérico.
///
/// Uma função só porque a mesma regra estava copiada em três telas — o tile de
/// amigo, a linha do ranking e o card do mural — e já divergiam: uma não
/// aparava o nome, e as três tratavam apelido **vazio** como apelido presente,
/// desenhando um `@` pelado. O resto do app protege contra isso; estas não
/// protegiam.
String displayName(PublicProfile? profile, {String? nickNameFallback}) {
  final name = profile?.name.trim() ?? '';
  if (name.isNotEmpty) return name;

  final nick = (profile?.nickName ?? nickNameFallback)?.trim() ?? '';
  return nick.isEmpty ? 'Entregador' : '@$nick';
}

/// A letra do avatar. Ignora o `@` — senão todo perfil sem nome teria a mesma.
String displayInitial(String name) {
  final clean = name.replaceAll('@', '').trim();
  return clean.characters.firstOrNull?.toUpperCase() ?? '?';
}

/// Se há foto de verdade para carregar.
///
/// String vazia não é ausência para o `NetworkImage`: ele tenta baixar `''` e
/// lança `No host specified in URI` dentro do pipeline de imagem, deixando o
/// círculo vazio **sem** a letra de fallback.
bool hasPhoto(String? url) => url != null && url.trim().isNotEmpty;
