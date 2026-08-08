/// O que a tela de busca mostra depois de procurar um `@apelido`.
///
/// Fica aqui, e não dentro do `State` da tela, porque é a única parte desta
/// feature que o padrão de teste da casa alcança: o método que faz
/// `batch.commit()` não sobe sem Firebase, mas a regra que decide o rótulo do
/// botão é aritmética de estado — ver `docs/specs/amigos.md`.
library;

import 'package:iter/controller/nicknameController.dart';

/// Os dez estados do resultado da busca.
///
/// Três deles existem porque colapsá-los seria mentir, e o app já pagou por
/// esse erro uma vez: [naoEncontrado], [naoPublicado] e [falha] parecem a
/// mesma tela vazia e são causas diferentes — "esse apelido não é de ninguém",
/// "é de alguém que ainda não abriu o app" e "não deu para saber". O clima
/// desenhava sol quando a API caía pela mesma economia.
enum FriendshipStatus {
  /// Nada digitado.
  vazio,

  /// Fora de `^[a-z0-9._-]{3,20}$` depois de normalizar. Não vai à rede.
  apelidoInvalido,

  /// `nicknames/{apelido}` não existe.
  naoEncontrado,

  /// O apelido existe, `profiles/{uid}` não.
  ///
  /// É o estado **normal** de todo usuário anterior a esta entrega que ainda
  /// não reabriu o app, não um caso de borda.
  naoPublicado,

  /// O apelido é o meu.
  souEu,

  amigo,

  /// Eu convidei e ele ainda não respondeu.
  convidado,

  /// Ele me convidou e eu ainda não respondi.
  convidou,

  semRelacao,

  /// Sem rede, `permission-denied`, corpo inesperado.
  falha;

  /// O rótulo do botão do dialog. `null` = não há ação, botão desabilitado.
  ///
  /// É `null` e não `''` de propósito: o `ProfileDialog` passa isto direto
  /// para `onPressed`, e um `VoidCallback` nulo é o que desabilita o botão de
  /// verdade, em vez de deixá-lo clicável sem efeito.
  String? get actionLabel => switch (this) {
    semRelacao => 'Adicionar',
    convidou => 'Aceitar convite',
    convidado => 'Cancelar convite',
    amigo => 'Remover amigo',
    _ => null,
  };

  /// A frase que a tela diz. `null` quando o perfil na tela já se explica.
  String? get message => switch (this) {
    apelidoInvalido => 'Apelido inválido. De 3 a 20 caracteres, '
        'só letras, números, ponto, hífen e sublinhado.',
    naoEncontrado => 'Ninguém usa esse apelido.',
    naoPublicado => 'Esse apelido existe, mas o perfil ainda não foi '
        'publicado. Peça para o colega abrir o app.',
    souEu => 'Esse é você.',
    falha => 'Não foi possível buscar agora.',
    _ => null,
  };

  /// Se há um perfil para desenhar na tela.
  bool get hasProfile => switch (this) {
    souEu || amigo || convidado || convidou || semRelacao => true,
    _ => false,
  };
}

/// O apelido pronto para a busca, ou `null` quando nem vale ir à rede.
///
/// **Nem `resolveUid` nem `isAvailable` normalizam** — `normalize()` hoje só
/// roda em `suggestFrom` e em `change`. Digitar `Maria.S7` bateria em
/// `nicknames/Maria.S7`, documento que não existe, e a tela diria "ninguém usa
/// esse apelido" para um apelido que existe.
String? searchableNickname(String raw) {
  final normalized = NicknameController.normalize(raw);
  return NicknameController.isValid(normalized) ? normalized : null;
}

/// Quais perfis ainda faltam buscar.
///
/// Devolve `List` e não `Iterable` de propósito, e essa escolha é o conserto de
/// um bug real: `uids.where(...)` é **preguiçoso** e reavalia o filtro a cada
/// iteração. Percorrer o resultado duas vezes — uma para marcar o que entrou em
/// carregamento, outra para disparar as buscas — fazia a segunda passada
/// enxergar as marcas da primeira e devolver lista vazia. Nenhum perfil era
/// buscado, e todo mundo aparecia como "Entregador".
///
/// [known] são os já resolvidos, inclusive os que resolveram para `null` — um
/// perfil que não existe não deve ser pedido de novo a cada rolagem.
List<String> missingProfiles(
  Iterable<String> uids, {
  required Set<String> known,
  required Set<String> loading,
}) {
  final missing = <String>{};
  for (final uid in uids) {
    if (known.contains(uid) || loading.contains(uid)) continue;
    missing.add(uid);
  }
  return missing.toList();
}

/// Qual é a relação com quem a busca encontrou.
///
/// Recebe fatos, não documentos: assim a regra é testável sem Firestore e a
/// mesma resposta serve à tela de busca e ao tile da lista.
///
/// A ordem de precedência é o que importa aqui, e cada degrau evita um erro
/// concreto:
///
/// 1. **[souEu]** antes de tudo — sem isso a auto-amizade viraria um botão
///    "Adicionar" que o servidor recusa.
/// 2. **[amigo] vence convite pendente.** Marcador que sobrou de um aceite
///    não pode fazer o botão voltar a "Aceitar": o segundo aceite bateria numa
///    aresta que já existe.
/// 3. **[convidou] vence [convidado]** no convite mútuo. Os dois se
///    convidaram, e aceitar é o toque que resolve — oferecer "Cancelar" ali
///    deixaria os dois esperando o outro.
FriendshipStatus resolveFriendship({
  required bool isMe,
  required bool hasProfile,
  required bool isFriend,
  required bool invitedByMe,
  required bool invitedMe,
}) {
  if (isMe) return FriendshipStatus.souEu;
  if (!hasProfile) return FriendshipStatus.naoPublicado;
  if (isFriend) return FriendshipStatus.amigo;
  if (invitedMe) return FriendshipStatus.convidou;
  if (invitedByMe) return FriendshipStatus.convidado;
  return FriendshipStatus.semRelacao;
}
