import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  BALDE_VAZIO,
  MINIMO_DE_ROTAS,
  baldeMudou,
  comparar,
  lerBalde,
  linha,
  passou,
} from '../rank.js';

/**
 * **Este arquivo é a única coisa que segura a fronteira Dart↔JS do ranking.**
 *
 * Os casos e os **números** vêm de `test/unit/ranking_test.dart`. Não há
 * compilador ligando `rank.js` a `lib/Utils/ranking.dart`: se alguém mudar a
 * regra de um lado só, é aqui que aparece — e em nenhum outro lugar.
 */

/** Espelho de `_stats` no teste do Dart, com os mesmos padrões. */
const balde = ({
  rotas = 10,
  pacotes = 0,
  insucessos = 0,
  comPacotes,
  cronometradas = 0,
  minutos = 0,
  paradas = 0,
} = {}) =>
  lerBalde({
    routes: rotas,
    packages: pacotes,
    failures: insucessos,
    packagedRoutes: comPacotes ?? (pacotes > 0 ? rotas : 0),
    pacedRoutes: paradas > 0 ? cronometradas : 0,
    pacedMinutes: paradas > 0 ? minutos : 0,
    pacedStops: paradas,
  });

/** Ordena dois uids pelo critério, como `rankBy` faria com dois participantes. */
function ordem(criterio, mapa) {
  return Object.entries(mapa)
    .map(([uid, b]) => linha(uid, criterio, b))
    .sort((a, b) => comparar(criterio, a, b))
    .map((l) => l.uid);
}

describe('rotas — maior primeiro, sem amostra mínima', () => {
  it('ordena do maior para o menor', () => {
    assert.deepEqual(
      ordem('rotas', { poucas: balde({ rotas: 3 }), muitas: balde({ rotas: 20 }) }),
      ['muitas', 'poucas'],
    );
  });

  it('quem não rodou aparece com zero, e zero é resposta', () => {
    const l = linha('parado', 'rotas', balde({ rotas: 0 }));
    assert.equal(l.valor, 0);
    // Dupla exceção do critério: sem amostra mínima e sem valor nulo, toda
    // linha de rotas disputa — inclusive a de quem rodou zero.
    assert.equal(l.disputa, true);
  });
});

describe('ritmo — menor primeiro, e por parada', () => {
  it('quem gasta menos tempo por parada lidera', () => {
    const r = ordem('ritmo', {
      lento: balde({ cronometradas: 10, minutos: 5400, paradas: 600 }),
      rapido: balde({ cronometradas: 10, minutos: 3000, paradas: 500 }),
    });

    assert.deepEqual(r, ['rapido', 'lento']);
    assert.equal(
      linha('rapido', 'ritmo', balde({ cronometradas: 10, minutos: 3000, paradas: 500 })).valor,
      6,
    );
  });

  it('a rota grande ganha da rota curta — o caso que motivou a troca', () => {
    // Os números da tela do usuário: 17 rotas em 2h49 de média contra 5 em
    // 4h27. Pela duração, um abismo; pelo ritmo, praticamente empatados.
    const wesley = balde({ rotas: 17, cronometradas: 17, minutos: 2873, paradas: 506 });
    const meu = balde({ rotas: 5, cronometradas: 5, minutos: 1335, paradas: 221 });

    assert.deepEqual(ordem('ritmo', { wesley, meu }), ['wesley', 'meu']);
    assert.ok(Math.abs(linha('w', 'ritmo', wesley).valor - 5.7) < 0.05);
    assert.ok(Math.abs(linha('m', 'ritmo', meu).valor - 6.0) < 0.05);
  });

  it('quem nunca preenche hora de fim fica fora da disputa', () => {
    // `null` é "não dá para calcular", não "terminou instantaneamente".
    const l = linha('semFim', 'ritmo', balde({ rotas: 30 }));
    assert.equal(l.valor, null);
    assert.equal(l.disputa, false);
  });

  it('cronometrar sem informar paradas não dá ritmo', () => {
    // Há duração média, e não há ritmo. Sem denominador não é ritmo de ninguém.
    const l = linha('semParadas', 'ritmo', balde({ cronometradas: 10, minutos: 4800, paradas: 0 }));
    assert.equal(l.valor, null);
    assert.equal(l.disputa, false);
  });
});

describe('insucesso — menor primeiro', () => {
  it('menor taxa lidera', () => {
    assert.deepEqual(
      ordem('insucesso', {
        pior: balde({ rotas: 20, pacotes: 1000, insucessos: 30 }),
        melhor: balde({ rotas: 20, pacotes: 1000, insucessos: 10 }),
      }),
      ['melhor', 'pior'],
    );
  });

  it('quem nunca preenche pacotes fica fora', () => {
    const l = linha('semPacotes', 'insucesso', balde({ rotas: 30 }));
    assert.equal(l.valor, null);
    assert.equal(l.disputa, false);
  });
});

describe('amostra mínima — o caso que motivou a regra', () => {
  it('uma rota perfeita não ganha de quarenta rotas boas', () => {
    // 1 rota de 8 pacotes sem insucesso dá 0%, contra 40 rotas e 3.000
    // pacotes a 1,4%. Sem o mínimo, o 0% lideraria.
    const novato = balde({ rotas: 1, pacotes: 8 });
    const veterano = balde({ rotas: 40, pacotes: 3000, insucessos: 42 });

    assert.deepEqual(ordem('insucesso', { novato, veterano }), ['veterano', 'novato']);
    assert.equal(linha('n', 'insucesso', novato).disputa, false);
    assert.equal(linha('v', 'insucesso', veterano).disputa, true);
    // O número continua visível — fica fora da disputa, não escondido.
    assert.equal(linha('n', 'insucesso', novato).valor, 0);
  });

  it('exatamente o mínimo já disputa', () => {
    assert.equal(
      linha('nolimite', 'insucesso', balde({ rotas: MINIMO_DE_ROTAS, pacotes: 100 })).disputa,
      true,
    );
    assert.equal(
      linha('abaixo', 'insucesso', balde({ rotas: MINIMO_DE_ROTAS - 1, pacotes: 100 })).disputa,
      false,
    );
  });

  it('o mínimo não se aplica à contagem de rotas', () => {
    assert.equal(linha('poucas', 'rotas', balde({ rotas: 2 })).disputa, true);
  });

  it('o mínimo conta a população da média, não as rotas do mês', () => {
    // 40 rotas no mês, **uma** cronometrada. A porta antiga olhava as 40.
    const quaseNunca = balde({ rotas: 40, cronometradas: 1, minutos: 60, paradas: 40 });
    const l = linha('quaseNunca', 'ritmo', quaseNunca);

    assert.equal(l.disputa, false);
    assert.equal(l.valor, 1.5);
    // A amostra é uma rota, não 40 — é o que a correção do Dart conserta.
    assert.equal(l.rotasDaAmostra, 1);
  });
});

describe('desempate — a ordem não pode dançar', () => {
  it('mesmo valor: mais amostra na frente', () => {
    // Os dois dão 1%; quem tem 30 rotas sustenta melhor o mesmo número.
    assert.deepEqual(
      ordem('insucesso', {
        pouca: balde({ rotas: 6, pacotes: 100, insucessos: 1 }),
        muita: balde({ rotas: 30, pacotes: 1000, insucessos: 10 }),
      }),
      ['muita', 'pouca'],
    );
  });

  it('mesmo valor e mesmas rotas: mais denominador na frente', () => {
    // 1% de 1.000 pacotes e 1% de 100, as duas com dez rotas.
    assert.deepEqual(
      ordem('insucesso', {
        ana: balde({ rotas: 10, pacotes: 100, insucessos: 1 }),
        bia: balde({ rotas: 10, pacotes: 1000, insucessos: 10 }),
      }),
      ['bia', 'ana'],
    );
  });

  it('mesmo valor e mesma amostra: resolve pelo uid, em ordem de código', () => {
    const igual = balde({ rotas: 10, pacotes: 500, insucessos: 5 });
    assert.deepEqual(
      ordem('insucesso', { zeca: igual, ana: igual, bia: igual }),
      ['ana', 'bia', 'zeca'],
    );
  });
});

describe('lerBalde — o contrato de sete inteiros', () => {
  it('`packagedRoutes` ausente cai em `routes`, não em zero', () => {
    // Documento antigo, escrito antes do campo existir: essa é a régua com que
    // ele foi feito. Zero jogaria gente para o rodapé, que parece defeito.
    assert.equal(lerBalde({ routes: 17, packages: 100 }).packagedRoutes, 17);
  });

  it('`pacedRoutes` ausente cai em zero, porque não há régua antiga', () => {
    // O documento velho não sabe quantas paradas houve nas cronometradas.
    // Zero vira ritmo `null`, que é a verdade: não dá para calcular.
    const b = lerBalde({ routes: 17 });
    assert.equal(b.pacedRoutes, 0);
    assert.equal(linha('x', 'ritmo', b).valor, null);
  });

  it('documento ausente é mês parado, não erro', () => {
    assert.equal(BALDE_VAZIO.routes, 0);
    assert.equal(linha('x', 'rotas', BALDE_VAZIO).disputa, true);
    assert.equal(linha('x', 'ritmo', BALDE_VAZIO).disputa, false);
  });

  it('valor que não é número não vira número', () => {
    const b = lerBalde({ routes: '17', packages: null, failures: undefined });
    assert.equal(b.routes, 0);
    assert.equal(b.packages, 0);
    assert.equal(b.failures, 0);
  });
});

describe('baldeMudou — o primeiro portão do gatilho', () => {
  it('reescrita idêntica não é mudança', () => {
    // É o que torna o custo aceitável: a abertura do app reescreve doze baldes.
    const b = balde({ rotas: 10, pacotes: 100, insucessos: 1 });
    assert.equal(baldeMudou(b, lerBalde({ ...b })), false);
  });

  it('qualquer um dos sete muda', () => {
    const b = balde({ rotas: 10, pacotes: 100, insucessos: 1 });
    for (const campo of [
      'routes', 'packages', 'failures', 'packagedRoutes',
      'pacedRoutes', 'pacedMinutes', 'pacedStops',
    ]) {
      assert.equal(baldeMudou(b, { ...b, [campo]: b[campo] + 1 }), true, campo);
    }
  });
});

describe('passou — a pergunta inteira do evento 3', () => {
  const amigo = balde({ rotas: 12 });

  it('quem gravou passa o amigo: notifica', () => {
    assert.equal(
      passou({
        criterio: 'rotas',
        antes: balde({ rotas: 11 }),
        depois: balde({ rotas: 13 }),
        amigo,
      }),
      true,
    );
  });

  it('quem gravou continua atrás: não notifica', () => {
    assert.equal(
      passou({
        criterio: 'rotas',
        antes: balde({ rotas: 9 }),
        depois: balde({ rotas: 11 }),
        amigo,
      }),
      false,
    );
  });

  it('quem gravou já estava na frente: não notifica de novo', () => {
    assert.equal(
      passou({
        criterio: 'rotas',
        antes: balde({ rotas: 13 }),
        depois: balde({ rotas: 14 }),
        amigo,
      }),
      false,
    );
  });

  it('quem gravou PIORA e cai atrás: não notifica ninguém', () => {
    // A leitura de evento, e não de estado: quem grava é quem causa. Sob a
    // leitura de estado, o amigo receberia "você passou fulano" sem ter tocado
    // no app — e a frase seria falsa sobre ele.
    assert.equal(
      passou({
        criterio: 'rotas',
        antes: balde({ rotas: 14 }),
        depois: balde({ rotas: 10 }),
        amigo,
      }),
      false,
    );
  });

  it('entrar na disputa NÃO é ultrapassar', () => {
    // O caso mais comum do começo do mês: os dois no rodapé, um cruza a
    // amostra mínima. Vira `0 → -1`, que o guarda `antes > 0` rejeita.
    const semAmostra = balde({ rotas: 4, pacotes: 50, comPacotes: 4 });
    const comAmostra = balde({ rotas: 5, pacotes: 60, comPacotes: 5 });

    assert.equal(
      passou({
        criterio: 'insucesso',
        antes: semAmostra,
        depois: comAmostra,
        amigo: balde({ rotas: 3, pacotes: 30, comPacotes: 3 }),
      }),
      false,
    );
  });

  it('entrar na disputa e passar alguém CLASSIFICADO notifica', () => {
    const amigoClassificado = balde({ rotas: 20, pacotes: 1000, insucessos: 50 });

    assert.equal(
      passou({
        criterio: 'insucesso',
        antes: balde({ rotas: 4, pacotes: 50, insucessos: 0, comPacotes: 4 }),
        depois: balde({ rotas: 6, pacotes: 600, insucessos: 6, comPacotes: 6 }),
        amigo: amigoClassificado,
      }),
      true,
    );
  });

  it('no ritmo, menor é melhor: baixar o tempo por parada é passar', () => {
    const amigoRitmo = balde({ rotas: 10, cronometradas: 10, minutos: 3000, paradas: 500 });

    assert.equal(
      passou({
        criterio: 'ritmo',
        antes: balde({ rotas: 10, cronometradas: 10, minutos: 3500, paradas: 500 }),
        depois: balde({ rotas: 10, cronometradas: 10, minutos: 2500, paradas: 500 }),
        amigo: amigoRitmo,
      }),
      true,
    );
  });
});
