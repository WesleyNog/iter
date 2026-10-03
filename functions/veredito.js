/**
 * A tabela de decisão da moderação automática — decisão pura, sem I/O.
 *
 * Ver `docs/specs/moderacao-automatica.md`. O desenho inteiro cabe numa
 * frase: **a lápide destrói** (`text: ''`, sem volta pelas regras), então a
 * máquina só remove sozinha no degrau grave com confiança alta, e todo o
 * resto vira denúncia automática na fila do painel — a máquina tria, o dono
 * julga.
 *
 * Racismo está em AMBIGUAS **de propósito**, apesar de ser crime: é a
 * categoria em que o classificador mais erra em pt-BR (gíria, ironia,
 * citação), e o custo do falso positivo é destruir post inocente. Promover
 * ao degrau grave é mover uma string de lista — depois que a fila do painel
 * mostrar a precisão real, com dados e não chute.
 */

/** Removem sozinhas, quando a confiança passa do corte. */
export const GRAVES = ['sexual-menores', 'ameaca'];

/** Nunca removem sozinhas: viram denúncia para o humano julgar. */
export const AMBIGUAS = ['racismo', 'golpe', 'sexual-explicito'];

/**
 * O corte do degrau grave. `>=`, e o teste prende os dois lados: 0.8 remove,
 * 0.79 denuncia.
 */
export const CORTE_GRAVE = 0.8;

/**
 * Abaixo disto a categoria nem vira denúncia — ruído do modelo. Sem este
 * piso, qualquer "racismo 0.05" encheria a fila de alarme falso e o alarme
 * falso é o que ensina a ignorar a fila.
 */
export const CORTE_SUSPEITA = 0.5;

/**
 * O veredito: `{ acao, categorias, confianca }`.
 *
 * `acao` é `'remover'`, `'denunciar'` ou `'nada'`. `categorias` são as que
 * sobreviveram ao piso, para o cartão do painel; `confianca` é a maior
 * delas, ou `null` quando a decisão não veio de categoria nenhuma (bloqueio,
 * resposta inválida).
 *
 * O contrato de entrada é o que `gemini.js` devolve:
 *   { categorias: [{categoria, confianca}] }  — a resposta normal
 *   { bloqueio: 'PROHIBITED_CONTENT' | … }    — o Vertex recusou a entrada
 *   { invalida: true }                        — respondeu, mas fora da forma
 *
 * **O bloqueio irredutível é sinal, não falha.** `PROHIBITED_CONTENT` é o
 * filtro de maior precisão do Google disparando sobre a pior categoria —
 * remove. Qualquer outro bloqueio é mais impreciso e vira denúncia.
 *
 * **Resposta malformada vira denúncia, não erro**: lançar aqui mandaria o
 * retry re-perguntar a um modelo que respondeu torto de propósito ou por
 * limitação — na dúvida, humano. Falha de transporte (rede, quota) nunca
 * chega aqui: `gemini.js` lança antes, e o retry da plataforma cuida.
 */
export function veredito(resultado) {
  if (resultado == null || resultado.invalida === true) {
    return { acao: 'denunciar', categorias: ['resposta-invalida'], confianca: null };
  }

  if (typeof resultado.bloqueio === 'string') {
    return {
      acao: resultado.bloqueio === 'PROHIBITED_CONTENT' ? 'remover' : 'denunciar',
      categorias: ['bloqueado-pelo-filtro'],
      confianca: null,
    };
  }

  if (!Array.isArray(resultado.categorias)) {
    return { acao: 'denunciar', categorias: ['resposta-invalida'], confianca: null };
  }

  // Só o que é conhecido e bem formado. O schema pede o enum, mas schema é
  // pedido, não garantia — categoria inventada ou confiança fora de [0, 1]
  // não pode nem remover nem sumir em silêncio.
  const validas = resultado.categorias.filter(
    (c) => c != null
      && (GRAVES.includes(c.categoria) || AMBIGUAS.includes(c.categoria))
      && typeof c.confianca === 'number'
      && c.confianca >= 0 && c.confianca <= 1,
  );

  // Respondeu algo que não dá para ler: o mesmo "na dúvida, humano" da
  // resposta malformada. Lista vazia de verdade — nada sinalizado — segue
  // para o piso abaixo e vira 'nada'.
  if (validas.length === 0 && resultado.categorias.length > 0) {
    return { acao: 'denunciar', categorias: ['resposta-invalida'], confianca: null };
  }

  const relevantes = validas.filter((c) => c.confianca >= CORTE_SUSPEITA);
  if (relevantes.length === 0) return { acao: 'nada', categorias: [], confianca: null };

  const remover = relevantes.some(
    (c) => GRAVES.includes(c.categoria) && c.confianca >= CORTE_GRAVE,
  );

  // Ordena por confiança: a primeira vira o `reason` da denúncia automática.
  const ordenadas = [...relevantes].sort((a, b) => b.confianca - a.confianca);

  return {
    acao: remover ? 'remover' : 'denunciar',
    categorias: ordenadas.map((c) => c.categoria),
    confianca: ordenadas[0].confianca,
  };
}
