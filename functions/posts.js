/**
 * Os marcos do mural: curtidas e comentários.
 *
 * Ver `docs/specs/notificacoes.md`.
 */

import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

import { REGIAO } from './opcoes.js';
import { db } from './firebase.js';
import { enviar } from './push.js';
import { perfilDe } from './perfis.js';
import {
  PASSO_COMENTARIOS,
  PASSO_CURTIDAS,
  idDoMarco,
  marcoDe,
} from './marcos.js';
import * as texto from './texto.js';

export const curtidas = onDocumentCreated(
  { document: 'posts/{postId}/likes/{likerId}', region: REGIAO },
  (event) => marcoDoPost({ event, tipo: 'curtidas', passo: PASSO_CURTIDAS }),
);

export const comentarios = onDocumentCreated(
  { document: 'posts/{postId}/comments/{commentId}', region: REGIAO },
  (event) =>
    marcoDoPost({ event, tipo: 'comentarios', passo: PASSO_COMENTARIOS }),
);

/**
 * **A ordem das operações é a spec, não detalhe de implementação.**
 *
 *   contar → derivar o marco → marcador já existe? sai        (1 leitura)
 *          → ler o post (dono, lápide, trecho)
 *          → o autor É o dono? sai SEM CRIAR o marcador
 *          → lápide? sai
 *          → create() do marcador
 *          → enviar
 *
 * Duas linhas dessa sequência quebraram o primeiro desenho no papel, e as duas
 * estão comentadas onde acontecem.
 */
async function marcoDoPost({ event, tipo, passo }) {
  const { postId } = event.params;

  // Evento de criação sem documento — ver `amizade.js`, onde o emulador
  // entregou exatamente isso quando um batch apagou caminho inexistente.
  const doc = event.data;
  if (doc === undefined || !doc.exists) return;

  const total = await contar(postId, tipo);
  const marco = marcoDe(total, passo);
  if (marco === null) return;

  const marcador = db()
    .doc(`posts/${postId}`)
    .collection('marcos')
    .doc(idDoMarco(tipo, marco));

  // **Caminho comum: uma leitura e nada mais.** Nove entre dez curtidas param
  // aqui, e é por isso que o post só é lido depois.
  if ((await marcador.get()).exists) return;

  const post = await db().doc(`posts/${postId}`).get();
  if (!post.exists) return;

  const dono = post.get('uid');
  const autor = doc.get('uid');

  // **Sai SEM criar o marcador, e essa é a linha inteira.**
  //
  // Todo mundo curte o próprio post. Se esta saída marcasse, a primeira curtida
  // de verdade — a de outra pessoa — nunca seria anunciada, porque o marcador
  // do marco 1 já estaria posto. Sem marcar, a curtida seguinte chega com a
  // contagem em 2, deriva o marco 1 pela regra de `marcos.js`, e avisa.
  if (autor === dono) return;

  // **Reler o post antes de enviar não é zelo.** A regra impede curtir e
  // comentar em lápide, mas nada impede o dono apagar o post **entre** o
  // gatilho e o envio — e ele costuma apagar justamente quando o post está
  // atraindo atenção que não queria. "Seu post chegou a 10 curtidas" depois de
  // apagado é da mesma família do gesto que a lápide existe para evitar.
  if (post.get('deleted') === true) return;

  try {
    await marcador.create({ at: new Date(), total });
  } catch (e) {
    // Só `already-exists` é silêncio: outra invocação ganhou a corrida. Um
    // `catch` largo transformaria falha de rede em "já avisei" e perderia o
    // marco sem rastro.
    if (e?.code === 6 || e?.code === 'already-exists') return;
    throw e;
  }

  const aviso = await montarAviso({ tipo, marco, post, dono, autor });
  const aparelhos = await enviar({
    para: dono,
    aviso,
    // Colapso por (post, tipo): dois marcos de posts diferentes não se apagam,
    // e um segundo marco do mesmo post substitui o anterior na bandeja — que é
    // o que se quer, porque "10 curtidas" torna "primeira curtida" obsoleto.
    collapse: `${postId}_${tipo}`,
  });

  logger.info(tipo, { postId, marco, total, para: dono, aparelhos });
}

/**
 * `count()` e não contador incremental.
 *
 * A posição do `CLAUDE.md` — *"recomputado, nunca incrementado"* — vale aqui sem
 * adaptação, e a deriva seria pior do que um número feio numa tela: um contador
 * dois acima do real dispara o marco de 10 com oito curtidas, e **o marcador
 * congela essa mentira para sempre**. A agregação custa uma leitura para
 * qualquer post com menos de mil curtidas.
 *
 * Sem `catch` que devolva zero: colapsar "não consegui contar" em zero apagaria
 * o evento em silêncio. Deixar estourar é o que aciona a recuperação — a
 * próxima curtida refaz a conta.
 */
async function contar(postId, tipo) {
  const sub = tipo === 'curtidas' ? 'likes' : 'comments';
  const agregado = await db()
    .doc(`posts/${postId}`)
    .collection(sub)
    .count()
    .get();

  return agregado.data().count;
}

async function montarAviso({ tipo, marco, post, dono, autor }) {
  // O trecho é do texto **do próprio dono** — nunca do comentário de terceiro,
  // que apareceria na tela de bloqueio dele fora do alcance de qualquer regra.
  const trecho = texto.trechoDoPost(post.get('text'));

  if (tipo === 'curtidas') {
    // **Ninguém é nomeado, nem na primeira.** A regra de `likes` não chama
    // `bloqueioEntre`: quem foi bloqueado ainda curte. Nomear entregaria o nome
    // dele na tela de bloqueio da vítima, furando por push o bloqueio que a
    // regra do comentário sustenta.
    return texto.curtidas({ marco, para: dono, postId: post.id, trecho });
  }

  // No comentário a assimetria é deliberada: a regra de `comments` **chama**
  // `bloqueioEntre` nos dois sentidos, então quem comentou não é bloqueado de
  // ninguém, e o primeiro comentário pode nomear. O que nunca vai é o texto.
  const perfil = marco === 1 ? await perfilDe(autor) : null;

  return texto.comentarios({
    marco,
    nome: texto.primeiroNome(perfil),
    de: autor,
    para: dono,
    postId: post.id,
    trecho,
  });
}
