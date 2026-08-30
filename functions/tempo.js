/**
 * O dia e o mês **de Fortaleza**, que é onde os entregadores estão.
 *
 * O relógio da Function é UTC. Formatar com `toISOString()` faria o "dia" virar
 * às 21h locais — e o teto diário do aviso de ultrapassagem, que carrega a data
 * no id, zeraria no meio da noite de trabalho de quem roda Amazon até as 23h.
 *
 * Num projeto que já trata fronteira de tempo local como assunto sério —
 * `RouteTime.resolveEnd`, a aritmética de semana pelo construtor de `DateTime` —
 * deixar essa passar seria incoerência.
 *
 * **UTC−3 fixo, e não uma biblioteca de fuso.** Fortaleza nunca teve horário de
 * verão, e o Brasil o aboliu em 2019; o deslocamento é constante. Uma biblioteca
 * de zonas seria uma dependência a mais para produzir o mesmo número.
 */

/** Fortaleza é UTC−3, o ano inteiro. */
const DESLOCAMENTO_MS = 3 * 60 * 60 * 1000;

function emFortaleza(agora) {
  return new Date(agora.getTime() - DESLOCAMENTO_MS);
}

/** `2026-08-27` — a parte do id do marcador que faz o teto ser diário. */
export function diaDeFortaleza(agora) {
  return emFortaleza(agora).toISOString().slice(0, 10);
}

/** `2026-08` — a mesma chave que `monthKey` gera no Dart. */
export function mesDeFortaleza(agora) {
  return emFortaleza(agora).toISOString().slice(0, 7);
}
