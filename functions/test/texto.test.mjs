import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  SEM_NOME,
  aceite,
  comentarios,
  convite,
  curtidas,
  primeiroNome,
  ranking,
  trechoDoPost,
} from '../texto.js';

describe('primeiroNome — o que cabe num título', () => {
  it('pega só o primeiro nome', () => {
    assert.equal(primeiroNome({ name: 'Cleyton Souza da Silva' }), 'Cleyton');
  });

  it('perfil ausente ou sem nome cai no fallback da casa', () => {
    // O mesmo `Entregador` que `ProfileController._displayName` e a
    // `FriendsScreen` já usam. Dois fallbacks para o mesmo conceito divergem na
    // primeira vez que alguém edita um só.
    assert.equal(primeiroNome(null), SEM_NOME);
    assert.equal(primeiroNome({}), SEM_NOME);
    assert.equal(primeiroNome({ name: '   ' }), SEM_NOME);
    assert.equal(primeiroNome({ name: 42 }), SEM_NOME);
  });
});

describe('convite e aceite — título é sujeito, corpo é predicado', () => {
  it('o convite lê como uma frase só', () => {
    const aviso = convite({ de: 'uid-c', nome: 'Cleyton', para: 'uid-w' });

    assert.equal(`${aviso.titulo} ${aviso.corpo}`,
      'Cleyton enviou um convite de amizade pra você');
    assert.deepEqual(aviso.data, {
      tipo: 'convite',
      de: 'uid-c',
      para: 'uid-w',
    });
  });

  it('o aceite também', () => {
    const aviso = aceite({ de: 'uid-w', nome: 'Wesley', para: 'uid-c' });

    assert.equal(`${aviso.titulo} ${aviso.corpo}`,
      'Wesley aceitou seu convite de amizade');
    assert.equal(aviso.data.tipo, 'aceite');
  });
});

describe('ranking', () => {
  it('usa o rótulo do critério, igual ao da tela', () => {
    // Estes três textos são cópia de `RankCriterion.label` no Dart. Se alguém
    // mudar lá e não aqui, o push passa a chamar a disputa por outro nome —
    // este teste é a única coisa que segura a fronteira.
    assert.equal(
      ranking({ de: 'u', nome: 'Cleyton', para: 'w', criterio: 'rotas', mes: '2026-08' }).corpo,
      'passou você em Rotas');
    assert.equal(
      ranking({ de: 'u', nome: 'Cleyton', para: 'w', criterio: 'ritmo', mes: '2026-08' }).corpo,
      'passou você em Ritmo');
    assert.equal(
      ranking({ de: 'u', nome: 'Cleyton', para: 'w', criterio: 'insucesso', mes: '2026-08' }).corpo,
      'passou você em Insucesso');
  });

  it('critério desconhecido não vira frase torta — devolve null', () => {
    // Melhor não avisar do que anunciar "passou você em undefined".
    assert.equal(
      ranking({ de: 'u', nome: 'C', para: 'w', criterio: 'dinheiro', mes: '2026-08' }),
      null);
  });

  it('leva critério e mês no data, para o toque abrir a disputa certa', () => {
    const aviso = ranking({
      de: 'uid-c', nome: 'Cleyton', para: 'uid-w', criterio: 'ritmo', mes: '2026-08',
    });

    assert.deepEqual(aviso.data, {
      tipo: 'ranking',
      de: 'uid-c',
      para: 'uid-w',
      criterio: 'ritmo',
      mes: '2026-08',
    });
  });
});

describe('marcos — ninguém é nomeado numa curtida', () => {
  it('a primeira curtida não diz quem curtiu', () => {
    // A regra de `likes` NÃO chama `bloqueioEntre`: quem foi bloqueado ainda
    // curte. Nomear entregaria o nome do bloqueado na tela de bloqueio da
    // vítima, furando por push o bloqueio que a regra do comentário sustenta.
    const aviso = curtidas({ marco: 1, para: 'uid-w', postId: 'p1' });

    assert.equal(aviso.titulo, 'Primeira curtida');
    assert.equal(aviso.corpo, 'Seu post recebeu a primeira curtida.');
    assert.equal(aviso.data.de, undefined);
  });

  it('o marco diz "chegou a", e o verbo é load-bearing', () => {
    // "chegou a 10" continua verdadeiro com 11 e continua verdadeiro se caiu
    // para 9. "tem 10 curtidas" é falso nos dois casos — e a corrida garante
    // que o número do envio quase nunca é o número do marco.
    assert.equal(
      curtidas({ marco: 10, para: 'w', postId: 'p1' }).corpo,
      'Seu post chegou a 10 curtidas.');
  });

  it('o primeiro comentário NOMEIA, e a assimetria é deliberada', () => {
    // A regra de `comments` chama `bloqueioEntre` nos dois sentidos, então quem
    // comentou não é bloqueado de ninguém. O que nunca vai é o texto do
    // comentário.
    const aviso = comentarios({
      marco: 1, nome: 'Cleyton', de: 'uid-c', para: 'uid-w', postId: 'p1',
    });

    assert.equal(`${aviso.titulo} ${aviso.corpo}`, 'Cleyton comentou no seu post');
    assert.equal(aviso.data.de, 'uid-c');
  });

  it('o marco de comentários não nomeia ninguém', () => {
    const aviso = comentarios({ marco: 5, para: 'uid-w', postId: 'p1' });

    assert.equal(aviso.titulo, '5 comentários');
    assert.equal(aviso.corpo, 'Seu post chegou a 5 comentários.');
    assert.equal(aviso.data.de, undefined);
  });
});

describe('o trecho do post — texto do dono, nunca de terceiro', () => {
  it('entra entre aspas no fim do corpo', () => {
    const aviso = curtidas({
      marco: 10, para: 'w', postId: 'p1', trecho: 'Rodei 180 km hoje',
    });

    assert.equal(aviso.corpo, 'Seu post chegou a 10 curtidas. “Rodei 180 km hoje”');
  });

  it('corta com reticências e normaliza espaços', () => {
    const longo = 'a'.repeat(80);
    assert.equal(trechoDoPost(longo).length, 51);
    assert.ok(trechoDoPost(longo).endsWith('…'));
    assert.equal(trechoDoPost('  duas   linhas\n  aqui '), 'duas linhas aqui');
  });

  it('post sem texto (só foto) não inventa aspas vazias', () => {
    assert.equal(trechoDoPost(''), null);
    assert.equal(trechoDoPost('   '), null);
    assert.equal(trechoDoPost(null), null);
    assert.equal(
      curtidas({ marco: 10, para: 'w', postId: 'p1', trecho: null }).corpo,
      'Seu post chegou a 10 curtidas.');
  });
});

describe('o data de toda mensagem é só string', () => {
  it('nada de null, undefined ou número', () => {
    // O FCM só aceita string em `data`, e `NotificationTarget.fromData` no Dart
    // descarta qualquer valor que não seja string. Mandar `null` só ocuparia
    // bytes numa mensagem que tem teto.
    const avisos = [
      convite({ de: 'a', nome: 'A', para: 'b' }),
      aceite({ de: 'a', nome: 'A', para: 'b' }),
      ranking({ de: 'a', nome: 'A', para: 'b', criterio: 'rotas', mes: '2026-08' }),
      curtidas({ marco: 20, para: 'b', postId: 'p' }),
      comentarios({ marco: 1, nome: 'A', de: 'a', para: 'b', postId: 'p' }),
      comentarios({ marco: 15, para: 'b', postId: 'p' }),
    ];

    for (const aviso of avisos) {
      for (const [chave, valor] of Object.entries(aviso.data)) {
        assert.equal(typeof valor, 'string', `${chave} não é string`);
        assert.notEqual(valor, '', `${chave} está vazio`);
      }
    }
  });

  it('todo aviso carrega `para`, que é a segunda trava do celular emprestado', () => {
    // O cliente descarta o alvo que não é da sessão atual. A primeira trava é a
    // chave de `fcmTokens`; esta pega a mensagem que já estava a caminho quando
    // a conta trocou.
    assert.equal(convite({ de: 'a', nome: 'A', para: 'b' }).data.para, 'b');
    assert.equal(curtidas({ marco: 1, para: 'b', postId: 'p' }).data.para, 'b');
  });
});
