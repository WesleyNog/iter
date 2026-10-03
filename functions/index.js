/**
 * O ponto de entrada das Cloud Functions do iter.
 *
 * **A primeira Function do projeto.** O `CLAUDE.md` registra o que vem antes
 * dela: orçamento e alerta de faturamento. A razão é que, a partir daqui,
 * escrita alheia deixa de custar quota e passa a custar dinheiro do dono — cada
 * curtida de qualquer pessoa em qualquer post acorda um processo que ele paga.
 *
 * Este arquivo só registra gatilhos. A decisão de cada um mora no módulo dele,
 * e o que é decisão pura mora em `texto.js`, `marcos.js` e `rank.js` — que são
 * testáveis com `node --test`, sem emulador, como `lib/Utils/` é no Dart.
 *
 * Ver `docs/specs/notificacoes.md`.
 */

// A região de cada gatilho vem de `opcoes.js`, passada explicitamente na
// declaração — e **não** por `setGlobalOptions`. A razão está escrita lá: o
// re-export abaixo é içado, então ele avalia antes de qualquer linha do corpo
// deste arquivo, e um `setGlobalOptions()` aqui chegaria tarde demais. O
// endpoint saía sem região, rumo a `us-central1`, incompatível com o banco.
export { convite, aceite } from './amizade.js';
export { ranking } from './ranking.js';
export { curtidas, comentarios } from './posts.js';
export { excluirConta } from './conta.js';
export { moderacaoPosts, moderacaoComentarios } from './moderacao.js';
