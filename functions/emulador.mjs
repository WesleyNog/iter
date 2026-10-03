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
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import { apagarDadosDe } from './conta.js';
import { bucket } from './firebase.js';
import { moderar } from './moderacao.js';
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

// ─── Moderação automática ───────────────────────────────────────────────────
//
// O classificador é o de mentira de `gemini.js` (o emulador define
// `FIRESTORE_EMULATOR_HOST`), dirigido por marcadores no texto. O que se
// prova aqui é tudo MENOS o Gemini: a ordem quarentena → lápide → denúncia,
// o ambíguo que nunca remove, o fail-open, e que repetir a passada não
// quebra nem duplica. Ids `mod-*` de propósito: `p1` e `p2` têm asserções
// próprias no run-emulador.sh.

await semear({ olga: 'Olga Furtado', pablo: 'Pablo Reis' });

const enviarFoto = (caminho) =>
  bucket().file(caminho).save(Buffer.from('jpg'), { contentType: 'image/jpeg' });

// M1. Grave com foto: lápide exata, foto movida para a quarentena, denúncia.
await enviarFoto('posts/olga/mod-grave.jpg');
const dadosGrave = {
  uid: 'olga',
  text: 'vou te pegar na saída [[grave:ameaca]]',
  imagePath: 'posts/olga/mod-grave.jpg',
  createdAt: new Date(),
  deleted: false,
};
await db.doc('posts/mod-grave').set(dadosGrave);

// M2. Ambíguo: fica no ar e vira denúncia — racismo nunca remove sozinho.
await publicar('mod-suspeito', 'olga', 'piada duvidosa [[suspeito:racismo]]');

// M3. Limpo: nenhum rastro, nenhum documento.
await publicar('mod-limpo', 'olga', 'dia tranquilo, 80 pacotes sem insucesso');

// M4. Grave ABAIXO do corte: denúncia, nunca remoção.
await publicar('mod-fraco', 'olga', 'ameaça talvez [[fraco:ameaca]]');

// M5. Bloqueado pelo filtro irredutível do Vertex: remove.
await publicar('mod-bloqueado', 'olga', 'o que o Vertex recusa [[bloqueado]]');

// M6. Transporte caiu: a função LANÇA (o retry é da plataforma) e o post fica.
await publicar('mod-erro', 'olga', 'classificador fora do ar [[erro]]');

// M7. Comentário grave sob post limpo: o comentário some, o post fica.
await publicar('mod-palco', 'pablo', 'post inocente da plateia');
await espera(4000);
await comentar('mod-palco', 'cm1', 'olga', 'aliciamento [[grave:sexual-menores]]');

await espera(12000);

// A repetição: o retry re-entrega o MESMO evento, então `moderar` roda de
// novo com os MESMOS dados — o `apagarDadosDe` duas vezes da exclusão.
await moderar({ tipo: 'post', postId: 'mod-grave', dados: dadosGrave });
await espera(2000);

const conferenciasMod = [];
const confereMod = (descricao, ok) => {
  conferenciasMod.push(ok);
  console.log(`MODERACAO ${ok ? 'ok   ' : 'FALHA'} ${descricao}`);
};
const docDe = async (caminho) => (await db.doc(caminho).get()).data();
const temDoc = async (caminho) => (await db.doc(caminho).get()).exists;
const temFoto = async (caminho) => (await bucket().file(caminho).exists())[0];

const graveDepois = await docDe('posts/mod-grave');
confereMod('M1: o post grave virou a lápide exata',
  graveDepois?.deleted === true && graveDepois.text === ''
  && graveDepois.imagePath === null);
confereMod('M1: a foto saiu de posts/', !(await temFoto('posts/olga/mod-grave.jpg')));
confereMod('M1: a foto está na quarentena',
  await temFoto('quarentena/p_mod-grave/mod-grave.jpg'));
const qGrave = await docDe('quarentena/p_mod-grave');
confereMod('M1: a quarentena guarda o texto original',
  qGrave?.texto === dadosGrave.text && qGrave.uid === 'olga');
const dGrave = await docDe('reports/p_mod-grave__maquina');
confereMod('M1: a denúncia automática caiu na fila',
  dGrave?.reason === 'ameaca' && dGrave.removeu === true);

confereMod('M2: o ambíguo CONTINUA no ar',
  (await docDe('posts/mod-suspeito'))?.deleted === false);
confereMod('M2: e virou denúncia sem remoção',
  (await docDe('reports/p_mod-suspeito__maquina'))?.removeu === false);
confereMod('M2: ambíguo não vai para a quarentena',
  !(await temDoc('quarentena/p_mod-suspeito')));

confereMod('M3: post limpo não gera denúncia',
  !(await temDoc('reports/p_mod-limpo__maquina')));
confereMod('M3: nem quarentena', !(await temDoc('quarentena/p_mod-limpo')));

confereMod('M4: grave abaixo do corte NÃO remove',
  (await docDe('posts/mod-fraco'))?.deleted === false);
confereMod('M4: mas denuncia',
  (await docDe('reports/p_mod-fraco__maquina'))?.removeu === false);

confereMod('M5: bloqueio irredutível remove',
  (await docDe('posts/mod-bloqueado'))?.deleted === true);
confereMod('M5: com a razão dita',
  (await docDe('reports/p_mod-bloqueado__maquina'))?.reason === 'bloqueado-pelo-filtro');

confereMod('M6: falha de transporte deixa o post DE PÉ',
  (await docDe('posts/mod-erro'))?.deleted === false);
confereMod('M6: sem denúncia', !(await temDoc('reports/p_mod-erro__maquina')));
confereMod('M6: sem quarentena', !(await temDoc('quarentena/p_mod-erro')));

confereMod('M7: o comentário grave sumiu',
  !(await temDoc('posts/mod-palco/comments/cm1')));
confereMod('M7: o post da plateia ficou',
  (await docDe('posts/mod-palco'))?.deleted === false);
confereMod('M7: a quarentena do comentário guarda o texto',
  (await docDe('quarentena/c_mod-palco_cm1'))?.texto?.includes('aliciamento') === true);
confereMod('M7: a denúncia carrega o commentId',
  (await docDe('reports/c_mod-palco_cm1__maquina'))?.commentId === 'cm1');

const graveRepetido = await docDe('posts/mod-grave');
confereMod('repetição: a lápide continua a lápide',
  graveRepetido?.deleted === true && graveRepetido.text === '');
confereMod('repetição: a foto continua na quarentena, e só lá',
  await temFoto('quarentena/p_mod-grave/mod-grave.jpg')
  && !(await temFoto('posts/olga/mod-grave.jpg')));
confereMod('repetição: a quarentena continua com o original',
  (await docDe('quarentena/p_mod-grave'))?.texto === dadosGrave.text);

const falhasMod = conferenciasMod.filter((ok) => !ok).length;
console.log(`MODERACAO: ${conferenciasMod.length} conferências, ${falhasMod} falhas`);

// ─── Exclusão de conta ──────────────────────────────────────────────────────
//
// O Zeca tem de tudo: rotas, perfil, apelido, dois aparelhos, post com foto,
// amizade com a Lara, convite pendente da Mika, bloqueio no Nino, curtida e
// comentário no post da Lara, relato de preço, denúncia e avisos de ranking.
// Apaga-se o usuário **no Auth** — o gatilho é esse, não uma chamada — e
// confere-se documento por documento o que sumiu e o que tinha de ficar.
//
// As estatísticas vão ANTES das amizades de propósito: gravar balde com amigo
// dispara o ranking, e a contagem de avisos lá em cima é exata.

await semear({
  zeca: 'Zeca Diniz',
  lara: 'Lara Pontes',
  mika: 'Mika Torres',
  nino: 'Nino Sales',
});
await getAuth().createUser({ uid: 'zeca', displayName: 'Zeca Diniz' });

const token = (n) => n.toString(16).padStart(64, '0');
const foto = (caminho) =>
  bucket().file(caminho).save(Buffer.from('jpg'), { contentType: 'image/jpeg' });

await db.doc('user/zeca').set({ id: 'zeca', cpf: '000.000.000-00', nickName: 'zeca.diniz' });
await db.doc('nicknames/zeca.diniz').set({ uid: 'zeca' });
await db.doc('nicknames/lara.pontes').set({ uid: 'lara' });
await gravarBalde('zeca', MES, balde({ rotas: 3 }));
await gravarBalde('zeca', 'all', balde({ rotas: 30 }));

for (const colecao of ['routes', 'vehicles', 'supply', 'maintenance', 'posts']) {
  await db.doc(`iter/zeca/${colecao}/x1`).set({ id: 'x1' });
}

await db.doc('posts/p-zeca').set({
  uid: 'zeca', text: 'meu post', imagePath: 'posts/zeca/p-zeca.jpg',
  createdAt: new Date(), deleted: false,
});
await publicar('p-lara', 'lara', 'post da Lara');
await foto('posts/zeca/p-zeca.jpg');
await foto('posts/lara/p-lara.jpg');

await curtir('p-zeca', 'lara');
await comentar('p-zeca', 'c-lara-1', 'lara', 'comentário da Lara no post do Zeca');
await curtir('p-lara', 'zeca');
await comentar('p-lara', 'c-zeca-1', 'zeca', 'comentário do Zeca');
await curtir('p-lara', 'nino');
await comentar('p-lara', 'c-lara-2', 'lara', 'a Lara no próprio post');

await db.doc('gastop/st1').set({ updatedBy: 'zeca', prices: { gasolina: 6.19 } });
await db.doc('gastop/st1/precos/pr-zeca').set({ uid: 'zeca', price: 6.19, fuel: 'gasolina' });
await db.doc('gastop/st1/precos/pr-lara').set({ uid: 'lara', price: 6.29, fuel: 'gasolina' });
await db.doc('gastop/st2').set({ updatedBy: 'lara', prices: { etanol: 4.5 } });

await db.doc('reports/p_p-lara__zeca').set({ uid: 'zeca', postId: 'p-lara', reason: 'spam' });
await db.doc('blocks/zeca/list/nino').set({ at: new Date() });
await db.doc('blocks/nino/list/zeca').set({ at: new Date() });

for (const id of [
  'zeca_lara_rotas_2026-09_2026-09-16',
  'lara_zeca_ritmo_2026-09_2026-09-16',
  'lara_nino_rotas_2026-09_2026-09-16',
  // `zeca` está contido em `zecao`: um `includes` apagaria este.
  'zecao_lara_rotas_2026-09_2026-09-16',
]) {
  await db.doc(`avisosRanking/${id}`).set({ at: new Date() });
}

await amizade('zeca', 'lara');
await amizade('lara', 'mika');
// Convite pendente da Mika para o Zeca.
await convidar('mika', 'zeca');
// **A armadilha da ordem.** Um `outgoing` da Lara para o Zeca com a amizade de
// pé — o estado do convite mútuo antes do aceite limpar tudo. Se a limpeza
// apagasse o marcador antes da aresta, `aceite` poderia ler a aresta ainda viva
// e mandar "Zeca aceitou seu convite" para a Lara. O `run-emulador.sh` proíbe o
// sintoma, mas **não prova a ordem**: o gatilho lê depois, e com a ordem
// invertida a aresta quase sempre já teria sumido. Quem garante é o código.
await db.doc('friendRequests/lara/outgoing/zeca').set({ at: new Date() });
await espera(6000);

// Os aparelhos entram **por último**, depois de todo aviso do cenário. Não há
// emulador de FCM: o token de mentira vai ao FCM de verdade, volta
// `invalid-argument`, e o `push.js` o apaga como registro morto. Semeados
// antes, os do Zeca sumiriam pelo convite da Mika — e "apagado" passaria sem
// a limpeza apagar nada. O que tem de ficar é do Nino, que não recebe aviso.
await db.doc(`fcmTokens/${token(1)}`).set({ uid: 'zeca', token: 't1', platform: 'android' });
await db.doc(`fcmTokens/${token(2)}`).set({ uid: 'zeca', token: 't2', platform: 'ios' });
await db.doc(`fcmTokens/${token(3)}`).set({ uid: 'nino', token: 't3', platform: 'android' });

await getAuth().deleteUser('zeca');

// Espera o gatilho em vez de um sono fixo: `user/zeca` é o último passo.
let gatilhoRodou = false;
for (let i = 0; i < 60 && !gatilhoRodou; i += 1) {
  await espera(1000);
  gatilhoRodou = !(await db.doc('user/zeca').get()).exists;
}

const conferencias = [];
const confere = (descricao, ok) => {
  conferencias.push(ok);
  console.log(`EXCLUSAO ${ok ? 'ok   ' : 'FALHA'} ${descricao}`);
};
const existe = async (caminho) => (await db.doc(caminho).get()).exists;
const dados = async (caminho) => (await db.doc(caminho).get()).data();
const fotoExiste = async (caminho) => (await bucket().file(caminho).exists())[0];

confere('o gatilho do Auth rodou', gatilhoRodou);

for (const caminho of [
  'user/zeca',
  'profiles/zeca',
  `profiles/zeca/stats/${MES}`,
  'profiles/zeca/stats/all',
  'nicknames/zeca.diniz',
  `fcmTokens/${token(1)}`,
  `fcmTokens/${token(2)}`,
  'iter/zeca/routes/x1',
  'iter/zeca/vehicles/x1',
  'iter/zeca/supply/x1',
  'iter/zeca/maintenance/x1',
  'iter/zeca/posts/x1',
  'friends/zeca/list/lara',
  'friends/lara/list/zeca',
  'friendRequests/zeca/incoming/mika',
  'friendRequests/mika/outgoing/zeca',
  'friendRequests/lara/outgoing/zeca',
  'blocks/zeca/list/nino',
  'posts/p-lara/likes/zeca',
  'posts/p-lara/comments/c-zeca-1',
  'avisosRanking/zeca_lara_rotas_2026-09_2026-09-16',
  'avisosRanking/lara_zeca_ritmo_2026-09_2026-09-16',
]) {
  confere(`apagado: ${caminho}`, !(await existe(caminho)));
}
confere('apagada: foto posts/zeca/p-zeca.jpg', !(await fotoExiste('posts/zeca/p-zeca.jpg')));

const lapide = await dados('posts/p-zeca');
confere('o post do Zeca virou lápide',
  lapide?.deleted === true && lapide.text === '' && lapide.imagePath === null);

const relato = await dados('gastop/st1/precos/pr-zeca');
confere('o relato de preço ficou, sem o uid', relato?.price === 6.19 && !('uid' in relato));
confere('o posto ficou, sem o updatedBy', (await dados('gastop/st1'))?.updatedBy === undefined);

for (const caminho of [
  'profiles/lara',
  'nicknames/lara.pontes',
  `fcmTokens/${token(3)}`,
  'posts/p-lara',
  'posts/p-zeca/likes/lara',
  'posts/p-zeca/comments/c-lara-1',
  'posts/p-lara/likes/nino',
  'posts/p-lara/comments/c-lara-2',
  'reports/p_p-lara__zeca',
  'blocks/nino/list/zeca',
  'friends/lara/list/mika',
  'friends/mika/list/lara',
  'avisosRanking/lara_nino_rotas_2026-09_2026-09-16',
  'avisosRanking/zecao_lara_rotas_2026-09_2026-09-16',
]) {
  confere(`ficou: ${caminho}`, await existe(caminho));
}
confere('ficou: foto posts/lara/p-lara.jpg', await fotoExiste('posts/lara/p-lara.jpg'));
confere('o relato da Lara continua com o uid dela',
  (await dados('gastop/st1/precos/pr-lara'))?.uid === 'lara');
confere('o posto da Lara continua com o updatedBy dela',
  (await dados('gastop/st2'))?.updatedBy === 'lara');

// O `failurePolicy` repete a função inteira: a segunda passada não pode lançar.
let repetiu = true;
try {
  await apagarDadosDe('zeca');
} catch (e) {
  console.log(`EXCLUSAO erro na repetição: ${e.message}`);
  repetiu = false;
}
confere('rodar a limpeza de novo não quebra', repetiu);

const falhas = conferencias.filter((ok) => !ok).length;
console.log(`EXCLUSAO: ${conferencias.length} conferências, ${falhas} falhas`);
await espera(6000);

console.log('EMULADOR: cenários concluídos.');
