/**
 * O comparador do ranking, do lado do servidor.
 *
 * **Este arquivo é um espelho de `lib/Utils/ranking.dart`, e os dois mudam
 * juntos.** Não há compilador ligando as duas pontas: a divergência é silenciosa
 * por construção, e a única defesa é `test/rank.test.mjs`, que repete os casos de
 * `test/unit/ranking_test.dart` com os mesmos números.
 *
 * O que **não** foi duplicado, e é o ponto do desenho: `rankBy`. Ultrapassagem é
 * **paridade**, não classificação — `_compare` no Dart não olha nenhum terceiro
 * participante, não há percentil nem média do grupo. Duplicar a ordenação
 * inteira seria a armadilha que o `CLAUDE.md` documenta em
 * `VehicleController.activeFrom()`: duas implementações da mesma ordenação, e a
 * que ficar para trás faz o push discordar da tela.
 *
 * Ver `docs/specs/notificacoes.md`.
 */

/** `ranking.dart`: `minimumRoutes`. */
export const MINIMO_DE_ROTAS = 5;

/** Os três critérios, com o mesmo `name` do enum do Dart. */
export const CRITERIOS = ['rotas', 'ritmo', 'insucesso'];

/**
 * Os **sete inteiros** que `MonthStats.toMap()` grava, e o contrato inteiro
 * entre o app e este arquivo. Renomear qualquer um quebra a Function em
 * silêncio.
 */
function inteiro(valor) {
  return typeof valor === 'number' && Number.isFinite(valor)
    ? Math.trunc(valor)
    : null;
}

/**
 * Espelho de `MonthStats.fromMap`.
 *
 * `packagedRoutes` ausente cai em `routes`, **não em zero**: é documento antigo,
 * escrito antes de o campo existir, e essa é a régua com que ele foi feito. Cair
 * em zero jogaria gente para o rodapé "ainda sem amostra", que parece defeito e
 * não é o que o documento diz.
 *
 * `pacedRoutes` **não** tem régua antiga em que cair: o documento velho não sabe
 * quantas paradas foram feitas nas rotas cronometradas. Zero vira ritmo `null`,
 * que é a verdade — "não dá para calcular".
 */
export function lerBalde(dados) {
  const rotas = inteiro(dados?.routes) ?? 0;

  return {
    routes: rotas,
    packages: inteiro(dados?.packages) ?? 0,
    failures: inteiro(dados?.failures) ?? 0,
    packagedRoutes: inteiro(dados?.packagedRoutes) ?? rotas,
    pacedRoutes: inteiro(dados?.pacedRoutes) ?? 0,
    pacedMinutes: inteiro(dados?.pacedMinutes) ?? 0,
    pacedStops: inteiro(dados?.pacedStops) ?? 0,
  };
}

/** Balde ausente é mês parado, não erro — igual ao que a `RankingTab` faz. */
export const BALDE_VAZIO = lerBalde({});

/**
 * O valor de cada critério. `null` é **"não dá para calcular"**, nunca zero:
 * colapsar em zero coroaria campeão quem não entregou nada.
 *
 * Os dois são **derivados e nunca gravados** — o balde guarda numerador e
 * denominador, e a conta é refeita aqui. `1 insucesso em 8 pacotes` e `125 em
 * 1000` dão a mesma porcentagem e não são o mesmo problema.
 */
const VALOR = {
  rotas: (b) => b.routes,
  // `routePace.dart`: precisa dos dois lados, senão não é ritmo de ninguém.
  ritmo: (b) =>
    b.pacedMinutes > 0 && b.pacedStops > 0 ? b.pacedMinutes / b.pacedStops : null,
  insucesso: (b) => (b.packages === 0 ? null : (b.failures / b.packages) * 100),
};

/** As rotas que **formaram** o valor — não as do mês. */
const ROTAS_DA_AMOSTRA = {
  rotas: (b) => b.routes,
  ritmo: (b) => b.pacedRoutes,
  insucesso: (b) => b.packagedRoutes,
};

/** O denominador: paradas no ritmo, pacotes no insucesso. */
const UNIDADES_DA_AMOSTRA = {
  rotas: () => null,
  ritmo: (b) => b.pacedStops,
  insucesso: (b) => b.packages,
};

/**
 * Uma linha do ranking, para um uid e um critério.
 *
 * A exceção do critério `rotas` é **dupla**: não há amostra mínima e o valor
 * nunca é `null`, então toda linha de rotas é sempre `ranked` — inclusive a de
 * quem rodou zero. Exigir amostra ali esconderia justamente quem rodou pouco,
 * que é o que aquela disputa mede.
 */
export function linha(uid, criterio, balde) {
  const valor = VALOR[criterio](balde);
  const rotasDaAmostra = ROTAS_DA_AMOSTRA[criterio](balde);

  return {
    uid,
    valor,
    rotasDaAmostra,
    unidadesDaAmostra: UNIDADES_DA_AMOSTRA[criterio](balde),
    disputa:
      valor !== null &&
      (criterio === 'rotas' || rotasDaAmostra >= MINIMO_DE_ROTAS),
  };
}

/** Nunca `localeCompare`: o `compareTo` do Dart é por unidade de código. */
const cmp = (x, y) => (x < y ? -1 : x > y ? 1 : 0);

/**
 * Negativo se [a] está **na frente** de [b]. Espelho de `_compare`, com duas
 * linhas que o Dart não tem.
 *
 * No Dart, a regra do rodapé mora na concatenação de `rankBy`
 * (`[...disputa, ...fora]`); aqui não há lista, então ela vira código: **quem
 * não disputa está atrás de todo mundo que disputa, e a ordem interna do rodapé
 * não é posição.** Devolver 0 entre dois não-classificados é o que impede o
 * detector de ler "entrou na disputa" como "ultrapassou".
 */
export function comparar(criterio, a, b) {
  if (a.disputa !== b.disputa) return a.disputa ? -1 : 1;
  if (!a.disputa) return 0;

  // Em rotas, maior é melhor. Em ritmo e insucesso, menor é melhor.
  const porValor =
    criterio === 'rotas' ? cmp(b.valor, a.valor) : cmp(a.valor, b.valor);
  if (porValor !== 0) return porValor;

  // Empate no número: mais amostra sustenta melhor o mesmo valor.
  const porRotas = cmp(b.rotasDaAmostra, a.rotasDaAmostra);
  if (porRotas !== 0) return porRotas;

  // 1% de 1.000 pacotes sustenta melhor que 1% de 100. `?? 0` e não `|| 0`:
  // em rotas o denominador é `null` dos dois lados, e `||` trataria 0 como
  // ausente — mesma coisa aqui, mas não no dia em que um critério novo tiver
  // denominador zero legítimo.
  const porUnidades = cmp(b.unidadesDaAmostra ?? 0, a.unidadesDaAmostra ?? 0);
  return porUnidades !== 0 ? porUnidades : cmp(a.uid, b.uid);
}

/**
 * **A pergunta inteira do evento 3:** quem gravou passou o amigo neste critério?
 *
 * O balde do amigo entra **igual nos dois lados**, e é isso que isola o
 * movimento de quem gravou. Comparar o "antes" de quem gravou contra o "antes"
 * do amigo contaria de novo um movimento do amigo que já disparou o gatilho
 * dele — e o mesmo evento notificaria duas vezes, de dois lados.
 *
 * Três propriedades saem de graça do `antes > 0 && agora < 0`:
 * - quem estava no rodapé e continua no rodapé dá 0 dos dois lados: não notifica;
 * - **quem apenas cruza a amostra mínima e entra na disputa contra alguém que
 *   também está no rodapé dá `0 → -1`: não notifica** — entrar não é
 *   ultrapassar, e é o caso mais comum no começo do mês;
 * - quem entra e passa alguém classificado dá `1 → -1`: notifica.
 */
export function passou({ criterio, antes, depois, amigo }) {
  const linhaAmigo = linha('amigo', criterio, amigo);

  const estava = comparar(criterio, linha('autor', criterio, antes), linhaAmigo);
  const esta = comparar(criterio, linha('autor', criterio, depois), linhaAmigo);

  return estava > 0 && esta < 0;
}

/** Se algum dos sete inteiros mudou. É o primeiro portão do gatilho. */
export function baldeMudou(antes, depois) {
  return (
    antes.routes !== depois.routes ||
    antes.packages !== depois.packages ||
    antes.failures !== depois.failures ||
    antes.packagedRoutes !== depois.packagedRoutes ||
    antes.pacedRoutes !== depois.pacedRoutes ||
    antes.pacedMinutes !== depois.pacedMinutes ||
    antes.pacedStops !== depois.pacedStops
  );
}
