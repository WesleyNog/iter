/**
 * O envio: quem são os aparelhos de alguém, e como a mensagem chega neles.
 *
 * Ver `docs/specs/notificacoes.md`.
 */

import { getMessaging } from 'firebase-admin/messaging';

import { app, db } from './firebase.js';

const COLECAO = 'fcmTokens';

/**
 * O teto de um `sendEachForMulticast`, lido do próprio SDK
 * (`FCM_MAX_BATCH_SIZE`). Uma pessoa com mais de 500 aparelhos registrados não
 * existe; o número está aqui para que o dia em que existir seja um erro alto e
 * não um silêncio.
 */
const MAX_POR_ENVIO = 500;

/**
 * Os códigos que significam **"este registro morreu, apague"** — e só eles.
 *
 * Os três, e não um: `installation-id-not-registered` é o equivalente do
 * primeiro para FIDs, que este app ainda não usa. Escrevê-lo hoje custa uma
 * linha e faz a migração futura ser um no-op neste caminho — ver a decisão
 * "token, não FID" na spec.
 *
 * **O que NÃO entra aqui é o que mais importa.**
 * `messaging/third-party-auth-error` é a credencial APNs errada ou ausente no
 * console — o token está vivo. Tratá-lo como token morto faz a limpeza apagar
 * **todos** os aparelhos iOS a cada envio, o app regravá-los na abertura
 * seguinte, e o `fcmTokens` piscar para sempre — com o diagnóstico apontando
 * para o cliente quando o problema está no console.
 */
const CODIGOS_DE_DESCARTE = new Set([
  'messaging/registration-token-not-registered',
  'messaging/installation-id-not-registered',
  'messaging/invalid-argument',
]);

/** Função pura, para o teste alcançar a decisão sem subir Firebase. */
export function deveDescartar(codigo) {
  return CODIGOS_DE_DESCARTE.has(codigo);
}

/**
 * Monta a mensagem.
 *
 * **`notification` e `data` sempre juntos.** O `notification` é o que o sistema
 * operacional desenha com o app fechado; o `data` é o que diz para onde ir no
 * toque. Só-`data` não acorda app morto no iOS e é adiada pelo Doze no Android.
 *
 * `priority: 'high'` porque o padrão do FCM é `normal`, e mensagem normal no
 * Android espera a próxima janela de manutenção do Doze — o convite das 21h
 * chegaria quando o motorista pegasse o telefone. Passa em teste de mesa, com a
 * tela ligada, e falha no bolso, que é onde o celular está.
 *
 * No `android.notification` a prioridade é minúscula (`'high'`), e não o
 * `PRIORITY_HIGH` que a documentação do REST usa: são duas grafias da mesma
 * coisa, e o SDK só aceita a dele.
 */
export function montarMensagem({ aviso, tokens, collapse }) {
  return {
    tokens,
    notification: { title: aviso.titulo, body: aviso.corpo },
    data: aviso.data,
    android: {
      priority: 'high',
      ...(collapse ? { collapseKey: collapse } : {}),
      notification: {
        priority: 'high',
        // O canal criado em `MainActivity.kt`. O meta-data do manifesto já o
        // aponta como padrão; repetir aqui é o que garante o canal certo mesmo
        // se o padrão mudar.
        channelId: 'iter_social',
      },
    },
    apns: {
      // 10 é entrega imediata, o equivalente iOS do `high` do Android. Só é
      // válido porque toda mensagem daqui carrega alerta; com `content-available`
      // sozinho a Apple exige 5.
      headers: {
        'apns-priority': '10',
        ...(collapse ? { 'apns-collapse-id': collapse } : {}),
      },
      payload: { aps: { sound: 'default' } },
    },
  };
}

/** Os aparelhos de alguém. */
export async function tokensDe(uid) {
  const consulta = await db()
    .collection(COLECAO)
    .where('uid', '==', uid)
    .limit(MAX_POR_ENVIO)
    .get();

  return consulta.docs
    .map((doc) => ({ id: doc.id, token: doc.get('token') }))
    .filter((linha) => typeof linha.token === 'string' && linha.token !== '');
}

/**
 * Manda um aviso para todos os aparelhos de [para].
 *
 * Devolve quantos aparelhos receberam. Zero é resposta legítima e comum: quem
 * nunca abriu o app depois desta feature não tem token, e quem recusou a
 * permissão tem token e não desenha nada.
 *
 * Nunca lança por falha de entrega — um push que não saiu não pode derrubar o
 * gatilho e fazer o Firestore repetir a escrita que o disparou.
 */
export async function enviar({ para, aviso, collapse }) {
  if (aviso == null) return 0;

  const aparelhos = await tokensDe(para);
  if (aparelhos.length === 0) return 0;

  const mensagem = montarMensagem({
    aviso,
    tokens: aparelhos.map((a) => a.token),
    collapse,
  });

  const resposta = await getMessaging(app()).sendEachForMulticast(mensagem);

  await limpar(resposta, aparelhos);
  return resposta.successCount;
}

/**
 * Apaga os registros que o FCM disse estarem mortos.
 *
 * A ordem das respostas corresponde à dos tokens enviados — é o que permite
 * ligar cada falha ao documento certo.
 */
async function limpar(resposta, aparelhos) {
  if (resposta.failureCount === 0) return;

  const mortos = [];
  for (let i = 0; i < resposta.responses.length; i += 1) {
    const item = resposta.responses[i];
    if (item.success) continue;

    const codigo = item.error?.code;
    if (deveDescartar(codigo)) {
      mortos.push(aparelhos[i].id);
    } else {
      // Falha que **não** é registro morto fica no log e o documento fica de
      // pé. É aqui que a credencial APNs errada aparece, e apagar seria
      // esconder a causa e criar um segundo problema.
      console.warn(`push: falha ao enviar para ${aparelhos[i].id}: ${codigo}`);
    }
  }

  if (mortos.length === 0) return;

  const lote = db().batch();
  for (const id of mortos) {
    lote.delete(db().collection(COLECAO).doc(id));
  }
  await lote.commit();
}
