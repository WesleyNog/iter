/**
 * As frases das notificações e o destino de cada toque, num lugar só.
 *
 * Módulo puro: nenhuma dependência do Firebase, testável com `node --test` sem
 * emulador. É o equivalente Node do que `lib/Utils/` é no Dart, e pela mesma
 * razão — decisão que mora dentro de um gatilho não tem como ser testada.
 *
 * Ver `docs/specs/notificacoes.md`.
 */

/**
 * O padrão das duas linhas: **o título é o sujeito da frase, o corpo é o
 * predicado.**
 *
 * "Cleyton" / "enviou um convite de amizade pra você" lê como uma frase só na
 * bandeja, que é como o sistema desenha as duas. E é isso que explica por que os
 * marcos fogem do padrão: em "Seu post chegou a 10 curtidas" não há uma pessoa
 * para ser sujeito — nomear a última que curtiu creditaria quem não fez o marco.
 */

/** O fallback de nome do app inteiro, para não haver dois. */
export const SEM_NOME = 'Entregador';

/**
 * O primeiro nome, que é o que cabe num título de notificação.
 *
 * Recebe o documento de `profiles/{uid}` — nunca um nome que tenha vindo dentro
 * do post ou do comentário. Autor denormalizado é personificação de graça, e a
 * regra não tem como conferi-lo contra a projeção; a spec de amigos registra
 * isso e vale igual aqui.
 */
export function primeiroNome(perfil) {
  const nome = typeof perfil?.name === 'string' ? perfil.name.trim() : '';
  if (nome === '') return SEM_NOME;
  return nome.split(/\s+/)[0];
}

/**
 * O rótulo de cada critério do ranking.
 *
 * **Cópia de `RankCriterion.label` em `lib/Utils/ranking.dart`, e os dois mudam
 * juntos.** É a segunda fronteira Dart↔JS desta feature, junto com os sete
 * campos de `MonthStats`; nenhuma das duas tem compilador que as una, e é por
 * isso que estão escritas nas duas pontas como contrato.
 */
const ROTULO_DO_CRITERIO = {
  rotas: 'Rotas',
  ritmo: 'Ritmo',
  insucesso: 'Insucesso',
};

/**
 * O pedaço do post que lembra ao dono de qual publicação se fala.
 *
 * É o texto **dele**, não de terceiro: o corpo de uma notificação aparece na
 * tela de bloqueio, fora do alcance de qualquer regra, e conteúdo de outra
 * pessoa ali é a porta que o bloqueio existe para fechar.
 */
export function trechoDoPost(texto, limite = 50) {
  if (typeof texto !== 'string') return null;
  const limpo = texto.replace(/\s+/g, ' ').trim();
  if (limpo === '') return null;
  return limpo.length <= limite ? limpo : `${limpo.slice(0, limite).trimEnd()}…`;
}

function comTrecho(corpo, trecho) {
  return trecho == null ? corpo : `${corpo} “${trecho}”`;
}

/**
 * Todo valor do `data` de uma mensagem FCM **precisa ser string**, e chave sem
 * valor não vai — `NotificationTarget.fromData` no Dart trata ausente e vazio
 * como a mesma coisa, então mandar `null` só ocuparia bytes.
 */
function dados(mapa) {
  const saida = {};
  for (const [chave, valor] of Object.entries(mapa)) {
    if (valor === null || valor === undefined) continue;
    const texto = String(valor);
    if (texto !== '') saida[chave] = texto;
  }
  return saida;
}

/** Alguém te convidou. */
export function convite({ de, nome, para }) {
  return {
    titulo: nome,
    corpo: 'enviou um convite de amizade pra você',
    data: dados({ tipo: 'convite', de, para }),
  };
}

/** Alguém aceitou o convite que você mandou. */
export function aceite({ de, nome, para }) {
  return {
    titulo: nome,
    corpo: 'aceitou seu convite de amizade',
    data: dados({ tipo: 'aceite', de, para }),
  };
}

/** Um amigo te ultrapassou no ranking do mês. */
export function ranking({ de, nome, para, criterio, mes }) {
  const rotulo = ROTULO_DO_CRITERIO[criterio];
  // Critério desconhecido não vira frase torta: melhor não avisar do que
  // anunciar "passou você em undefined".
  if (rotulo === undefined) return null;

  return {
    titulo: nome,
    corpo: `passou você em ${rotulo}`,
    data: dados({ tipo: 'ranking', de, para, criterio, mes }),
  };
}

/**
 * Marco de curtidas: a primeira, depois 10, 20, 30…
 *
 * **Ninguém é nomeado, nem na primeira.** No marco, apontar a última pessoa
 * credita quem não o fez; e na primeira há uma razão mais forte — a regra de
 * `likes` **não** chama `bloqueioEntre`, então quem foi bloqueado ainda pode
 * curtir. Nomear entregaria o nome do bloqueado na tela de bloqueio da vítima,
 * furando por push o bloqueio que a regra do comentário sustenta.
 */
export function curtidas({ marco, para, postId, trecho }) {
  const primeira = marco === 1;

  return {
    titulo: primeira ? 'Primeira curtida' : `${marco} curtidas`,
    // "chegou a" continua verdadeiro com 11 e continua verdadeiro se caiu para
    // 9. "tem 10 curtidas" é falso nos dois casos — e a corrida garante que o
    // número do envio quase nunca é o número do marco.
    corpo: comTrecho(
      primeira
        ? 'Seu post recebeu a primeira curtida.'
        : `Seu post chegou a ${marco} curtidas.`,
      trecho,
    ),
    data: dados({ tipo: 'curtidas', para, postId }),
  };
}

/**
 * Marco de comentários: o primeiro, depois 5, 10, 15…
 *
 * O primeiro **nomeia quem comentou**, e a assimetria com a curtida é
 * deliberada: a regra de `comments` chama `bloqueioEntre` nos dois sentidos,
 * então quem comentou não é bloqueado de ninguém. O que nunca vai é o **texto**
 * do comentário — conteúdo de terceiro na tela de bloqueio.
 */
export function comentarios({ marco, nome, de, para, postId, trecho }) {
  if (marco === 1) {
    return {
      titulo: nome,
      corpo: 'comentou no seu post',
      data: dados({ tipo: 'comentarios', de, para, postId }),
    };
  }

  return {
    titulo: `${marco} comentários`,
    corpo: comTrecho(`Seu post chegou a ${marco} comentários.`, trecho),
    data: dados({ tipo: 'comentarios', para, postId }),
  };
}
