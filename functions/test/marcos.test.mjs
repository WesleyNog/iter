import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  PASSO_COMENTARIOS,
  PASSO_CURTIDAS,
  idDoMarco,
  marcoDe,
} from '../marcos.js';

const curtidas = (n) => marcoDe(n, PASSO_CURTIDAS);
const comentarios = (n) => marcoDe(n, PASSO_COMENTARIOS);

describe('marcoDe — curtidas: a 1ª, depois de dez em dez', () => {
  it('a primeira curtida é marco', () => {
    assert.equal(curtidas(1), 1);
  });

  it('a segunda ainda deriva o marco 1 — e é o que salva a auto-curtida', () => {
    // Todo mundo curte o próprio post. Como o dono não é notificado da própria
    // curtida e **não** deixa marcador, a curtida seguinte, de outra pessoa,
    // chega com a contagem em 2, deriva o marco 1 e anuncia a primeira de
    // verdade. Com teste de igualdade (`n === 1`) essa notificação se perdia
    // para sempre.
    assert.equal(curtidas(2), 1);
  });

  it('nove ainda é o marco 1, não o 10', () => {
    assert.equal(curtidas(9), 1);
  });

  it('dez é dez', () => {
    assert.equal(curtidas(10), 10);
  });

  it('ONZE deriva DEZ — o caso da corrida, e a razão de tudo isto', () => {
    // Com a contagem em 9, duas curtidas simultâneas podem fazer as duas
    // invocações lerem 11. Com `n % 10 === 0`, ninguém é notificado e o marco
    // se perde em silêncio. Derivando, as duas chegam em 10, uma só ganha o
    // `create()` do marcador, e sai exatamente uma notificação.
    assert.equal(curtidas(11), 10);
  });

  it('vinte e cinco deriva vinte', () => {
    assert.equal(curtidas(25), 20);
  });

  it('zero não é marco nenhum', () => {
    assert.equal(curtidas(0), null);
  });

  it('número inválido não vira marco', () => {
    // `PostController.likeCount` devolve 0 no `catch`. Na função, colapsar
    // "não consegui contar" em zero apagaria o evento — a mesma armadilha do
    // `getWeather`. Aqui o `null` protege o outro lado.
    assert.equal(marcoDe(NaN, PASSO_CURTIDAS), null);
    assert.equal(marcoDe(-3, PASSO_CURTIDAS), null);
  });
});

describe('marcoDe — comentários: o 1º, depois de cinco em cinco', () => {
  it('a régua é outra, a lógica é a mesma', () => {
    assert.equal(comentarios(1), 1);
    assert.equal(comentarios(4), 1);
    assert.equal(comentarios(5), 5);
    assert.equal(comentarios(6), 5);
    assert.equal(comentarios(9), 5);
    assert.equal(comentarios(10), 10);
    assert.equal(comentarios(15), 15);
  });

  it('a corrida também acontece aqui', () => {
    assert.equal(comentarios(7), 5);
    assert.equal(comentarios(12), 10);
  });
});

describe('a regra de parada: não desce para o marco anterior', () => {
  it('com 15 curtidas o marco é 10, e nunca 1', () => {
    // Se o marcador de 10 já existe, a função **sai** — não tenta o marco
    // anterior. Sem isso, alguém receberia "primeira curtida" atrasada, meses
    // depois, num post com quinze.
    assert.equal(curtidas(15), 10);
    assert.notEqual(curtidas(15), 1);
  });
});

describe('idDoMarco', () => {
  it('nomeia o tipo e o número', () => {
    assert.equal(idDoMarco('curtidas', 10), 'curtidas_10');
    assert.equal(idDoMarco('comentarios', 5), 'comentarios_5');
    assert.equal(idDoMarco('curtidas', 1), 'curtidas_1');
  });

  it('curtidas e comentários no mesmo número são ids DIFERENTES', () => {
    // Os dois marcos convivem no mesmo post e no mesmo número: dez curtidas e
    // dez comentários. Um id só por número faria o segundo silenciar o primeiro.
    assert.notEqual(idDoMarco('curtidas', 10), idDoMarco('comentarios', 10));
  });
});
