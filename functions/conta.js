/**
 * A conta sumiu do Firebase Auth: apaga o que era dela.
 *
 * **O gatilho é o Auth, não um botão.** O app chama `user.delete()`; o pedido
 * que chega pela página web é atendido apagando o usuário no console. Os dois
 * caem aqui, e é por isso que a limpeza não é uma função *callable* — ela só
 * cobriria o primeiro.
 *
 * **1ª geração, e não por descuido.** A 2ª não tem gatilho de exclusão de
 * usuário, só os bloqueantes de criação e login. As outras funções do projeto
 * continuam na 2ª.
 *
 * Ver `docs/specs/exclusao-de-conta.md`.
 */

import * as functions from 'firebase-functions/v1';
import { logger } from 'firebase-functions';
import { FieldValue } from 'firebase-admin/firestore';

import { REGIAO } from './opcoes.js';
import { bucket, db } from './firebase.js';
import {
  arestas,
  avisoEnvolve,
  ehLapide,
  LAPIDE,
  marcadores,
} from './exclusao.js';

/**
 * `failurePolicy: true` é o que substitui o app não saber se terminou: uma falha
 * — rede, cota, um índice que ainda não ficou pronto — repete por até sete
 * dias, e **cada passo de `apagarDadosDe` é seguro de repetir**.
 *
 * 540 s é o teto da 1ª geração para função de evento. Quem registra rota todo
 * dia há dois anos tem milhares de documentos, e o padrão de 60 s morreria no
 * meio — repetindo, e morrendo no mesmo ponto, por uma semana.
 */
export const excluirConta = functions
  .runWith({ failurePolicy: true, timeoutSeconds: 540 })
  .region(REGIAO)
  .auth.user()
  .onDelete(async (usuario) => {
    await apagarDadosDe(usuario.uid);
    logger.info('conta excluída', { uid: usuario.uid });
  });

/**
 * Tudo o que o uid deixou no projeto. Exportada para o emulador provar que
 * rodar duas vezes não quebra.
 *
 * A ordem só importa num ponto — arestas antes de marcadores, dentro de
 * `desfazerVinculos` — e o resto é sequencial por legibilidade, não por
 * dependência. `user/{uid}` vai por último só para ser o último rastro, o que
 * facilita conferir no console se uma execução parou no meio.
 */
export async function apagarDadosDe(uid) {
  await desfazerVinculos(uid);
  await apagarRaiz(`blocks/${uid}`);

  await apagarConsulta(db().collectionGroup('likes').where('uid', '==', uid));
  await apagarConsulta(db().collectionGroup('comments').where('uid', '==', uid));
  await enterrarPosts(uid);
  await bucket().deleteFiles({ prefix: `posts/${uid}/` });

  await anonimizarPrecos(uid);
  await apagarAvisos(uid);

  await apagarConsulta(db().collection('fcmTokens').where('uid', '==', uid));
  await apagarConsulta(db().collection('nicknames').where('uid', '==', uid));

  await apagarRaiz(`profiles/${uid}`);
  await apagarRaiz(`iter/${uid}`);
  await apagarRaiz(`user/${uid}`);
}

/**
 * Amizades e convites, dos dois lados.
 *
 * "Os dois lados" é o motivo de não bastar `recursiveDelete('friends/{uid}')`:
 * a entrada da pessoa na lista **do amigo** mora no subtree do amigo.
 *
 * **Todas as arestas primeiro, e só depois qualquer marcador** — ver
 * `arestas()` em `exclusao.js`. As arestas incluem quem só aparece em convite,
 * sem amizade: é o que cobre uma aresta que tenha ficado de pé do lado de lá.
 */
async function desfazerVinculos(uid) {
  const [amigos, recebidos, enviados] = await Promise.all([
    idsEm(`friends/${uid}/list`),
    idsEm(`friendRequests/${uid}/incoming`),
    idsEm(`friendRequests/${uid}/outgoing`),
  ]);

  const pessoas = [...new Set([...amigos, ...recebidos, ...enviados])];
  if (pessoas.length === 0) return;

  await escreverTodos(
    pessoas.flatMap((outro) => arestas(uid, outro)),
    (escritor, caminho) => escritor.delete(db().doc(caminho)),
  );

  await escreverTodos(
    pessoas.flatMap((outro) => marcadores(uid, outro)),
    (escritor, caminho) => escritor.delete(db().doc(caminho)),
  );
}

/**
 * Os posts viram lápide, na forma exata de `PostController.erase`.
 *
 * Não `delete`: os comentários **de outras pessoas** embaixo do post são dado
 * delas. O espelho `iter/{uid}/posts` vai inteiro com `apagarRaiz('iter/…')`.
 */
async function enterrarPosts(uid) {
  const posts = await db().collection('posts').where('uid', '==', uid).get();
  const vivos = posts.docs.filter((doc) => !ehLapide(doc.data()));

  await escreverTodos(vivos, (escritor, doc) =>
    escritor.update(doc.ref, { ...LAPIDE }));
}

/**
 * Os relatos de preço ficam — a mediana é de todo mundo —, mas sem o uid.
 *
 * `gastop/*\/precos` é listável por qualquer autenticado e o feed entrega o uid
 * de todo autor: relato com uid é a trilha de onde e quando a pessoa
 * abasteceu. **Tirar o campo é também o que torna o passo repetível**: a
 * próxima execução não acha mais nada para anonimizar.
 */
async function anonimizarPrecos(uid) {
  const [relatos, postos] = await Promise.all([
    db().collectionGroup('precos').where('uid', '==', uid).select().get(),
    db().collection('gastop').where('updatedBy', '==', uid).select().get(),
  ]);

  await escreverTodos(relatos.docs, (escritor, doc) =>
    escritor.update(doc.ref, { uid: FieldValue.delete() }));
  await escreverTodos(postos.docs, (escritor, doc) =>
    escritor.update(doc.ref, { updatedBy: FieldValue.delete() }));
}

/**
 * As travas de "fulano te passou no ranking".
 *
 * O uid mora só no **id** (`{passado}_{passador}_…`), e o passador fica no
 * meio, onde nenhuma consulta alcança. Então é varredura — `select()` sem campo,
 * só os ids. Cresce com a coleção, que não tem TTL; quando pesar, a saída é um
 * campo de expiração em `ranking.js` e uma política de TTL, não uma consulta
 * mais esperta.
 */
async function apagarAvisos(uid) {
  const avisos = await db().collection('avisosRanking').select().get();
  const deles = avisos.docs.filter((doc) => avisoEnvolve(doc.id, uid));

  await escreverTodos(deles, (escritor, doc) => escritor.delete(doc.ref));
}

/** Um documento e todas as subcoleções embaixo dele, exista ele ou não. */
async function apagarRaiz(caminho) {
  await db().recursiveDelete(db().doc(caminho));
}

async function apagarConsulta(consulta) {
  const resultado = await consulta.select().get();
  await escreverTodos(resultado.docs, (escritor, doc) => escritor.delete(doc.ref));
}

async function idsEm(colecao) {
  const resultado = await db().collection(colecao).select().get();
  return resultado.docs.map((doc) => doc.id);
}

/**
 * Aplica [operacao] a cada item num `BulkWriter` e **lança se qualquer uma
 * falhou** — é o que faz o `failurePolicy` repetir.
 *
 * O `.then(…, erro => erro)` imediato não é enfeite: a promessa de cada escrita
 * pode rejeitar enquanto o `close()` ainda espera as outras, e rejeição sem
 * handler naquele instante derruba o processo inteiro no Node 22, em vez de
 * virar o erro que a gente quer relançar.
 */
async function escreverTodos(itens, operacao) {
  if (itens.length === 0) return;

  const escritor = db().bulkWriter();
  const resultados = itens.map((item) =>
    operacao(escritor, item).then(() => null, (erro) => erro));

  await escritor.close();

  const falhas = (await Promise.all(resultados)).filter(Boolean);
  if (falhas.length > 0) {
    throw new Error(
      `exclusão: ${falhas.length} de ${itens.length} escritas falharam; `
      + `primeira: ${falhas[0].message}`,
    );
  }
}
