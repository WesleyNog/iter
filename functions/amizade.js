/**
 * Os gatilhos de amizade: convite enviado e convite aceito.
 *
 * Ver `docs/specs/notificacoes.md`.
 */

import {
  onDocumentCreated,
  onDocumentDeleted,
} from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

import { REGIAO } from './opcoes.js';
import { db } from './firebase.js';
import { enviar } from './push.js';
import { perfilDe } from './perfis.js';
import * as texto from './texto.js';

/**
 * Alguém te convidou.
 *
 * O mais simples dos cinco eventos, e não por acaso: **o caminho já carrega os
 * dois lados** — `friendRequests/{quem recebeu}/incoming/{quem convidou}` —, que
 * é a técnica que `friendController.dart` documenta como "corpo é dado, caminho
 * é fato".
 *
 * E a regra de `incoming` já garantiu, antes de o documento existir, tudo o que
 * importaria conferir aqui: que quem convida é quem diz ser
 * (`request.auth.uid == otherId`), que os dois perfis existem, e que **não há
 * bloqueio entre eles**. Esta função não reconfere nada disso — é exatamente o
 * que a spec quer dizer com "o gatilho herda a validação de graça", e é o
 * argumento contra uma função *callable* de envio, que teria de reimplementar
 * os três em código.
 *
 * Dispara uma vez só: o convite escreve `incoming` e `outgoing` no mesmo batch,
 * e o gatilho está pendurado apenas no primeiro.
 *
 * Sem `retry`. O padrão da 2ª geração é não repetir, e é o que queremos: uma
 * notificação repetida não tem como ser desenviada.
 */
export const convite = onDocumentCreated(
  {
    document: 'friendRequests/{userId}/incoming/{otherId}',
    region: REGIAO,
  },
  async (event) => {
    const { userId, otherId } = event.params;

    // **Evento de criação sem documento existe, e não é hipótese.**
    //
    // `FriendController.accept` e `decline` apagam os **quatro** caminhos de
    // marcador sem saber quais existem — apagar inexistente é no-op, e o
    // `CLAUDE.md` registra isso como deliberado. Contra o emulador, esse no-op
    // entrega um `created` para o caminho que nunca existiu: no cenário do
    // aceite, quem convidou recebia "aceitou seu convite" **e** "enviou um
    // convite de amizade pra você", o segundo falso.
    //
    // Se produção se comporta como o emulador, esta porta é o conserto. Se não
    // se comporta, ela nunca fecha e não custa nada. Não depender de qual dos
    // dois está certo é mais barato do que descobrir — e o modo de falha do
    // outro lado é uma notificação mentirosa para todo mundo, a cada aceite.
    if (event.data === undefined || !event.data.exists) {
      logger.debug('convite: evento sem documento, ignorado', {
        de: otherId,
        para: userId,
      });
      return;
    }

    // A regra já impede, mas custa nada e o dia em que a regra afrouxar isto
    // aqui é a segunda porta — mesma razão de `friendId != userId` continuar
    // escrito em `firestore.rules` mesmo sendo redundante.
    if (userId === otherId) return;

    const perfil = await perfilDe(otherId);

    const aviso = texto.convite({
      de: otherId,
      nome: texto.primeiroNome(perfil),
      para: userId,
    });

    const aparelhos = await enviar({ para: userId, aviso });

    // Este log é o que prova o gatilho no emulador, e é o que responde
    // "por que fulano não recebeu?" em produção sem precisar de outro rastro.
    // Zero aparelhos é resposta legítima: quem nunca abriu o app depois desta
    // feature não tem token registrado.
    logger.info('convite', { de: otherId, para: userId, aparelhos });
  },
);

/**
 * Alguém aceitou o convite que você mandou.
 *
 * **O gatilho não é a amizade — é o marcador que morre.** O caminho óbvio não
 * funciona, e vale escrever por quê: `FriendController.accept` grava as **duas**
 * arestas no mesmo batch, com corpo idêntico (só `at`, e o `serverTimestamp`
 * resolve para o mesmo valor nas duas). Um gatilho em `friends/{u}/list/{f}`
 * dispararia **duas vezes** e nenhuma das duas diria quem aceitou; os quatro
 * marcadores de convite, que diriam, são apagados no mesmo commit.
 *
 * O apagar do `outgoing` resolve os dois problemas de uma vez. O caminho nomeia
 * os dois lados — `userId` convidou, `otherId` aceitou — e num aceite normal
 * existe exatamente **um** `outgoing`, então dispara uma vez só.
 *
 * A leitura da aresta é o que separa o aceite de tudo o mais que também apaga
 * marcador: no aceite ela está lá (o batch é atômico, e o gatilho vê o estado
 * depois do commit); na recusa e na retirada nunca existiu; no bloqueio e no
 * desfazer, `severTies` apagou aresta e marcador no mesmo commit. Uma leitura
 * por evento.
 *
 * **Aresta conhecida:** no convite mútuo — os dois se convidaram antes de
 * qualquer aceite — existem dois `outgoing`, os dois são apagados, e os **dois**
 * recebem "fulano aceitou seu convite". As duas frases são verdadeiras; quem
 * aceitou recebe um aviso sobre algo que acabou de fazer. Aceito.
 */
export const aceite = onDocumentDeleted(
  {
    document: 'friendRequests/{userId}/outgoing/{otherId}',
    region: REGIAO,
  },
  async (event) => {
    const { userId, otherId } = event.params;
    if (userId === otherId) return;

    // A pergunta inteira do evento cabe nesta linha: a aresta existe depois do
    // commit? Se sim, foi aceite. Se não, foi recusa, retirada, bloqueio ou
    // desfazer — e nenhum deles notifica ninguém.
    const aresta = await db().doc(`friends/${userId}/list/${otherId}`).get();
    if (!aresta.exists) {
      logger.debug('marcador apagado sem aresta: não é aceite', {
        de: userId,
        para: otherId,
      });
      return;
    }

    const perfil = await perfilDe(otherId);

    const aviso = texto.aceite({
      de: otherId,
      nome: texto.primeiroNome(perfil),
      para: userId,
    });

    const aparelhos = await enviar({ para: userId, aviso });

    logger.info('aceite', { de: otherId, para: userId, aparelhos });
  },
);
