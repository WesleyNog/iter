/**
 * "Um amigo te passou no ranking do mês."
 *
 * O mais caro dos cinco eventos, e o único que **deriva** o fato em vez de
 * lê-lo: não existe nenhuma escrita no Firestore que signifique "A ultrapassou
 * B". O que salva o desenho é a ultrapassagem ser **paridade**, não
 * classificação — ver `rank.js`.
 *
 * Ver `docs/specs/notificacoes.md`.
 */

import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

import { REGIAO } from './opcoes.js';
import { db } from './firebase.js';
import { enviar } from './push.js';
import { perfilDe } from './perfis.js';
import { BALDE_VAZIO, CRITERIOS, baldeMudou, lerBalde, passou } from './rank.js';
import { diaDeFortaleza, mesDeFortaleza } from './tempo.js';
import * as texto from './texto.js';

/**
 * A ordem em que os critérios são citados quando um amigo foi passado em mais
 * de um na mesma gravação.
 *
 * **Arbitrária de propósito, e determinística por isso.** Uma escrita pode
 * passar quatro amigos em três critérios e produzir doze avisos; o teto diário
 * não vê isso, porque ele é por par. O segundo limite é aqui: **um aviso por
 * amigo passado**, citando um critério só. Qual deles é escolha de estilo — que
 * seja sempre a mesma, para o comportamento não depender da ordem em que o
 * `Object.entries` devolveu as coisas.
 */
const PRIORIDADE = CRITERIOS;

export const ranking = onDocumentWritten(
  {
    document: 'profiles/{uid}/stats/{bucket}',
    region: REGIAO,
  },
  async (event) => {
    const { uid, bucket } = event.params;

    const depoisSnap = event.data?.after;
    if (depoisSnap === undefined || !depoisSnap.exists) return;

    const antes = lerBalde(event.data?.before?.data());
    const depois = lerBalde(depoisSnap.data());

    // **Portão 1, e é ele que torna o custo aceitável.** A abertura do app
    // reescreve treze baldes (doze meses + carreira). Escrita cujo conteúdo não
    // muda é no-op e nem chega aqui — foi para isso que o `updatedAt` saiu dos
    // baldes —, mas a comparação continua sendo a rede de segurança para o dia
    // em que alguém devolver um carimbo qualquer ao documento.
    if (!baldeMudou(antes, depois)) return;

    // **Portão 2: só o mês corrente.** A aba navega doze meses para trás e
    // todos são disputas de verdade, mas uma ultrapassagem em junho, anunciada
    // em agosto, é um evento sobre o qual ninguém pode agir. É a mesma
    // disciplina da provisão congelada: o passado não gera evento novo. O
    // balde `all` (carreira) também cai aqui, e deve.
    const agora = new Date();
    const mes = mesDeFortaleza(agora);
    if (bucket !== mes) return;

    const amigos = await amigosDe(uid);
    if (amigos.length === 0) return;

    // Um aviso por amigo: `Map<uid do amigo, critério citado>`.
    const passados = new Map();

    for (const amigo of amigos) {
      const baldeAmigo = await baldeDe(amigo, mes);

      for (const criterio of PRIORIDADE) {
        // O balde do amigo entra **igual nos dois lados**: é o que isola o
        // movimento de quem gravou. Comparar o "antes" de quem gravou contra o
        // "antes" do amigo contaria de novo um movimento do amigo que já
        // disparou o gatilho dele — e o mesmo evento notificaria duas vezes.
        if (passou({ criterio, antes, depois, amigo: baldeAmigo })) {
          if (!passados.has(amigo)) passados.set(amigo, criterio);
          break;
        }
      }
    }

    if (passados.size === 0) return;

    const perfil = await perfilDe(uid);
    const nome = texto.primeiroNome(perfil);
    const dia = diaDeFortaleza(agora);

    for (const [amigo, criterio] of passados) {
      await avisar({ passado: amigo, passador: uid, nome, criterio, mes, dia });
    }
  },
);

/**
 * A lista de amigos, e **só ela**.
 *
 * É o que faz o bloqueio funcionar de graça: `FriendController.severTies` apaga
 * as duas arestas no mesmo commit do bloqueio, então um bloqueado nunca está
 * aqui. Derivar amizade de qualquer outro caminho — de um marcador de convite,
 * por exemplo — reabriria contato para quem foi bloqueado.
 */
async function amigosDe(uid) {
  const lista = await db().collection(`friends/${uid}/list`).get();
  return lista.docs.map((doc) => doc.id);
}

async function baldeDe(uid, mes) {
  const doc = await db().doc(`profiles/${uid}/stats/${mes}`).get();
  // Balde ausente é mês parado, não erro: quem não rodou aparece com zero.
  return doc.exists ? lerBalde(doc.data()) : BALDE_VAZIO;
}

/**
 * Manda o aviso, no máximo um por par, critério e dia.
 *
 * **O documento é a trava.** `create()` falha quando o id já existe, então não
 * há leitura, nem transação, nem contador para conciliar — a técnica de
 * `nicknames/{apelido}`. O uid vem antes da data no id porque data no prefixo
 * joga as escritas do dia numa faixa contígua de chaves.
 *
 * A trava é criada **antes** do envio. Se ela passa e o envio falha, o par perde
 * o aviso do dia; na ordem inversa, uma falha ao gravar a trava faria a função
 * repetir e **reenviar** — e push não tem como ser desenviado. Queima o dia, não
 * a tela de bloqueio de alguém.
 *
 * A chave inclui a **direção**: a Ana passar a Bia e a Bia repassar a Ana são
 * dois destinatários diferentes, e colapsar silenciaria um evento verdadeiro
 * para quem ainda não recebeu nada hoje.
 */
async function avisar({ passado, passador, nome, criterio, mes, dia }) {
  const id = `${passado}_${passador}_${criterio}_${mes}_${dia}`;

  try {
    await db().collection('avisosRanking').doc(id).create({
      at: new Date(),
    });
  } catch (e) {
    // **Só `already-exists` é silêncio.** Um `catch` largo transformaria falha
    // de rede em "já avisei hoje" e perderia a notificação sem deixar rastro.
    if (e?.code === 6 || e?.code === 'already-exists') return;
    throw e;
  }

  const aviso = texto.ranking({ de: passador, nome, para: passado, criterio, mes });
  const aparelhos = await enviar({ para: passado, aviso });

  logger.info('ranking', { de: passador, para: passado, criterio, aparelhos });
}
