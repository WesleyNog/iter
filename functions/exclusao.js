/**
 * As decisões puras da exclusão de conta: quais caminhos apagar, e em que ordem.
 *
 * Separadas de `conta.js` pela mesma razão de `rank.js` e `texto.js`: testáveis
 * com `node --test`, sem emulador. Ver `docs/specs/exclusao-de-conta.md`.
 */

/**
 * As duas arestas de amizade entre [uid] e [outro].
 *
 * **Apagadas antes dos marcadores, sempre.** O gatilho `aceite` dispara no
 * apagar de `friendRequests/{a}/outgoing/{b}` e decide lendo se a aresta
 * `friends/{a}/list/{b}` existe: com a aresta de pé, apagar o marcador manda
 * "fulano aceitou seu convite" para o ex-amigo de uma conta que acabou de
 * deixar de existir.
 */
export function arestas(uid, outro) {
  return [`friends/${uid}/list/${outro}`, `friends/${outro}/list/${uid}`];
}

/**
 * Os quatro marcadores de convite entre os dois, nas duas direções — os mesmos
 * quatro que `FriendController.severTies` apaga. Apagar marcador inexistente é
 * no-op, então não é preciso saber quais existem.
 */
export function marcadores(uid, outro) {
  return [
    `friendRequests/${uid}/incoming/${outro}`,
    `friendRequests/${uid}/outgoing/${outro}`,
    `friendRequests/${outro}/incoming/${uid}`,
    `friendRequests/${outro}/outgoing/${uid}`,
  ];
}

/**
 * O aviso de ranking envolve [uid]?
 *
 * O id é `{passado}_{passador}_{criterio}_{mes}_{dia}` (`ranking.js`) e o corpo
 * é só `at`, então o id é o único lugar onde a pessoa aparece. Comparar as duas
 * primeiras partes, e não procurar o uid na string: `ana` está contido em
 * `mariana`, e um `includes` apagaria o aviso de quem continua no app.
 *
 * O split é seguro porque uid do Firebase Auth é alfanumérico — não tem `_`.
 */
export function avisoEnvolve(id, uid) {
  const [passado, passador] = id.split('_');
  return passado === uid || passador === uid;
}

/**
 * Já é lápide? Evita regravar, a cada repetição da limpeza, um post que já foi
 * apagado — pela própria pessoa, antes, ou por uma execução anterior.
 *
 * `imagePath` ausente conta como nulo: é o formato dos posts sem foto.
 */
export function ehLapide(post) {
  return post.deleted === true
    && post.text === ''
    && (post.imagePath ?? null) === null;
}

/** A lápide, na forma exata que `PostController.erase` grava. */
export const LAPIDE = Object.freeze({ deleted: true, text: '', imagePath: null });
