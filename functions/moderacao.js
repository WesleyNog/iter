/**
 * A moderação automática do mural. Ver `docs/specs/moderacao-automatica.md`.
 *
 * `onDocumentCreated` e **nunca** `onWrite`: a lápide que esta função grava
 * re-dispararia um `onWrite` — o loop de gatilho que o CLAUDE.md avisa que
 * custa dinheiro. `onCreate` não dispara em update, por construção.
 *
 * `retry: true`, como o `failurePolicy` da exclusão de conta — e pela mesma
 * razão todo passo é **idempotente**: a fonte é `event.data`, o snapshot do
 * documento criado, nunca uma releitura. Rodar duas vezes grava os mesmos
 * bytes nos mesmos lugares, e o emulador prova rodando duas vezes.
 *
 * A ordem das operações é a spec, não detalhe:
 *
 *   classificar → veredito
 *     'nada'      → fim, sem rastro
 *     'remover'   → quarentena (doc, depois foto) → lápide/delete → denúncia
 *     'denunciar' → denúncia
 *
 * Quarentena ANTES da lápide porque a lápide destrói (`text: ''`, sem volta
 * pelas regras): se a função morrer no meio, o pior estado possível é
 * "original preservado e post ainda de pé por um retry" — nunca "post
 * destruído e original perdido". E a quarentena existe pelos dois erros:
 * máquina errou → dá para restaurar; máquina acertou → é evidência, e
 * destruir evidência do pior crime é o oposto do dever (preservar e
 * denunciar — SaferNet/autoridade — é do dono, documentado na spec).
 */

import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { FieldValue } from 'firebase-admin/firestore';

import { REGIAO } from './opcoes.js';
import { bucket, db } from './firebase.js';
import { classificar } from './gemini.js';
import { veredito } from './veredito.js';

export const moderacaoPosts = onDocumentCreated(
  { document: 'posts/{postId}', region: REGIAO, retry: true, timeoutSeconds: 120 },
  (event) => {
    // Evento de criação sem documento — ver `amizade.js`.
    if (event.data === undefined || !event.data.exists) return undefined;
    return moderar({
      tipo: 'post',
      postId: event.params.postId,
      dados: event.data.data(),
    });
  },
);

export const moderacaoComentarios = onDocumentCreated(
  { document: 'posts/{postId}/comments/{commentId}', region: REGIAO, retry: true, timeoutSeconds: 120 },
  (event) => {
    if (event.data === undefined || !event.data.exists) return undefined;
    return moderar({
      tipo: 'comentario',
      postId: event.params.postId,
      commentId: event.params.commentId,
      dados: event.data.data(),
    });
  },
);

/**
 * Exportada sem o envelope do gatilho pela razão de `apagarDadosDe` em
 * `conta.js`: o emulador a chama DUAS vezes com os mesmos dados para provar
 * que repetir não quebra nem duplica.
 */
export async function moderar({ tipo, postId, commentId = null, dados }) {
  // Lápide recriada por algum reparo futuro: não há o que julgar num
  // documento que já nasceu apagado.
  if (dados.deleted === true) return;

  const resultado = await classificar({
    texto: dados.text ?? '',
    imagePath: tipo === 'post' ? dados.imagePath ?? null : null,
  });
  const v = veredito(resultado);
  if (v.acao === 'nada') return;

  const alvo = tipo === 'post' ? `p_${postId}` : `c_${postId}_${commentId}`;
  logger.info('moderacao', { alvo, acao: v.acao, categorias: v.categorias, postId });

  if (v.acao === 'remover') {
    await quarentenar({ alvo, tipo, postId, commentId, dados, v });
    await remover({ tipo, postId, commentId });
  }

  // A denúncia automática cai na MESMA fila do painel: `__maquina` no lugar
  // do uid (nenhum uid real colide), agrupada por alvo com as denúncias
  // humanas. `reason` é a categoria líder; `removeu` diz ao cartão se a
  // máquina agiu ou só sinalizou.
  await db().doc(`reports/${alvo}__maquina`).set({
    uid: 'maquina',
    postId,
    ...(tipo === 'comentario' && { commentId }),
    reason: v.categorias[0] ?? 'resposta-invalida',
    categorias: v.categorias,
    ...(v.confianca != null && { confianca: v.confianca }),
    removeu: v.acao === 'remover',
    at: FieldValue.serverTimestamp(),
  });
}

/** O doc primeiro — o texto é o que não pode se perder —, a foto depois. */
async function quarentenar({ alvo, tipo, postId, commentId, dados, v }) {
  const imagePath = tipo === 'post' ? dados.imagePath ?? null : null;
  const destinoFoto = imagePath
    ? `quarentena/${alvo}/${imagePath.split('/').pop()}`
    : null;

  await db().doc(`quarentena/${alvo}`).set({
    alvo,
    tipo,
    postId,
    ...(tipo === 'comentario' && { commentId }),
    uid: dados.uid ?? null,
    texto: dados.text ?? '',
    imagePathOriginal: imagePath,
    imagePathQuarentena: destinoFoto,
    categorias: v.categorias,
    ...(v.confianca != null && { confianca: v.confianca }),
    criadoEm: dados.createdAt ?? null,
    removidoEm: FieldValue.serverTimestamp(),
  });

  if (!imagePath) return;

  // Mover = baixar, salvar no destino, apagar a origem — e não `copy()`,
  // que usa o endpoint de rewrite que o emulador de Storage não promete.
  // ≤ 2 MiB pelo `storage.rules`; cabe na memória da função com folga.
  //
  // Origem ausente não é erro: ou uma passada anterior já moveu, ou o autor
  // apagou a foto entre o post e a análise. O que havia para preservar é o
  // que o snapshot tinha, e o texto já está no documento acima.
  const origem = bucket().file(imagePath);
  const [existe] = await origem.exists();
  if (!existe) return;

  const [meta] = await origem.getMetadata();
  const [bytes] = await origem.download();
  await bucket().file(destinoFoto).save(bytes, {
    contentType: meta.contentType ?? 'image/jpeg',
  });
  await origem.delete();
}

/**
 * Post vira a MESMA lápide de `PostController.erase` — forma exata, via
 * `set(merge)`: `update()` lança em documento ausente, e "ausente" aqui só
 * acontece num retry depois de meia passada. Comentário é delete real, como
 * o dono do post já faz pelo app; apagar o já apagado é no-op.
 */
async function remover({ tipo, postId, commentId }) {
  if (tipo === 'post') {
    await db().doc(`posts/${postId}`).set(
      { deleted: true, text: '', imagePath: null },
      { merge: true },
    );
    return;
  }
  await db().doc(`posts/${postId}/comments/${commentId}`).delete();
}
