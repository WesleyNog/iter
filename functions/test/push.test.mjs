import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { deveDescartar, montarMensagem } from '../push.js';

describe('deveDescartar — o que é registro morto e o que não é', () => {
  it('token de registro não registrado é morto', () => {
    assert.equal(deveDescartar('messaging/registration-token-not-registered'), true);
  });

  it('FID não registrado também, ainda que o app não use FID hoje', () => {
    // Escrito agora porque custa uma linha e faz a migração token→FID ser um
    // no-op neste caminho. Ver a decisão "token, não FID" na spec: o bloqueio é
    // do lado cliente — `firebase_messaging` 16.6.0 não tem uma linha de FID.
    assert.equal(deveDescartar('messaging/installation-id-not-registered'), true);
  });

  it('argumento inválido também autoriza apagar', () => {
    assert.equal(deveDescartar('messaging/invalid-argument'), true);
  });

  it('erro de credencial APNs NÃO é token morto — e este é o teste que importa', () => {
    // `third-party-auth-error` é a chave `.p8` errada ou ausente no console; o
    // token está vivo. Confundir os dois faz a limpeza apagar TODOS os
    // aparelhos iOS a cada envio, o app regravá-los na abertura seguinte, e o
    // `fcmTokens` piscar para sempre — com o diagnóstico apontando para o
    // cliente quando o problema está no console.
    assert.equal(deveDescartar('messaging/third-party-auth-error'), false);
  });

  it('erro desconhecido, indisponibilidade e ausência de código não apagam nada', () => {
    // Na dúvida, o registro fica. Apagar é irreversível do lado do servidor: o
    // aparelho só volta na próxima abertura do app.
    assert.equal(deveDescartar('messaging/server-unavailable'), false);
    assert.equal(deveDescartar('messaging/internal-error'), false);
    assert.equal(deveDescartar(undefined), false);
    assert.equal(deveDescartar('qualquer-coisa'), false);
  });
});

describe('montarMensagem', () => {
  const aviso = {
    titulo: 'Cleyton',
    corpo: 'enviou um convite de amizade pra você',
    data: { tipo: 'convite', de: 'uid-c', para: 'uid-w' },
  };

  it('leva notification E data, sempre as duas', () => {
    // Só-`data` não acorda app morto no iOS e é adiada pelo Doze no Android —
    // entrega a feature no emulador e falha no aparelho do dono.
    const m = montarMensagem({ aviso, tokens: ['t1'] });

    assert.deepEqual(m.notification, {
      title: 'Cleyton',
      body: 'enviou um convite de amizade pra você',
    });
    assert.deepEqual(m.data, aviso.data);
  });

  it('prioridade alta nas duas plataformas', () => {
    // O padrão do FCM é `normal`, e mensagem normal no Android espera a janela
    // do Doze. Passa em teste de mesa, com a tela ligada, e falha no bolso.
    const m = montarMensagem({ aviso, tokens: ['t1'] });

    assert.equal(m.android.priority, 'high');
    assert.equal(m.apns.headers['apns-priority'], '10');
  });

  it('a prioridade do android.notification é minúscula, não PRIORITY_HIGH', () => {
    // Duas grafias da mesma coisa: a doc do REST usa `PRIORITY_HIGH`, o Admin
    // SDK aceita só `'high'`. Copiar a receita do REST para cá é um valor que o
    // servidor ignora em silêncio.
    const m = montarMensagem({ aviso, tokens: ['t1'] });

    assert.equal(m.android.notification.priority, 'high');
  });

  it('aponta o canal criado no MainActivity', () => {
    // Sem canal de importância alta o Android só toca som: não abre banner e
    // não acende a tela — o critério de aceite falhando com o resto certo.
    const m = montarMensagem({ aviso, tokens: ['t1'] });

    assert.equal(m.android.notification.channelId, 'iter_social');
  });

  it('sem collapse não inventa chave nenhuma', () => {
    // Chave de colapso por usuário faria o segundo aviso apagar o primeiro.
    const m = montarMensagem({ aviso, tokens: ['t1'] });

    assert.equal('collapseKey' in m.android, false);
    assert.equal('apns-collapse-id' in m.apns.headers, false);
  });

  it('com collapse, a mesma chave nas duas plataformas', () => {
    const m = montarMensagem({ aviso, tokens: ['t1'], collapse: 'post-1-curtidas' });

    assert.equal(m.android.collapseKey, 'post-1-curtidas');
    assert.equal(m.apns.headers['apns-collapse-id'], 'post-1-curtidas');
  });
});
