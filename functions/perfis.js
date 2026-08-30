/**
 * A vitrine pública de alguém, do lado do servidor.
 *
 * `profiles/{uid}` é a **única** fonte de nome e foto — nunca um campo dentro do
 * post, do comentário ou do convite. Autor denormalizado é personificação de
 * graça: a regra não tem como conferi-lo contra a projeção, e a spec de amigos
 * registra isso. Vale aqui igual, com um agravante: o que sai daqui vai para a
 * tela de bloqueio de outra pessoa.
 */

import { db } from './firebase.js';

/**
 * `null` quando o perfil não existe.
 *
 * Distinguir isso de "existe e está sem nome" é o que deixa quem chama escolher
 * o fallback certo — a mesma disciplina do `ProfileController.fetch` no app, e
 * do `getWeather` antes dele.
 */
export async function perfilDe(uid) {
  const doc = await db().doc(`profiles/${uid}`).get();
  return doc.exists ? doc.data() : null;
}
