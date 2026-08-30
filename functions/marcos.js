/**
 * A régua dos marcos: a primeira, e depois de tantas em tantas.
 *
 * Módulo puro, testável sem emulador. Ver `docs/specs/notificacoes.md`.
 */

/** Curtidas: a 1ª, depois 10, 20, 30… */
export const PASSO_CURTIDAS = 10;

/** Comentários: o 1º, depois 5, 10, 15… */
export const PASSO_COMENTARIOS = 5;

/**
 * O maior marco menor ou igual a [n], ou `null` se [n] não alcançou nenhum.
 *
 * **Derivar, e não testar igualdade.** `n === 1 || n % passo === 0` está errado,
 * e o modo de falha é o silêncio: com a contagem em 9, duas curtidas
 * simultâneas podem fazer as duas invocações lerem **11**, e o teste de
 * igualdade não notifica ninguém. Marcador impede repetir; nunca inventa o que
 * faltou.
 *
 * Com a derivação, as duas leem 11, as duas derivam 10, uma só ganha o
 * `create()`, e sai uma notificação. **A corrida vira o caso normal.**
 *
 * De quebra o sistema fica **auto-curativo**: um marco perdido por falha da
 * função é recuperado pela próxima curtida — o que torna seguro não repetir a
 * invocação. Só a última curtida da vida de um post perde o marco de vez.
 */
export function marcoDe(n, passo) {
  if (!Number.isFinite(n) || n < 1) return null;
  return n < passo ? 1 : Math.floor(n / passo) * passo;
}

/** O id do marcador em `posts/{postId}/marcos`. */
export function idDoMarco(tipo, marco) {
  return `${tipo}_${marco}`;
}
