import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  arestas,
  avisoEnvolve,
  ehLapide,
  LAPIDE,
  marcadores,
} from '../exclusao.js';

describe('os caminhos de amizade de quem sai', () => {
  it('as duas arestas: a minha lista e a minha entrada na lista do outro', () => {
    assert.deepEqual(arestas('zeca', 'lara'), [
      'friends/zeca/list/lara',
      'friends/lara/list/zeca',
    ]);
  });

  it('os quatro marcadores, nas duas direções', () => {
    assert.deepEqual(new Set(marcadores('zeca', 'lara')), new Set([
      'friendRequests/zeca/incoming/lara',
      'friendRequests/zeca/outgoing/lara',
      'friendRequests/lara/incoming/zeca',
      'friendRequests/lara/outgoing/zeca',
    ]));
  });

  it('todo `outgoing` que o gatilho de aceite escuta tem a aresta que ele lê', () => {
    // `aceite` dispara em `friendRequests/{a}/outgoing/{b}` e lê
    // `friends/{a}/list/{b}`. Se um marcador apagado não tivesse a aresta
    // correspondente na lista apagada antes, o ex-amigo receberia um aceite
    // falso. Esta é a propriedade, e não a lista literal.
    const apagadasAntes = new Set(arestas('zeca', 'lara'));

    for (const caminho of marcadores('zeca', 'lara')) {
      const m = caminho.match(/^friendRequests\/([^/]+)\/outgoing\/([^/]+)$/);
      if (!m) continue;
      assert.ok(
        apagadasAntes.has(`friends/${m[1]}/list/${m[2]}`),
        `${caminho} seria apagado com a aresta de pé`,
      );
    }
  });
});

describe('o aviso de ranking envolve a pessoa', () => {
  it('como quem foi passado', () => {
    assert.equal(avisoEnvolve('zeca_lara_rotas_2026-09_2026-09-16', 'zeca'), true);
  });

  it('como quem passou', () => {
    assert.equal(avisoEnvolve('lara_zeca_ritmo_2026-09_2026-09-16', 'zeca'), true);
  });

  it('um uid contido em outro NÃO conta', () => {
    // `includes` apagaria o aviso da Mariana quando a Ana sai.
    assert.equal(avisoEnvolve('mariana_lara_rotas_2026-09_2026-09-16', 'ana'), false);
    assert.equal(avisoEnvolve('lara_mariana_rotas_2026-09_2026-09-16', 'ana'), false);
  });

  it('o critério e a data não são confundidos com uid', () => {
    assert.equal(avisoEnvolve('lara_nino_rotas_2026-09_2026-09-16', 'rotas'), false);
  });
});

describe('a lápide', () => {
  it('é reconhecida com e sem a chave da foto', () => {
    assert.equal(ehLapide({ uid: 'zeca', ...LAPIDE }), true);
    assert.equal(ehLapide({ uid: 'zeca', deleted: true, text: '' }), true);
  });

  it('post vivo, ou apagado pela metade, não é lápide', () => {
    assert.equal(ehLapide({ deleted: false, text: 'oi' }), false);
    assert.equal(ehLapide({ deleted: true, text: 'sobrou' }), false);
    assert.equal(ehLapide({ deleted: true, text: '', imagePath: 'posts/zeca/p.jpg' }), false);
    // Post do acervo antigo, de antes de `deleted` ser obrigatório.
    assert.equal(ehLapide({ text: '' }), false);
  });
});
