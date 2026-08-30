/**
 * As opções compartilhadas por todos os gatilhos.
 *
 * **A região vai explícita em cada gatilho, e não por `setGlobalOptions`.**
 *
 * O motivo é mecânico e custou um susto: `export { x } from './y.js'` é uma
 * declaração de módulo, e declarações de módulo são **içadas**. O `./y.js`
 * avalia — e portanto o gatilho é declarado — *antes* de qualquer linha do corpo
 * do `index.js` rodar, `setGlobalOptions()` inclusive. O endpoint saía sem
 * região nenhuma, e um gatilho de Firestore em `us-central1` com o banco em
 * `southamerica-east1` é incompatível por construção.
 *
 * Passar a constante em cada declaração é imune à ordem de avaliação, e
 * continua havendo **um** lugar para mudar.
 */

/**
 * A mesma região do Firestore do projeto, verificada com
 * `firebase firestore:databases:get "(default)" --project iter-mn`.
 *
 * Não é preferência: gatilho de 2ª geração exige região compatível com a do
 * banco. E é onde os entregadores estão.
 */
export const REGIAO = 'southamerica-east1';
