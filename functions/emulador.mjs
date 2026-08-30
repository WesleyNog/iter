/**
 * Prova que os gatilhos disparam — e, sobretudo, que os que **não** devem
 * disparar ficam quietos. Contra o emulador, sem deploy e sem gastar nada.
 *
 * Fica **fora de `test/`** de propósito: `npm test` é `node --test`, que varre
 * aquele diretório, e este arquivo precisa do emulador de pé. É a mesma razão
 * pela qual `firestore-tests/` mora fora de `test/` no projeto Flutter.
 *
 * Rodar: `npm run emulador` (a partir de `functions/`).
 *
 * O que ele **não** cobre: o envio em si. Não existe emulador de FCM — a
 * mensagem chegar no aparelho é a tarefa A12, em celular de verdade. O que este
 * arquivo prova é a metade que erra em silêncio: que a escrita no caminho certo
 * acorda a função certa, que os parâmetros do caminho chegam corretos, e que o
 * aceite é distinguido da recusa.
 *
 * As asserções são feitas **sobre a saída** pelo `run-emulador.sh`: o log da
 * função sai no stdout do emulador, não neste processo.
 */

import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

import { mesDeFortaleza } from './tempo.js';

const db = getFirestore(initializeApp({ projectId: 'iter-mn' }));

const espera = (ms) => new Promise((r) => setTimeout(r, ms));

const perfil = (uid, nome) => ({
  uid,
  name: nome,
  updatedAt: '2026-08-25T09:00:00.000',
});

async function semear(pessoas) {
  for (const [uid, nome] of Object.entries(pessoas)) {
    await db.doc(`profiles/${uid}`).set(perfil(uid, nome));
  }
}

/** O que `FriendController.invite` faz: dois marcadores num batch. */
async function convidar(de, para) {
  const lote = db.batch();
  lote.set(db.doc(`friendRequests/${para}/incoming/${de}`), { at: new Date() });
  lote.set(db.doc(`friendRequests/${de}/outgoing/${para}`), { at: new Date() });
  await lote.commit();
}

/** O que `FriendController.accept` faz: as duas arestas e os quatro marcadores. */
async function aceitar(eu, outro) {
  const lote = db.batch();
  lote.set(db.doc(`friends/${eu}/list/${outro}`), { at: new Date() });
  lote.set(db.doc(`friends/${outro}/list/${eu}`), { at: new Date() });
  limparMarcadores(lote, eu, outro);
  await lote.commit();
}

/** O que `FriendController.decline` faz: só os quatro marcadores. */
async function recusar(eu, outro) {
  const lote = db.batch();
  limparMarcadores(lote, eu, outro);
  await lote.commit();
}

function limparMarcadores(lote, eu, outro) {
  lote.delete(db.doc(`friendRequests/${eu}/incoming/${outro}`));
  lote.delete(db.doc(`friendRequests/${outro}/outgoing/${eu}`));
  lote.delete(db.doc(`friendRequests/${outro}/incoming/${eu}`));
  lote.delete(db.doc(`friendRequests/${eu}/outgoing/${outro}`));
}

/** As duas arestas de amizade, como `FriendController.accept` as grava. */
async function amizade(a, b) {
  const lote = db.batch();
  lote.set(db.doc(`friends/${a}/list/${b}`), { at: new Date() });
  lote.set(db.doc(`friends/${b}/list/${a}`), { at: new Date() });
  await lote.commit();
}

/** Um balde do mês, com os sete inteiros que `MonthStats.toMap` grava. */
const balde = ({ rotas = 0, pacotes = 0, insucessos = 0, comPacotes = 0,
                 cronometradas = 0, minutos = 0, paradas = 0 } = {}) => ({
  routes: rotas,
  packages: pacotes,
  failures: insucessos,
  packagedRoutes: comPacotes,
  pacedRoutes: cronometradas,
  pacedMinutes: minutos,
  pacedStops: paradas,
});

const gravarBalde = (uid, mes, dados) =>
  db.doc(`profiles/${uid}/stats/${mes}`).set(dados);

await semear({
  ana: 'Ana Paula Ribeiro',
  bia: 'Bia Nogueira',
  carla: 'Carla Menezes',
  dinho: 'Dinho Barbosa',
  elias: 'Elias Prado',
  fabio: 'Fábio Correia',
});

// 1. Convite: a Ana convida a Bia. Deve logar `convite` para a bia.
await convidar('ana', 'bia');
await espera(5000);

// 2. Aceite: a Carla convida o Dinho, o Dinho aceita. Deve logar `aceite`
//    para a **carla**, que é quem convidou — e uma vez só, apesar de o aceite
//    escrever duas arestas.
await convidar('carla', 'dinho');
await espera(5000);
await aceitar('dinho', 'carla');
await espera(6000);

// 3. Recusa: o Elias convida o Fábio, o Fábio recusa. Apaga os mesmos
//    marcadores do aceite — e **não pode** notificar ninguém. É o caso que
//    justifica a leitura da aresta depois do commit.
await convidar('elias', 'fabio');
await espera(5000);
await recusar('fabio', 'elias');
await espera(6000);

// ─── Ranking ────────────────────────────────────────────────────────────────

await semear({ gil: 'Gil Moreira', helo: 'Helô Ramos' });
await amizade('gil', 'helo');

const MES = mesDeFortaleza(new Date());

// R1. Estado inicial: o Gil atrás da Helô. Nenhum aviso — é a primeira
//     gravação de cada um, e ninguém ultrapassou ninguém.
await gravarBalde('gil', MES, balde({ rotas: 5 }));
await gravarBalde('helo', MES, balde({ rotas: 10 }));
await espera(6000);

// R2. O Gil passa a Helô: deve avisar a **Helô**, em Rotas.
await gravarBalde('gil', MES, balde({ rotas: 12 }));
await espera(7000);

// R3. **A pergunta em aberto da spec**: escrita byte-idêntica dispara gatilho?
//     Se disparar, o portão `baldeMudou` tem de segurar. De um jeito ou de
//     outro, não pode sair aviso novo.
await gravarBalde('gil', MES, balde({ rotas: 12 }));
await espera(6000);

// R4. O Gil continua subindo, mas já estava na frente: não é ultrapassagem.
await gravarBalde('gil', MES, balde({ rotas: 15 }));
await espera(6000);

// R5. Mês passado, com números que ultrapassariam: o portão 2 recusa.
await gravarBalde('gil', '2026-01', balde({ rotas: 900 }));
await espera(6000);

// R6. A Helô reassume e o Gil passa de novo **no mesmo dia**: o teto diário
//     por par+critério tem de emudecer o segundo aviso.
await gravarBalde('helo', MES, balde({ rotas: 20 }));
await espera(6000);
await gravarBalde('gil', MES, balde({ rotas: 25 }));
await espera(7000);

// ─── Marcos de curtida e comentário ─────────────────────────────────────────

await semear({ ines: 'Inês Cavalcante', joao: 'João Vitor' });

const publicar = (id, uid, texto) =>
  db.doc(`posts/${id}`).set({
    uid,
    text: texto,
    createdAt: new Date(),
    deleted: false,
  });

const curtir = (postId, uid) =>
  db.doc(`posts/${postId}/likes/${uid}`).set({ uid, at: new Date() });

const comentar = (postId, id, uid, texto) =>
  db.doc(`posts/${postId}/comments/${id}`).set({
    uid,
    text: texto,
    createdAt: new Date(),
  });

await publicar('p1', 'ines', 'Rodei 180 km hoje e sobrou perna');
await espera(3000);

// C1. A Inês curte o PRÓPRIO post. Não pode notificar — e, sobretudo, **não
//     pode deixar marcador**: se deixasse, a primeira curtida de verdade nunca
//     seria anunciada, porque o marco 1 já estaria consumido.
await curtir('p1', 'ines');
await espera(6000);

// C2. O João curte. A contagem é 2, o marco derivado é 1, e a Inês recebe
//     "Primeira curtida" — que só acontece porque C1 não marcou.
await curtir('p1', 'joao');
await espera(6000);

// C3. Mais dez curtidas, de propósito **em rajada**: as invocações correm entre
//     si e leem contagens diferentes. A derivação faz todas convergirem para o
//     marco 10, e o marcador deixa passar uma só.
for (let i = 1; i <= 10; i += 1) {
  await curtir('p1', `curtidor${i}`);
}
await espera(12000);

// C4. Primeiro comentário: notifica a Inês **nomeando** o João. Pode nomear
//     porque a regra de comentário barra bloqueado; a de curtida não.
await comentar('p1', 'c1', 'joao', 'Boa, parceiro!');
await espera(6000);

// C5. Até cinco comentários.
for (let i = 2; i <= 5; i += 1) {
  await comentar('p1', `c${i}`, `comentarista${i}`, 'mais um');
}
await espera(10000);

// C6. Post com lápide: a curtida chega (o Admin SDK ignora a regra que a
//     barraria) e a função tem de desistir na releitura do post. É o caso do
//     dono que apaga justamente quando o post atrai atenção que ele não quis.
await publicar('p2', 'ines', 'post que vai ser apagado');
await espera(2000);
await db.doc('posts/p2').update({ deleted: true, text: '', imagePath: null });
await espera(2000);
await curtir('p2', 'joao');
await espera(6000);

console.log('EMULADOR: cenários concluídos.');
