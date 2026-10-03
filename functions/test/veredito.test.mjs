// A tabela de decisão da moderação automática, linha por linha — e, mais
// importante, os dois lados de cada corte. Ver docs/specs/moderacao-automatica.md.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  AMBIGUAS,
  CORTE_GRAVE,
  CORTE_SUSPEITA,
  GRAVES,
  veredito,
} from '../veredito.js';

const resultado = (...categorias) => ({ categorias });

describe('o degrau grave', () => {
  it('grave com confiança no corte REMOVE — `>=`, não `>`', () => {
    const v = veredito(resultado({ categoria: 'ameaca', confianca: CORTE_GRAVE }));
    assert.equal(v.acao, 'remover');
    assert.deepEqual(v.categorias, ['ameaca']);
  });

  it('grave um fio abaixo do corte NÃO remove — vira denúncia', () => {
    // A linha inteira do desenho: a lápide destrói, então confiança
    // insuficiente degrada para o humano, nunca para a remoção.
    const v = veredito(resultado({ categoria: 'ameaca', confianca: CORTE_GRAVE - 0.01 }));
    assert.equal(v.acao, 'denunciar');
  });

  it('toda categoria grave remove no corte', () => {
    for (const categoria of GRAVES) {
      const v = veredito(resultado({ categoria, confianca: 0.95 }));
      assert.equal(v.acao, 'remover', categoria);
    }
  });
});

describe('o degrau ambíguo nunca remove', () => {
  it('ambígua com confiança MÁXIMA ainda é denúncia', () => {
    // Racismo a 1.0 não remove: a precisão do classificador em pt-BR é a
    // razão documentada, e promover a categoria é decisão do dono com os
    // dados da fila — não deste arquivo por conta própria.
    for (const categoria of AMBIGUAS) {
      const v = veredito(resultado({ categoria, confianca: 1 }));
      assert.equal(v.acao, 'denunciar', categoria);
    }
  });

  it('grave fraco + ambígua forte: denuncia com as duas, não remove', () => {
    const v = veredito(resultado(
      { categoria: 'ameaca', confianca: 0.6 },
      { categoria: 'racismo', confianca: 0.9 },
    ));
    assert.equal(v.acao, 'denunciar');
    // Ordenadas por confiança: a primeira vira o `reason` da denúncia.
    assert.deepEqual(v.categorias, ['racismo', 'ameaca']);
    assert.equal(v.confianca, 0.9);
  });

  it('grave forte + ambígua: remove e lista as duas', () => {
    const v = veredito(resultado(
      { categoria: 'sexual-menores', confianca: 0.97 },
      { categoria: 'golpe', confianca: 0.7 },
    ));
    assert.equal(v.acao, 'remover');
    assert.deepEqual(v.categorias, ['sexual-menores', 'golpe']);
  });
});

describe('o piso do ruído', () => {
  it('abaixo do piso não vira nem denúncia', () => {
    // Alarme falso é o que ensina a ignorar a fila.
    const v = veredito(resultado({ categoria: 'racismo', confianca: CORTE_SUSPEITA - 0.01 }));
    assert.equal(v.acao, 'nada');
    assert.deepEqual(v.categorias, []);
  });

  it('no piso exato, denuncia', () => {
    const v = veredito(resultado({ categoria: 'racismo', confianca: CORTE_SUSPEITA }));
    assert.equal(v.acao, 'denunciar');
  });

  it('lista vazia é post limpo: nada', () => {
    assert.equal(veredito(resultado()).acao, 'nada');
  });
});

describe('bloqueio do Vertex é sinal, não falha', () => {
  it('PROHIBITED_CONTENT remove — o filtro de maior precisão do Google', () => {
    const v = veredito({ bloqueio: 'PROHIBITED_CONTENT' });
    assert.equal(v.acao, 'remover');
    assert.deepEqual(v.categorias, ['bloqueado-pelo-filtro']);
  });

  it('bloqueio genérico (SAFETY e afins) só denuncia', () => {
    for (const bloqueio of ['SAFETY', 'BLOCKLIST', 'OTHER']) {
      const v = veredito({ bloqueio });
      assert.equal(v.acao, 'denunciar', bloqueio);
      assert.deepEqual(v.categorias, ['bloqueado-pelo-filtro']);
    }
  });
});

describe('na dúvida, humano — nunca erro, nunca remoção', () => {
  it('resposta nula ou marcada inválida vira denúncia', () => {
    for (const r of [null, undefined, { invalida: true }]) {
      const v = veredito(r);
      assert.equal(v.acao, 'denunciar');
      assert.deepEqual(v.categorias, ['resposta-invalida']);
    }
  });

  it('categorias fora do contrato viram denúncia', () => {
    // O schema pede o enum, mas schema é pedido, não garantia. Categoria
    // inventada não pode remover nem sumir em silêncio.
    for (const r of [
      { categorias: 'não é lista' },
      resultado({ categoria: 'heresia', confianca: 0.99 }),
      resultado({ categoria: 'ameaca', confianca: 'alta' }),
      resultado({ categoria: 'ameaca', confianca: 7 }),
      resultado(null),
    ]) {
      const v = veredito(r);
      assert.equal(v.acao, 'denunciar');
      assert.deepEqual(v.categorias, ['resposta-invalida']);
    }
  });

  it('entrada torta misturada com válida: a válida decide, a torta cai fora', () => {
    const v = veredito(resultado(
      { categoria: 'heresia', confianca: 0.99 },
      { categoria: 'ameaca', confianca: 0.9 },
    ));
    assert.equal(v.acao, 'remover');
    assert.deepEqual(v.categorias, ['ameaca']);
  });
});
