import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { diaDeFortaleza, mesDeFortaleza } from '../tempo.js';

describe('o dia é o de Fortaleza, não o do relógio da Function', () => {
  it('23h de Fortaleza ainda é o mesmo dia, apesar de já ser o seguinte em UTC', () => {
    // 28/08 02:00 UTC = 27/08 23:00 em Fortaleza. Com `toISOString()` cru, o
    // teto diário do aviso zeraria às 21h locais — no meio da noite de trabalho
    // de quem roda Amazon até as 23h.
    const agora = new Date('2026-08-28T02:00:00.000Z');

    assert.equal(diaDeFortaleza(agora), '2026-08-27');
    assert.notEqual(diaDeFortaleza(agora), agora.toISOString().slice(0, 10));
  });

  it('a virada do dia acontece à meia-noite local, não às 21h', () => {
    assert.equal(diaDeFortaleza(new Date('2026-08-28T02:59:59.999Z')), '2026-08-27');
    assert.equal(diaDeFortaleza(new Date('2026-08-28T03:00:00.000Z')), '2026-08-28');
  });

  it('o mês vira junto, e casa com o `monthKey` do Dart', () => {
    // 01/09 01:00 UTC ainda é 31/08 em Fortaleza: o balde do mês corrente é o
    // de agosto, e o portão do gatilho tem de concordar com a tela.
    assert.equal(mesDeFortaleza(new Date('2026-09-01T01:00:00.000Z')), '2026-08');
    assert.equal(mesDeFortaleza(new Date('2026-09-01T03:00:00.000Z')), '2026-09');
  });
});
