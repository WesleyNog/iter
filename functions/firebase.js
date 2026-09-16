/**
 * O acesso ao Firestore, num lugar só.
 *
 * Espelha o que `lib/services/firebase.dart` é no app: o **único** acessor, para
 * não haver dois caminhos até o mesmo banco.
 *
 * Inicialização preguiçosa de propósito — assim qualquer módulo daqui pode ser
 * importado por um teste sem que nada suba, e nenhum gatilho depende da ordem de
 * import do `index.js`.
 */

import { getApp, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

/**
 * O bucket do app, escrito por extenso — o mesmo `storageBucket` de
 * `lib/firebase_options.dart`.
 *
 * Explícito pela razão da `REGIAO` em `opcoes.js`: o padrão vem de
 * `FIREBASE_CONFIG`, que o deploy preenche e o emulador preenche do jeito dele,
 * e o teste do emulador precisa semear foto **no mesmo** bucket que a limpeza
 * apaga. Projetos criados depois de out/2024 usam `.firebasestorage.app`, não
 * `.appspot.com`.
 */
export const BUCKET = 'iter-mn.firebasestorage.app';

let instancia;

/**
 * O app padrão, criando-o se ainda não existir.
 *
 * **`try/getApp()` e não `getApps().length > 0`.** A primeira versão fazia isso
 * e a função morria na primeira invocação com "The default Firebase app does
 * not exist": haver *algum* app registrado não implica que o **padrão** exista,
 * e `getApp()` sem nome procura exatamente o padrão. O emulador pegou; nenhum
 * teste unitário pegaria, e em produção o sintoma seria a função morrer a cada
 * disparo com a notificação nunca saindo.
 */
export function app() {
  if (instancia) return instancia;

  try {
    instancia = getApp();
  } catch {
    instancia = initializeApp();
  }
  return instancia;
}

export function db() {
  return getFirestore(app());
}

export function bucket() {
  return getStorage(app()).bucket(BUCKET);
}
