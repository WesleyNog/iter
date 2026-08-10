# Spec: Status "Sem Rota"

Status: **implementada** · Escrita, aprovada e implementada em 2026-08-10 ·
Falta a verificação no aparelho (tarefa 10) e os dois documentos no console

> **Leia antes a seção [Correções depois da varredura](#correções-depois-da-varredura)**,
> no fim deste arquivo. Uma varredura de 8 agentes sobre os 312 pontos do código
> que tocam status achou 95 falhas que aconteceriam **em silêncio** — sem erro de
> compilação e sem teste vermelho. Sete delas invalidam decisões do corpo desta
> spec, e a seção manda nelas.

## Objetivo

Registrar a ida que **não virou rota**: o app da empresa oferece, você aceita,
dirige até o CD e lá a rota acabou. A empresa paga assim mesmo — o Mercado
Livre paga 40% do valor, a Amazon paga 100% — e hoje o app não tem onde botar
isso.

Usuário: o entregador. Sucesso = ele marca **Sem Rota**, informa o valor cheio
que a rota valia e o KM que rodou até o CD e de volta, e o app grava o que ele
**realmente recebeu**, com gasolina e provisão descontadas como em qualquer
outra rota.

Hoje as saídas são três, e as três são erradas:

| o que dá para fazer hoje | por que mente |
|---|---|
| não cadastrar | some o dinheiro **e** o KM: a gasolina daquela ida fica fora do custo |
| cadastrar como `pago` com o valor cheio | ganho inflado — recebeu 40%, o app conta 100% |
| cadastrar como `pago` com 40% digitado na mão | o número certo, mas ninguém sabe de onde veio, e a conta é refeita de cabeça toda vez |

## A regra de negócio mora no banco

`norouterule/{empresa}`, com um campo `percent`:

```
norouterule/mercadolivre   { percent: 40 }
norouterule/amazon         { percent: 100 }
norouterule/shopee         (não existe)
```

O id do documento é `Company.name` — `mercadolivre`, `amazon`, `shopee` —, o
mesmo texto que `NewRouteModal.toMap()` já grava em `company`. Assim a regra é
alcançada por `get` de id conhecido, sem query e sem índice.

**Fica no banco, e não no código, porque é a empresa que decide.** O dia em que
o Mercado Livre passar de 40% para 35%, isso é uma edição no console — não uma
release na App Store.

### Sem regra cadastrada, não salva

A Shopee não tem documento, e nenhum dos dois defaults possíveis é honesto:

- **100%** superestima o ganho, que é sempre o lado que engana — a mesma razão
  de `getWeather` nunca devolver `clear` quando falhou e de `totalRatePerKm`
  devolver `null` em vez de só as peças.
- **0%** zera o valor, e de quebra apaga a provisão: `provisionFor` desiste com
  `value <= 0`, então a gasolina de uma ida que aconteceu de verdade sumiria.

Então o formulário **recusa** e diz o que fazer:

> Sem regra de pagamento cadastrada para a Shopee.

Resolve-se criando o documento no console. É a mesma escolha de `EconomyResult`
carregar um `gap` nomeando o que falta em vez de mostrar um número bonito e
errado.

`percent` válido é um número inteiro **de 1 a 100**. Fora disso — ausente, texto,
zero, negativo, 200 — vale como *sem regra*, pelo mesmo motivo: um documento
quebrado e uma regra de 0% são indistinguíveis pelo cliente, e o app não pode
adivinhar qual dos dois é.

## O que fica gravado

**O campo `value` guarda o que entrou no bolso**, já com o percentual aplicado.
Não é detalhe de implementação, são as duas propriedades que o app precisa:

**1. Todo agregado passa a funcionar sem ser tocado.** `valueByStatus`,
`summarize`, `companySummary`, `valuePerCompany`, `valuePerWeekday`,
`valuePerHour`, `RouteProvision.profitFrom` — todos leem `route.value`. Guardar
o valor cheio obrigaria cada um deles a saber da regra, e o primeiro que
esquecesse mostraria 100% de uma rota de 40%.

**2. O passado congela.** É o pilar do app, e ele vale aqui exatamente como
vale para a provisão: se o `value` fosse o valor cheio e o percentual fosse
aplicado na leitura, mudar `percent` de 40 para 30 hoje reescreveria o lucro de
junho. É o que a planilha faz e o que este app existe para não fazer.

Mas só o líquido não basta — sem a origem, editar a rota aplicaria o percentual
de novo sobre um valor que já veio descontado, e R$ 250 viraria R$ 100 e depois
R$ 40. Então vai junto um bloco congelado, irmão de `RouteProvision`:

```dart
class NoRoutePayment {
  final double grossValue;  // o que a rota valia cheia:  250,00
  final int    percent;     // o que a empresa paga:      40
  final String appliedAt;

  double get paid => …;     // 100,00 — o mesmo que NewRouteModal.value
}
```

Os três campos respondem três perguntas diferentes: `grossValue` é o que o
formulário reabre, `percent` é o que o card explica ("40% de R$ 250,00"), e
`paid` é a conferência — **invariante: `route.value == noRoutePayment.paid`**,
com um teste afirmando isso.

`paid` é **derivado**, não gravado dentro do bloco: valor derivado que se grava é
valor que um dia discorda da origem. Ele já está gravado uma vez, em `value`,
porque é lá que os agregados leem.

O arredondamento é para centavos, numa função só: `249,90 × 40%` são R$ 99,96, e
não `99.96000000000001` aparecendo num card.

## Congelar o percentual, e quando não congelar

`resolveNoRoutePayment` é a irmã de `resolveProvision`, com a mesma tabela:

| situação | resultado |
|---|---|
| status não é `semRota` | `null` — a rota deixou de ser uma ida perdida |
| `semRota`, sem bloco anterior | aplica a regra de **hoje** |
| `semRota`, mesma empresa | **mantém o percentual** e recalcula sobre o valor cheio informado |
| `semRota`, empresa mudou | aplica a regra de **hoje**, da empresa nova |
| `semRota`, sem regra e sem bloco | `null` — e o formulário recusa antes de chegar aqui |

A terceira linha é a que importa, e é a mesma frase da provisão: **corrigir o
valor de uma ida de junho não pode restampar o percentual de hoje**. A quarta é
a única exceção, e é óbvia — o percentual do Mercado Livre não descreve uma ida
da Amazon.

## O caso que quebraria em silêncio

`_fillFromRoute` preenche o campo Valor com `route.value`. Numa rota `semRota`,
`value` é o **líquido** — reabrir e salvar aplicaria os 40% outra vez.

Então: editando uma rota `semRota`, o campo Valor recebe
`noRoutePayment.grossValue`. O formulário sempre fala em valor cheio; o líquido
aparece na linha abaixo, calculado ao vivo.

Um teste de widget cobre exatamente isso — abrir uma rota de R$ 100 líquidos
com 40% e ver **R$ 250,00** no campo.

## Onde a Sem Rota entra, e onde não entra

A decisão: **ela é dinheiro e é quilômetro rodado, mas não é uma rota.** Você
saiu, gastou gasolina e recebeu — isso conta. Mas não entregou pacote nenhum,
não passou por bairro nenhum, e uma ida ao CD de 40 minutos entrando na média
de duração faria parecer que suas rotas ficaram mais rápidas.

| onde | entra? | por quê |
|---|---|---|
| `value` do período, barra de status | **sim** | é dinheiro do período |
| Card "Pago no período" | **sim**, somada | foi pago; é o que você pediu |
| `km` e `custo por km` do Resumo | **sim** | a gasolina foi queimada de verdade |
| Lucro (valor − gasolina − provisão) | **sim** | é a conta que diz se a ida valeu a pena |
| Nº de rotas, R$/rota, médias | **não** | não foi uma rota |
| Pacotes, paradas, insucesso, bairros | **não** | não existem numa ida sem rota |
| Gráficos de análise (empresa, bairro, dia, hora) | **não** | são "das rotas concluídas e pagas" |
| `MonthStats` / ranking de amigos | **não** | ninguém fica mais produtivo por uma rota que não teve |
| `ProfileStats` (carreira) | **não** | idem |

Em código, isso vira **duas réguas** em vez de uma:

```dart
List<NewRouteModal> realized(routes)  // concluido + pago      — INALTERADA
List<NewRouteModal> noRoute(routes)   // semRota               — nova
```

`realized` não muda uma linha, e é ela que alimenta `monthStats`,
`profileStats` e todos os carrosséis de análise. Quem precisa do dinheiro soma
as duas.

### As médias não podem misturar as duas

Se `TOTAL` inclui a Sem Rota e `ROTAS` não, então `TOTAL ÷ ROTAS` deixa de ser
"quanto rendeu uma rota". Por isso `PeriodSummary` ganha o dinheiro das rotas
separado do dinheiro total:

```dart
final double total;      // tudo do período, incl. sem rota  (denominador da barra)
final double routeTotal; // só rotas                          (numerador da média)
final int    count;      // só rotas
final double noRoute;    // só sem rota
final int    noRouteCount;

double get average => count == 0 ? 0 : routeTotal / count;
double get receivedTotal => received + noRoute;   // o que caiu na conta
```

`received` continua sendo só `pago`; quem soma é `receivedTotal`, e é ele que
vai para o card. Assim nenhuma média do app divide dinheiro de uma população
pela contagem de outra.

No card **"Pago no período"**, `PAGO` mostra `receivedTotal` e `MÉDIA/ROTA`
continua sendo `received ÷ receivedCount`. A diferença entre os dois é
explicada no rodapé, que só aparece quando há o que explicar:

> Inclui R$ 100,00 de idas sem rota.

### Na barra do "Resumo do período": fatia própria

Cinco fatias, e a nova em **verde claro** (`0xFFB9F6CA`) ao lado do verde do
Pago (`0xFF69F0AE`) — mesma família, porque as duas somam juntas no card
seguinte. Responde de graça uma pergunta que não existia: *quanto do meu mês
veio de rota que não teve rota?*

No card branco da lista a cor é outra (`blueGrey.shade400`), e o arquivo já
documenta por que as duas paletas existem: lá o fundo é o gradiente azul e o
que importa é a soma com o Pago; aqui o fundo é branco e o que importa é ler
"esta não aconteceu".

## Regras do Firestore

```
// A regra de pagamento de rota que acabou antes de começar.
match /norouterule/{company} {
  allow get: if request.auth != null;
  allow list: if false;
  allow write: if false;
}
```

Três decisões, e nenhuma é enfeite:

**`get` e não `read`.** `read` é `get` + `list`, e uma condição que não olha
`resource` autoriza baixar a coleção inteira. Aqui o dano seria pequeno, mas a
regra da casa é essa desde que `nicknames` entregou o mapa apelido → uid da base
toda, e abrir exceção é como a próxima coleção volta a ficar aberta.

**`list: if false`.** Não há consumidor: o app lê `norouterule/{empresa}` por id
conhecido, uma leitura, e o resultado fica no estado da tela.

**`write: if false`.** Esta é a linha que mais protege. É a **primeira coleção
do app que é configuração de negócio**, e não dado de usuário: `gastop` é
gravável porque quem passa no posto relata o preço, e o pior caso é um preço
errado que a mediana dilui. Aqui, um `create` liberado deixa qualquer conta
autenticada gravar `{percent: 0}` em `amazon` e zerar o pagamento de **todo
mundo** — ou `{percent: 10000}` e inflar. Quem edita é o dono, no console, onde
a escrita de admin não passa por estas regras.

Hoje a coleção não tem regra nenhuma, o que significa **negada** — o app ainda
não consegue lê-la. Sem esta match, a feature não funciona.

`iter/{uid}/routes` não muda: a rota continua sendo do dono, e o percentual já
chega congelado dentro dela.

> Fora de escopo, mas anotado: existe uma coleção `paymentRules` no banco, vazia
> de uso e sem regra. Não é tocada aqui.

## O que muda, arquivo por arquivo

| arquivo | mudança |
|---|---|
| `model/newRouteModal.dart` | `StatusRoute.semRota`; classe `NoRoutePayment`; campo `noRoutePayment` no modelo, no `toMap`/`fromMap` **e no `withProvision`** |
| `Utils/noRouteRule.dart` *(novo)* | `readPercent`, `noRoutePaidValue`, `resolveNoRoutePayment` — funções puras |
| `controller/noRouteRuleController.dart` *(novo)* | `fetchPercent(Company)` → `int?` |
| `Utils/routeStyle.dart` | rótulo, cor, cor de gráfico e ícone do novo status (4 `switch` exaustivos — o compilador cobra) |
| `Utils/routeStats.dart` | `noRoute()`; `receivedPayment` passa a incluir `semRota`; `PeriodSummary` ganha `routeTotal`, `noRoute`, `noRouteCount`, `receivedTotal`; `summarize` ganha o novo `case` |
| `Utils/companySummary.dart` | soma dinheiro/KM/lucro da Sem Rota; `routes` continua só das rotas; ganha `noRouteValue`/`noRouteCount` |
| `Utils/vehicleCost.dart` | `resolveProvision`: `done` passa a incluir `semRota` |
| `screens/addIter.dart` | item no dropdown, ícone, nome e cor do botão, busca da regra, linha do valor líquido, bloqueio sem regra, valor **cheio** ao editar |
| `widget/routeCard.dart` | linha "Pagamento: 40% de R$ 250,00"; `_profitBlock` passa a desenhar para `semRota` |
| `widget/companySummaryCard.dart` | linha das idas sem rota quando houver |
| `screens/graficsScreen.dart` | `PAGO` usa `receivedTotal`; média usa `routeTotal`; rodapé explicando a soma |
| `firestore.rules` | a match nova |
| `firestore-tests/rules.test.mjs` | 4 casos |
| `CLAUDE.md` | uma seção curta, como as outras decisões de pilar |

**`monthStats.dart`, `profileStats.dart` e os carrosséis de análise não mudam** —
e é isso que garante que a Sem Rota fique fora deles.

### Uma limpeza que entra junto, porque é a causa do risco

`addIter.dart` tem a lista de status escrita **três vezes**: no
`selectedItemBuilder`, nos `items` e no `switch` de `_getStatusIcon` — mais o
encadeado de cores do botão. Acrescentar um status significa lembrar dos quatro,
e esquecer de um é um status que existe no enum e não aparece no menu, sem erro
de compilação.

As listas passam a sair de `StatusRoute.values`. Não é refatoração oportunista:
é exatamente o lugar onde a feature falharia em silêncio.

## Comandos

```bash
flutter test                                   # tudo
flutter test test/unit/noRouteRule_test.dart   # a conta e o congelamento
flutter analyze
cd firestore-tests && npm test                 # regras, contra o emulador
firebase deploy --only firestore:rules         # depois de npm test passar
```

## Critérios de sucesso

- [ ] Marcar **Sem Rota** com Mercado Livre e R$ 250 grava `value: 100` e
      `noRoutePayment: {grossValue: 250, percent: 40}`.
- [ ] O mesmo com Amazon grava `value: 250, percent: 100`.
- [ ] Com Shopee, o formulário recusa e diz por quê; nada é gravado.
- [ ] Reabrir a rota mostra **R$ 250,00** no campo Valor, e salvar sem mexer em
      nada mantém `value: 100`.
- [ ] Trocar `percent` para 30 no console **não muda** nenhuma rota já gravada.
- [ ] Informando KM inicial e final, o card mostra Gasolina, Provisão e Lucro,
      como numa rota paga.
- [ ] O card "Pago no período" soma a Sem Rota; a barra do "Resumo" mostra a
      fatia própria; o total das duas bate.
- [ ] O nº de rotas do Resumo, o ranking de amigos e o perfil **não** contam a
      Sem Rota.
- [ ] `norouterule` é legível por qualquer autenticado e não gravável por
      ninguém pelo cliente.
- [ ] `flutter analyze` limpo e todos os testes passando.

## Fronteiras

**Sempre:** rodar `flutter test` e `npm test` antes de dizer que acabou; manter
o pt-BR nas strings de tela; `null` significa "não dá para saber", nunca zero.

**Perguntar antes:** mudar o significado de qualquer número já existente na
tela; mexer em `monthStats`/`profileStats`, que são públicos para os amigos;
qualquer alteração no formato do que já está gravado em `iter/{uid}/routes`.

**Nunca:** recalcular o passado a partir de uma taxa de hoje; deixar
`norouterule` gravável pelo cliente; somar a Sem Rota dentro de uma média cujo
denominador não a conta.

## Decidido pelo caminho

**1. O líquido no `value`, o bruto no bloco.** Guardar só o bruto obrigaria dez
agregados a conhecer a regra; guardar só o líquido tornaria a edição impossível.
Os dois, com uma invariante testada ligando um ao outro.

**2. Duas réguas, não uma.** `realized` continua sendo `concluido + pago` e não
foi tocada. Toda a análise — bairro, insucesso, ritmo, ranking — herda a
exclusão de graça, e nenhum comportamento antigo muda de valor.

**3. Sem regra é erro, não default.** A escolha entre 100% e 0% é uma escolha
entre mentir para mais e apagar a gasolina. A terceira opção é dizer que falta
cadastrar.

**4. Percentual congelado, como a provisão.** Mesma regra, mesma tabela, mesmo
motivo. A única diferença é que trocar de empresa recarrega — porque aí o
percentual antigo não descreve mais nada.

**5. `write: if false` desde o primeiro dia.** É a primeira coleção de
configuração de negócio do app. Aberta, uma linha de script muda o pagamento de
todos os usuários.

## Dívidas e fora de escopo

- **Rota que paga 0%.** Um dia uma empresa pode não pagar nada por uma ida
  perdida. Hoje isso é indistinguível de documento quebrado, e uma rota de
  R$ 0,00 perde a provisão junto (`provisionFor` desiste em `value <= 0`). É
  uma limitação que já existe para rotas normais de valor zero.
- **Shopee.** Falta o dado. É uma linha no console quando ele existir.
- **Percentual por região ou por praça.** Se um dia o percentual variar dentro
  da mesma empresa, o id do documento deixa de bastar. O bloco congelado na
  rota continua valendo do mesmo jeito.
- **Histórico do percentual.** Não há: o console sobrescreve. Como cada rota
  carrega o seu, o histórico efetivo está nas rotas.
- **`paymentRules`.** Coleção existente, sem uso e sem regra. Fica como está.
- **App Check.** Segue pendente e segue sendo o item que `amigos.md` marca como
  "antes de o app sair do seu celular". `norouterule` não piora isso — é só
  leitura.

## Perguntas em aberto

Nenhuma bloqueante. As quatro que existiam — o que fazer sem regra, se conta
como rota, como aparece na barra, e se o percentual congela — foram respondidas
antes desta spec.

---

# Correções depois da varredura

Oito agentes varreram lib/, test/, `firestore.rules` e `firestore-tests/` atrás de
tudo que o quinto valor de `StatusRoute` toca: 312 pontos, 95 deles capazes de
falhar **sem erro de compilação e sem teste vermelho**. O que segue manda sobre
o corpo da spec.

## As três regras "rodou" escritas em lugares diferentes

`done = concluido || pago` existe **três vezes**:

| onde | o que faz |
|---|---|
| `vehicleCost.dart:167` (`resolveProvision`) | a regra de verdade |
| `addIter.dart:938` (`_withProvision`) | **roda primeiro** e curto-circuita |
| `routeCard.dart:240` (`_profitBlock`) | só decide a dica "Informe o KM" |

Corrigir apenas a primeira não produz efeito nenhum: `_withProvision` intercepta
antes e devolve `withProvision(null)`. O teste unitário de `resolveProvision`
fica verde, e **o app não provisiona uma Sem Rota sequer** — o KM até o CD nunca
vira gasolina. `_withProvision` é método privado de tela: zero testes.

## O vazio que engole a feature

Três telas decidem "não há nada para mostrar" por uma contagem que passa a
excluir a Sem Rota. Num mês só de idas ao CD — que é o mês fraco, o caso
provável — cada uma esconde o dinheiro que a feature existe para registrar:

| onde | condição | o que aparece hoje |
|---|---|---|
| `summaryScreen.dart:133` | `total.isEmpty` (`routes == 0`) | "Nenhuma rota entre 01/08 e 31/08" — a aba inteira |
| `companySummaryCard.dart:51` | idem, por empresa | "Sem rotas no período" escondendo valor, lucro, KM e custo por km |
| `graficsScreen.dart:234` | `total: summary.received` ≤ 0 | "Nada foi pago neste período ainda", com PAGO em R$ 0,00 |
| `summaryCards.dart:169` | `summary.count == 0` | "Sem rotas no período." embaixo de uma barra com dinheiro |

Então:

- `CompanySummary.isEmpty` vira `routes == 0 && noRouteCount == 0`.
- O card "Pago no período" usa **`receivedTotal`** como `total`, não `received`.
  Sem isso há um segundo defeito: as fatias vêm de `receivedPayment` (que passa a
  incluir a Sem Rota) e o denominador não, então as porcentagens da legenda somam
  mais de 100% e os `flex` da barra distorcem.
- `DeliveryRateBar` ganha a terceira frase: sem rota nenhuma e sem ida, "Sem
  rotas no período."; só idas, "Só idas sem rota no período."; senão, a de
  sempre.

## O arredondamento, e por que o teste-âncora da spec não testava nada

`249,90 × 40%` em IEEE754: `249.9 * (40/100)` dá `99.96000000000001`, mas
`249.9 * 40 / 100` dá `99.96` **exato**. Ou seja, o critério que o corpo da spec
escolheu passaria por sorte, sem arredondamento nenhum — e o defeito apareceria
em `1.234,56 × 40% = 493.82399999999996`.

E `(x * 100).round() / 100` erra o meio centavo: `87,45 × 30% = 26,235` cai
exatamente no meio, e `1.005 * 100` vira `100.49999999999999`, então a direção do
arredondamento passa a ser decidida por ruído de float.

A conta é feita em **centavos inteiros**, sem float no meio:

```dart
final grossCents = (grossValue * 100).round();
final paidCents  = (grossCents * percent + 50) ~/ 100;   // meio para cima
return paidCents / 100;
```

Os testes comparam com **igualdade exata**, nunca `closeTo`: `toStringAsFixed(2)`
esconde o double sujo na tela, no card e no gráfico, então a verificação no
aparelho não consegue detectar a falta do arredondamento. Só o teste consegue.
Casos obrigatórios: `250,00×40 = 100,00`, `249,90×40 = 99,96`,
`87,45×30 = 26,24` (o meio centavo), `1.234,56×40 = 493,82`, `250,00×100 = 250,00`.

## "Sem regra" e "sem sinal" não podem virar a mesma frase

`fetchPercent(Company) -> int?` faz exatamente o que a spec condena nas suas
próprias linhas sobre a Shopee: a primeira leitura de `norouterule` num aparelho
**nunca** vem do cache, então offline o `get()` volta `unavailable` — e com
`int?` isso é o mesmo `null` de "documento não existe". O entregador sem sinal
seria mandado abrir o console para cadastrar uma regra que já está lá.

Então o controller **devolve `int?` para encontrado/ausente e lança para falha de
leitura**, como `VehicleController.fetchActive` já faz. A tela tem quatro
estados, com quatro frases:

| estado | frase | salva? |
|---|---|---|
| carregando | "Buscando a regra de pagamento…" | não |
| encontrada | "Sem rota: a Amazon paga 100% → R$ 250,00" | sim |
| ausente | "Sem regra de pagamento cadastrada para a Shopee." | não |
| falhou | "Não foi possível ler a regra de pagamento. Tente de novo." | não |

E o guarda do save é **"`resolveNoRoutePayment` devolveu `null`"**, não "não tem
percentual": editar uma rota de junho chega ao formulário sem regra carregada, e
o bloco congelado já responde a pergunta — recusar ali tornaria impossível
corrigir uma rota antiga.

## As quatro cópias da lista de status em `addIter.dart`

Nenhuma delas é `switch` sobre enum, então **o compilador não cobra nenhuma**:

| linha | o que é | o que acontece se esquecer |
|---|---|---|
| 503 | `selectedItemBuilder`, lista const de 4 strings | debug: assert; **release: desenha o ícone do status anterior** |
| 513 | `items`, 4 `DropdownMenuItem` | o status existe no enum e não aparece no menu |
| 181 | `_getStatusIcon`, switch sobre String com `default` | interrogação cinza |
| 238 | `_getButtonName`, idem | botão escrito "Desconhecido Rota" |
| 862 | encadeado ternário da cor, **com aspas duplas** | botão cinza; um grep com aspas simples não acha esta cópia |

As duas primeiras são cruzadas **por índice** pelo Flutter. Todas passam a sair
de `StatusRoute.values`.

E há uma quinta cópia que a spec não citava: a empresa é escolhida em **três
`GestureDetector` separados** (`addIter.dart:292`, `:313`, `:337`). Instrumentar
dois e esquecer um deixa o percentual da empresa anterior na tela **e no
documento gravado**. Os três passam a chamar um `_selectCompany(int)` único —
sem mexer no visual, que tem padding e altura diferentes por logo.

## Outras que entram

- **A linha ao vivo fica um caractere atrás.** `valueController` não tem listener
  e nada chama `setState` enquanto se digita: o usuário vê R$ 25,00 tendo
  digitado 250. Vai por `onChanged` do `TextFormField` e não `addListener` —
  esta `State` não tem `dispose()`, e os oito controllers já vazam.
- **A contagem de filhos da `Column` do formulário.** Um `if` que acrescenta ou
  remove um filho desloca todos os irmãos abaixo e o `TextFormField` recriado
  perde o foco e a mensagem de validação. O widget é emitido **sempre**,
  devolvendo `SizedBox.shrink()` fora da Sem Rota.
- **`semRota` vai no FIM do enum.** `valueByStatus` itera `StatusRoute.values`,
  e a barra do Resumo é lida como esteira: inserir no meio reordena um gráfico de
  outra tela sem nenhum sinal aqui.
- **Os campos novos entram como `required`.** Dar default deixa a suíte verde sem
  que nenhum teste conheça a Sem Rota; o erro de compilação em
  `summaryCards_test.dart:24` e `companySummaryCard_test.dart:21/:174` é o sinal
  barato que obriga a olhar.
- **A quinta fatia só aparece quando há dinheiro nela.** `MoneyBreakdownCard`
  filtra `slice.value > 0`, então um teste que só acrescente o status ao enum
  continua desenhando quatro chips e continua verde. O caso de layout precisa de
  `noRoute > 0`.
- **`realizedTotal` passa a ser `receivedTotal + pending`** e `receivedRate` a
  usar `receivedTotal` nos dois lados. A spec não tinha decidido; deixar o
  numerador sem a Sem Rota e o denominador com ela faria a taxa de recebimento
  **cair** a cada ida registrada.
- **`NoRoutePayment.fromMap` nasce defensivo** (`readDouble`/`readInt` + guarda
  `is Map`). `NewRouteModal.fromMap:196` lê `value` com cast cru e é a exceção da
  casa: um número redondo volta do Firestore como `int`, o cast lança, e o
  try/catch por documento de `RouteController._parseAll` faz a rota **sumir da
  lista sem log**.
- **Nada de alargar `final done = realized(all)`** em `companySummary`. Todo o
  corpo itera essa lista, e a Sem Rota entraria em `routesPerBairro`, `packages`,
  `stops` e `failures` — o formulário continua tendo campo de bairro, e uma rota
  editada de `concluido` para `semRota` **mantém** pacotes e insucesso gravados.
  A soma é num acumulador separado.
- **`gross > 0` é guarda explícita no save.** `parseMoneyToDouble` devolve `0.0`
  para vazio e para lixo, nunca `null` — e valor 0 encadeia em líquido 0, que faz
  `provisionFor` desistir em `value <= 0` e some com a gasolina da ida.

## Testes de regra: três jeitos de escrever um teste que não testa

1. **`assertSucceeds(getDoc(...))` fica verde sem o documento existir** — um `get`
   autorizado sobre documento inexistente devolve snapshot com `exists() ==
   false`, não erro. O caso "autenticado lê" passa mesmo se o seed for esquecido.
   Tem de **afirmar o valor**: `assert.equal(snap.data().percent, 40)`.
2. **`assertFails` só aceita `permission-denied`.** `updateDoc` sobre id nunca
   semeado volta `not-found` e o teste quebra pelo motivo errado. Os três casos
   de escrita rodam contra o **mesmo id semeado**.
3. **`seed()` começa com `clearFirestore()`.** Semear `norouterule` antes de
   chamá-lo apaga o seed em silêncio — e aí o item 1 entra por cima e o teste
   continua verde. Ordem: `await seed()` e só então `withSecurityRulesDisabled`.

Mais duas: **não existe um único teste anônimo no arquivo hoje**
(`env.unauthenticatedContext()` tem zero ocorrências), e escrever "anônimo não
lê" como `authenticatedContext('qualquer')` testaria a asserção errada, porque
`request.auth != null` é satisfeito por qualquer uid. E os quatro casos entram em
`rules.test.mjs`, **não em arquivo novo**: `node --test` roda arquivos em
paralelo e dois `clearFirestore()` contra o mesmo emulador apagariam o seed um do
outro, em falha intermitente.

## Deploy: o comando da spec vai para o projeto errado

Não existe `.firebaserc` na raiz e `firebase.json` não tem bloco de projeto.
`run.sh` compensa com `--project iter-mn` explícito; o comando de deploy não. Sem
ele, o destino é o que o `firebase use` global apontar por último — e o sintoma é
`norouterule` continuar negada em `iter-mn`, indistinguível de regra não escrita.

```bash
firebase deploy --only firestore:rules --project iter-mn
```

E é este o comando que a **tarefa 10** repete — não a versão sem `--project`,
que estava escrita no primeiro rascunho desta spec e foi corrigida depois de a
revisão apontar que a última linha do arquivo contradizia esta seção.

E **a regra deployada não cria dado nenhum**. Enquanto
`norouterule/mercadolivre {percent: 40}` e `norouterule/amazon {percent: 100}`
não forem digitados no console, toda empresa se comporta como a Shopee — com
`npm test` verde e `flutter test` verde. É o único passo da entrega que nenhum
teste acusa.

## Desvios decididos durante a implementação

Quatro, todos registrados aqui em vez de descobertos depois no diff:

**1. A conta é `NoRoutePayment.paidValue`, estática, e não uma função solta em
`Utils/noRouteRule.dart`.** O bloco mora em `newRouteModal.dart` (o precedente de
`RouteProvision`), então a função em `Utils` criaria import circular. Uma
implementação só é inegociável — a invariante `value == paid` é igualdade exata
de `double` —, e a estática ao lado do getter garante isso sem o ciclo.
`Utils/noRouteRule.dart` ficou com `readPercent` e `resolveNoRoutePayment`.

**2. `AddIter` passou a receber `uid` em vez do `User` do FirebaseAuth**, mais um
`ruleLoader` injetável — o formato que `AddSupply` já usa. Só o `uid` era lido
(quatro chamadas), e um `User` é classe abstrata com dezenas de membros: exigi-lo
tornava a tela impossível de pumpar. Junto saiu um `final firestore =
FirestoreService.instance` **morto** no `_AddIterState`, que tocava o Firebase no
construtor e derrubava qualquer teste antes do primeiro frame. É por isso que a
tela que carrega a armadilha mais cara da feature não tinha um teste sequer —
agora tem 14.

**3. O rótulo "Rotas" do card de resumo virou "Ganhos".** Aquele número agora
soma dinheiro que não veio de rota nenhuma; manter o rótulo era descrever errado
o valor ao lado dele.

**4. `DeliveryRateBar` ganhou uma terceira frase**, "Só idas sem rota no
período." Um período de `count == 0` com dinheiro na barra logo acima diria "Sem
rotas no período" — que pareceria defeito — ou "Preencha Pacotes", que é pedir o
impossível para uma ida que não carregou nenhum.

## Documentação que envelhece junto

Três specs passam a mentir e a tabela arquivo-a-arquivo só listava o `CLAUDE.md`:
`graficos.md:392` ("Pago no período | `pago`"), `resumo-por-empresa.md:56`
("Tudo sobre as rotas **realizadas**") e `lista-iter.md:56` (a enumeração dos
quatro status). Neste repositório comentário é argumento carregado, e o pior
formato de erro é o arquivo cuja linha 56 mente enquanto a 213 ainda diz a
verdade.

Também: `CLAUDE.md:248` afirma "30 cases" e `rules.test.mjs` tem **84** `it()`. O
número já estava errado; a entrega corrige em vez de aumentar a diferença. E o
comentário de `firestore.rules:72` ("a ÚNICA coleção compartilhada do app") já é
falso desde que `posts` e `reports` subiram — a `match` nova entra em seção
própria, longe dele, em vez de encostar a contraprova a duas linhas da frase.

---
# Tarefas

- [x] **1. `Utils/noRouteRule.dart` + `NoRoutePayment` — a conta, teste
      primeiro** — 35 testes em `test/unit/noRouteRule_test.dart`.
  - A conta virou `NoRoutePayment.paidValue`, **estática**, em centavos
    inteiros: `(grossCents * percent + 50) ~/ 100 / 100`. Ver o desvio 1.
  - O teste-âncora que a spec escolheu (`249,90 × 40%`) passa **sem
    arredondamento nenhum** — `249.9 * 40 / 100` dá 99,96 exato em IEEE754.
    Quem prova o arredondamento são `1.234,56 × 40% = 493,82` (que sem ele daria
    `493.82399999999996`) e `87,45 × 30% = 26,24` (o meio centavo).
  - Comparação **exata**, nunca `closeTo`: `toStringAsFixed(2)` esconde o double
    sujo na tela, no card e no gráfico, então a verificação no aparelho não
    consegue detectar a falta do arredondamento.
  - Verificar: `flutter test test/unit/noRouteRule_test.dart`

- [x] **2. `StatusRoute.semRota` no modelo e no estilo**
  - O valor entrou no **fim** do enum e quebrou os quatro `switch` de
    `routeStyle.dart` mais o de `summarize` na compilação — cinco no total, que
    é o ponto de eles serem exaustivos.
  - `noRoutePayment` entrou no construtor, `toMap`, `fromMap` **e
    `withProvision`**. Um teste afirma a preservação, porque ali os parâmetros
    são opcionais e omitir o campo não gera erro.
  - Nasceu junto `NewRouteModal.hasRun` — ver tarefa 4.
  - Verificar: `flutter analyze`

- [x] **3. `routeStats.dart` — as duas réguas**
  - `noRouteTrips()` (o nome `noRoute` ficou para o campo de `PeriodSummary`);
    `receivedPayment` incluindo `semRota`; `realized` **sem uma linha alterada**.
  - `PeriodSummary` ganhou `routeTotal`, `noRoute`, `noRouteCount` e
    `receivedTotal`; `count` deixou de ser `routes.length`; `average` passou a
    dividir `routeTotal` por `count`; `receivedRate` usa `receivedTotal` nos
    **dois** lados.
  - Verificar: `flutter test test/unit/routeStats_test.dart`

- [x] **4. `companySummary.dart` + `vehicleCost.dart` — dinheiro e gasolina**
  - A regra "rodou" virou o getter `NewRouteModal.hasRun`, e não uma edição em
    `resolveProvision`: ela estava escrita em **três** arquivos, e a cópia de
    `addIter._withProvision` roda primeiro. Corrigir só `vehicleCost.dart`
    deixava toda Sem Rota salvando com `provision: null` — teste unitário verde,
    KM até o CD nunca virando gasolina.
  - `companySummary` soma numa **passada separada**, nunca ampliando `done`:
    todo o corpo daquele laço e o `routesPerBairro` iteram a mesma lista, e uma
    rota editada de `concluido` para `semRota` mantinha `adress`, `packages` e o
    insucesso gravados.
  - `isEmpty` passou a olhar as duas contagens — ver a tarefa 8.
  - Verificar: `flutter test test/unit/companySummary_test.dart
    test/unit/routeProvision_test.dart`

- [x] **5. `monthStats` e `profileStats` — provar que ficaram de fora**
  - Nenhuma linha de código mudou nos dois. Entraram dois testes afirmando que
    uma `semRota` de 40 minutos, 500 pacotes e 60 insucessos não mexe em
    `routes`, `minutesPerRoute`, `packages`, `failureRate` nem na carreira.
  - Eles existem para que "consertar" esses arquivos para usar `receivedPayment`
    fique vermelho aqui, e não errado na tela de **outra pessoa**.
  - Verificar: `flutter test test/unit/monthStats_test.dart
    test/unit/profileStats_test.dart`

- [x] **6. `firestore.rules` + testes de regra** — 6 casos novos, 90 no total.
  - `match /norouterule/{company}` com `get` / `list: false` / `write: false`,
    em seção própria e longe do comentário de `gastop`, que foi corrigido: ele
    afirmava ser "a ÚNICA coleção compartilhada do app" desde antes de `posts` e
    `reports` existirem.
  - Os testes afirmam o **valor** (`percent == 40`), não só que o `get` passou:
    um `get` autorizado sobre documento inexistente devolve `exists() == false`,
    não erro, e o caso passaria com o seed esquecido.
  - Primeiro teste anônimo do arquivo (`env.unauthenticatedContext()`), e os
    três casos de escrita rodam contra ids **semeados**, senão quebrariam por
    `not-found` em vez de `permission-denied`.
  - Verificar: `cd firestore-tests && npm test`

- [x] **7. `addIter.dart` — o formulário** — 22 testes de widget, numa tela que
      não tinha **nenhum**.
  - As quatro listas de status (duas do dropdown, o ícone e a cor do botão)
    saem de `StatusRoute.values` ou de `switch` exaustivo sobre o enum. O campo
    `status` deixou de ser `String`, o que eliminou o `firstWhere` sem `orElse`
    do salvamento.
  - Os três `GestureDetector` do seletor de empresa passaram por um
    `_selectCompany` único, com `_ruleRequest` descartando resposta atrasada.
  - Ver os desvios 2 e 4.
  - Verificar: `flutter test test/widget/addIter_test.dart`

- [x] **8. Cards — `routeCard`, `companySummaryCard`, `graficsScreen`**
  - `routeCard` ganhou a linha `Pagamento: 40% de R$ 250,00` e desenha o bloco
    de lucro para a Sem Rota.
  - `graficsScreen`: `PAGO` usa `receivedTotal`, a média usa `routeTotal`, e o
    rodapé "Inclui R$ X de N idas sem rota" só aparece quando há o que explicar.
  - `companySummaryCard`: rótulo "Ganhos" (desvio 3) e a linha da parcela.
  - Verificar: `flutter test test/widget/`

- [x] **9. Revisão adversarial** — 6 revisores + 8 céticos sobre o diff. Nenhum
      dos 8 achados de maior severidade sobreviveu à refutação; **sete achados
      menores foram consertados**, e um deles era grave:

  - **O caminho de salvamento não tinha um teste.** Um revisor trocou
    `payment?.paid ?? gross` por `gross` em `_saveRoute` — a quebra direta da
    invariante 1 — e os 871 testes continuaram verdes. `AddIter` ganhou um
    `saver` injetável e cinco testes que exercem o save de ponta a ponta;
    a mesma sabotagem agora derruba quatro deles.
  - **Trocar de `concluido` para `semRota` regravava pacotes, paradas, bairros e
    insucesso.** Os agregados estavam protegidos, mas o card exibia
    "Pacotes: 120" embaixo do chip "Sem Rota". Esses campos deixaram de ser
    gravados na Sem Rota.
  - **O estado "carregando" não tinha teste** e é o mais provável dos quatro:
    apagar aquele ramo do `switch` deixava a tela dizer "Sem regra cadastrada",
    em vermelho, para uma regra que existe e está a caminho.
  - `cadastro-veiculo.md` e `graficos.md` continuavam definindo a provisão como
    `concluido`/`pago` e a média como `total ÷ quantidade`.
  - O comando de deploy da tarefa 10 estava sem `--project iter-mn`.
  - O teste `inPeriod mantém todos os status` enumerava quatro.

  Fica registrado o que **não** foi consertado, e por quê:
  `NewRouteModal.fromMap` resolve o status com `firstWhere` sem `orElse`, então
  um build antigo que leia um documento `semRota` lança, e
  `RouteController._parseAll` descarta a rota em silêncio. Um `readEnum` com
  fallback seria pior — rotularia uma rota paga como agendada. O sintoma correto
  é a rota sumir da tela do aparelho desatualizado; os números públicos dos
  amigos não mudam, porque `realized()` já a excluiria.

- [ ] **10. Verificação no aparelho** — falta, e é sua.
  1. **Antes de tudo**, crie no console: `norouterule/mercadolivre {percent: 40}`
     e `norouterule/amazon {percent: 100}`. **A regra deployada não cria dado
     nenhum** — sem esses documentos, toda empresa se comporta como a Shopee,
     com `npm test` e `flutter test` verdes. É o único passo que nenhum teste
     acusa.
  2. `firebase deploy --only firestore:rules --project iter-mn` — **com** o
     `--project`: não existe `.firebaserc` na raiz, e sem ele o destino é o que
     o `firebase use` global apontar por último. O sintoma de errar é
     `norouterule` continuar negada, indistinguível de regra não escrita.
  3. Percorra os critérios de sucesso um a um, **trocando o `percent` do Mercado
     Livre para 30 no meio do caminho**. É o passo que prova o pilar: nenhuma
     rota já gravada pode mudar de valor.
  4. Olhe a legenda de cinco fatias na barra do Resumo num mês que tenha
     dinheiro de Sem Rota. Teste de widget não sabe se o texto cabe — a fonte de
     teste é quadrada, e quebra de linha não levanta exceção.
