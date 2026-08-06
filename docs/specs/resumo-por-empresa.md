# Spec: Resumo por Empresa

Status: **proposta** · Criada em 2026-08-05 · Aguardando aprovação

## Objetivo

Preencher a aba **Resumo** — hoje um `Center(child: Text('Resumo'))` — com um
card por empresa (Mercado Livre, Amazon, Shopee) mais um card de total geral,
respondendo de um olhar: *quanto entrou, quanto sobrou, quanto rodei e onde*.

É a tradução do bloco `V2:AA6` da planilha (ganhos, provisão e lucro por
plataforma), agora com KM, pacotes, paradas, insucessos e bairros — que a
planilha não tem.

Usuário: o entregador. Sucesso = ele abre a aba no fim do mês e sabe qual
empresa valeu mais a pena, sem abrir o Excel.

Esta tela é a primeira consumidora de `NewRouteModal.provision`, criada em
`cadastro-veiculo.md`. Sem ela, o lucro era um número que ficava guardado e
ninguém via somado.

## Layout

```
┌────────────────────────────────────────────┐
│  Início 01/08/2026  →  Fim 31/08/2026      │  ← PeriodFilter, fixo no topo
├────────────────────────────────────────────┤
│ ╔════════════════════════════════════════╗ │
│ ║  AGOSTO · 28 rotas                     ║ │  ← total geral, em destaque
│ ║  Rotas          R$ 4.120,00            ║ │
│ ║  Lucro          R$ 3.402,17            ║ │
│ ║  ⚠ R$ 812,50 ainda sem custo calculado ║ │
│ ║  1.284 km · 1.412 pacotes · 980 paradas║ │
│ ╚════════════════════════════════════════╝ │
│                                            │
│ ┌────────────────────────────────────────┐ │
│ │ [logo] Mercado Livre        12 rotas   │ │
│ │ Rotas                     R$ 1.510,00  │ │
│ │ Lucro                     R$ 1.446,24  │ │
│ │ ⚠ R$ 812,50 ainda sem custo calculado  │ │
│ │ ──────────────────────────────────────  │ │
│ │  428,5 km      512 pacotes   390 paradas│ │
│ │  12 insucessos (2,3%)      R$ 0,82/km  │ │
│ │ ──────────────────────────────────────  │ │
│ │  Mais rodado    Aldeota                │ │
│ │  Menos rodado   Messejana              │ │
│ └────────────────────────────────────────┘ │
│ ┌─ Amazon ───────────────────────────────┐ │
│ ┌─ Shopee ──── sem rotas no período ─────┐ │  ← aparece zerada
└────────────────────────────────────────────┘
```

## Os números, um a um

Tudo sobre as rotas **realizadas** (`concluido` + `pago`) dentro do período —
`realized(inPeriod(...))`, o mesmo recorte que os gráficos usam. Rota agendada
não entregou pacote, não rodou quilômetro e não passou por bairro nenhum.

| campo | conta | `null` quando |
|---|---|---|
| Rotas | contagem | nunca (zero é zero) |
| Valor | `Σ value` | nunca |
| **Lucro** | `Σ (route.profit ?? route.value)` | nunca |
| **Sem custo** | `Σ value` das rotas **sem** provisão | é zero → some da tela |
| KM | `Σ (kmFinal − kmInitial)` das que informaram | nenhuma informou |
| Pacotes | `Σ packages` das que informaram | nenhuma informou |
| Paradas | `Σ stops` das que informaram | nenhuma informou |
| Insucessos | `Σ failuresOf(route)` | nunca — zero é informação |
| Taxa de insucesso | `insucessos ÷ pacotes × 100` | sem pacotes informados |
| Custo por km | `Σ provision.total ÷ Σ provision.km` | nenhuma rota com provisão |
| Mais / menos rodado | `routesPerBairro().first` e `.last` | nenhuma rota com bairro |

### O Lucro e a ressalva

A conta é a que você pediu: **lucro real das rotas calculadas + valor bruto das
que ainda não têm cálculo**. Nenhuma rota fica de fora do total.

Mas esse número, sozinho, engana de dois jeitos, e por isso ele vem sempre com
uma linha embaixo dizendo **quanto dele ainda é bruto**:

1. Hoje nenhuma rota tem provisão, então "Lucro" sairia **idêntico** a "Rotas"
   nos três cards — dois números iguais parecem tela quebrada.
2. Conforme as rotas ganharem provisão, o Lucro vai **cair**. Sem a ressalva,
   pareceria que o entregador passou a lucrar menos, quando ele só passou a
   medir certo.

A linha some sozinha quando `uncalculatedValue` chega a zero — no dia em que
toda rota do período tiver custo calculado, o card fica limpo, e isso vira o
sinal de que o número está inteiro.

### Custo por km

Só das rotas **com** provisão: `Σ provision.total ÷ Σ provision.km`. Misturar as
sem provisão jogaria KM no divisor sem jogar custo no dividendo, e o resultado
seria um custo por km artificialmente baixo — o tipo de número que só está
errado para menos, que é o lado que engana.

### Menos rodado

`routesPerBairro` já devolve ordenado do maior para o menor, com empate pelo
nome. "Menos rodado" é o último da lista, não o bairro com zero rotas — bairro
onde ele nunca foi não é "pouco rodado", é ausente.

Com **um** bairro só, mais e menos rodado seriam o mesmo, e a tela mostra apenas
"Mais rodado". Repetir o mesmo nome em duas linhas com rótulos opostos parece
defeito.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1. **Nenhuma dependência nova.** `setState` +
`StreamBuilder`, como no resto do app.

Reusa o que já existe em vez de recopiar: `realized`, `inPeriod`, `failuresOf`,
`routesPerBairro` e `RankEntry` de `Utils/routeStats.dart`; `PeriodFilter` e o
`PeriodFilter.currentMonth()` da tela de gráficos; `companyLogo`,
`companyLabel` e `companyColor` de `Utils/routeStyle.dart`;
`CurrencyFormatterHelper.formatMoney`.

## Comandos

```bash
flutter analyze lib/ test/                       # sem error/warning novo
flutter test test/unit/companySummary_test.dart
flutter test test/widget/companySummaryCard_test.dart
flutter test                                     # widget_test.dart segue quebrado (template)
flutter run
```

## Estrutura

```
lib/Utils/companySummary.dart              → as contas, puras (novo)
lib/widget/companySummaryCard.dart         → o card (novo)
lib/screens/summaryScreen.dart             → a aba, hoje um stub
lib/screens/home.dart                      → passar o `user` para a aba
test/unit/companySummary_test.dart         → (novo)
test/widget/companySummaryCard_test.dart   → (novo)
```

`companySummary.dart` separado de `routeStats.dart` pelo mesmo critério que
separou `profileStats.dart`: aquele arquivo devolve **rankings e séries** para
gráficos, este devolve **um objeto de resumo por recorte**. E separado de
`profileStats.dart` porque lá é carreira inteira sem filtro, aqui é um período e
uma empresa.

## Dados

Origem: `iter/{uid}/routes` via `RouteController.watchAll(uid)` — o mesmo stream
que a lista e os gráficos já usam. **Nada é escrito**: a tela é só leitura.

Nenhum campo novo no Firestore. `provision` já existe desde
`cadastro-veiculo.md`.

## Estilo de código

Uma classe de resultado e uma função pura que a monta numa passada, como
`PeriodSummary`/`summarize` e `ProfileStats`/`profileStats`:

```dart
/// Resumo de um recorte de rotas — uma empresa num período, ou todas.
///
/// `null` aqui significa **"não dá para calcular"**, nunca zero.
class CompanySummary {
  const CompanySummary({
    required this.routes,
    required this.value,
    required this.profit,
    required this.uncalculatedValue,
    ...
  });

  /// `Σ (route.profit ?? route.value)` — líquido onde há cálculo, bruto onde
  /// não há.
  final double profit;

  /// Quanto de [profit] ainda é bruto. Zero = o número está inteiro.
  final double uncalculatedValue;
  ...
}

/// Recebe a lista **já filtrada** por período e empresa.
CompanySummary companySummary(List<NewRouteModal> routes) { ... }
```

Função pura sobre `List<NewRouteModal>`, sem Firestore e sem `BuildContext`.
Texto em pt-BR. Arquivos em camelCase.

## Estados

1. **Carregando** — `CircularProgressIndicator`, com o `PeriodFilter` já visível
   (fora do `StreamBuilder`, como a `ListIterScreen` faz com o filtro de
   empresa).
2. **Erro ao ler as rotas** — a mesma mensagem com ícone das outras abas, e
   `debugPrint` sempre.
3. **Nenhuma rota no período** — uma linha "Nenhuma rota entre 01/08 e 31/08" e
   a dica de trocar o período. Mandar "cadastre a primeira rota" seria mentira
   para quem tem 200 rotas em julho. *(A spec pedia os cards zerados; na
   implementação virou a mensagem sozinha — quatro cards repetindo "sem rotas"
   é a mesma frase quatro vezes.)*
4. **Empresa sem rota no período** — card presente, com o cabeçalho e a linha
   "Sem rotas no período". A posição dos três cards não muda de um mês para o
   outro. *(A spec dizia "`—` nos campos"; na implementação virou só o rótulo —
   uma grade inteira de travessões é ruído para dizer o que uma linha já diz.)*
5. **Métrica incalculável** — `—`, nunca `0`. Vale para KM, pacotes, paradas,
   taxa, custo/km e bairros.
6. **Sem custo calculado** — a linha de ressalva no lucro; some quando zera.

## Estratégia de teste

`test/unit/companySummary_test.dart` (sem Firebase, sem widget):

- só `concluido` e `pago` entram; agendada e em andamento ficam fora;
- valor é a soma simples das realizadas;
- **lucro usa `profit` onde há provisão e `value` onde não há**, na mesma soma;
- `uncalculatedValue` é a soma só das sem provisão, e zera quando todas têm;
- lucro de rota com provisão bate com a planilha (152,50 · 46,9 km → 114,07);
- KM soma só as que informaram e é `null` quando nenhuma informou;
- KM negativo ou zero não entra (dado incompleto);
- pacotes e paradas são `null` quando ninguém informou, não zero;
- insucessos somam via `failuresOf` — switch desligado com quantidade gravada
  não conta;
- taxa de insucesso é `null` sem pacotes (sem divisão por zero);
- **custo por km ignora as rotas sem provisão nos dois lados da divisão**;
- custo por km é `null` quando nenhuma rota tem provisão;
- mais e menos rodado saem do ranking; com um bairro só, os dois são iguais;
- sem bairro nenhum, os dois são `null`;
- lista vazia devolve zeros e `null`s sem lançar.

`test/widget/companySummaryCard_test.dart`: monta o card com um `CompanySummary`
à mão e verifica os números formatados, o `—` das métricas nulas, a linha de
ressalva aparecendo e sumindo, o estado "sem rotas no período", e que "Menos
rodado" não aparece quando é igual ao mais rodado. Não toca em rede.

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; texto em pt-BR; conta em
  `Utils/companySummary.dart`, nunca dentro do `build`; reusar `routeStats.dart`
  em vez de recopiar; `null` para "não dá para calcular", nunca zero.
- **Perguntar antes:** qualquer dependência nova; mexer em `NewRouteModal`,
  `addIter.dart` ou no formato gravado; mudar `routeStats.dart`.
- **Nunca:** escrever, alterar ou apagar documento (a tela é read-only);
  recalcular provisão aqui — o valor gravado é o que vale; misturar rota sem
  provisão no divisor do custo por km.

## Critérios de sucesso

- [ ] A aba Resumo mostra o `PeriodFilter` abrindo no **mês corrente**.
- [ ] Um card de total geral no topo e três cards de empresa abaixo.
- [ ] Empresa sem rota no período aparece zerada, na mesma posição de sempre.
- [ ] Valor = soma das rotas concluídas e pagas do período.
- [ ] Lucro = líquido onde há provisão + bruto onde não há.
- [ ] A linha "⚠ R$ X ainda sem custo calculado" aparece quando há rota sem
      provisão e **some** quando todas têm.
- [ ] KM, pacotes, paradas e insucessos somados; taxa de insucesso em %.
- [ ] Custo por km só das rotas com provisão.
- [ ] Bairro mais e menos rodado; com um bairro só, mostra apenas o mais rodado.
- [ ] Métrica sem como ser calculada mostra `—`, nunca `0`.
- [ ] Trocar o período recalcula tudo sem reabrir a tela.
- [ ] `flutter analyze lib/` sem error/warning novo.
- [ ] Os testes novos passam e os 328 que já existem continuam passando.

## Decisões

**1. Lucro com ressalva, e não um número solto.** A conta é a pedida, mas hoje
ela sairia idêntica ao valor bruto, e cairia conforme as provisões fossem
calculadas. A linha de quanto ainda é bruto custa uma linha de tela e evita as
duas leituras erradas. Ela some sozinha quando o número fica inteiro.

**2. Custo por km só das rotas com provisão.** Incluir as outras jogaria KM no
divisor sem jogar custo no dividendo. Erraria sempre para menos — o lado que
engana.

**3. Empresa zerada continua na tela.** Card que some e volta faz a posição dos
outros dançar de um mês para o outro, e "Shopee: sem rotas" é informação, não
ausência de informação.

**4. Recorte de realizadas, como os gráficos.** Bairro rodado numa rota que não
saiu não é verdade, e pacote de rota agendada não foi entregue. É a mesma regra
que `routeStats.dart` já aplica.

**5. `companySummary.dart` separado.** `routeStats.dart` devolve rankings e
séries para gráficos; `profileStats.dart` é carreira inteira sem filtro. Este é
um objeto de resumo por recorte. O que dá para reusar é importado, não copiado.

**6. Nada é recalculado aqui.** A tela lê `provision` como está gravado. Somar
provisões congeladas é o único jeito de o resumo de julho continuar sendo o
resumo de julho — ver `cadastro-veiculo.md`, decisão 3.

## Dívidas e fora de escopo

- **Pendente x pago separados** (colunas `W` e `X` da planilha) — o card mostra
  o total das realizadas. Separar "já caiu" de "vai cair" é outra tela ou outra
  linha, e ninguém pediu ainda.
- **Comparação entre períodos** ("agosto x julho") — o número que responde "estou
  melhorando?". Fora de escopo aqui.
- **Despesas avulsas** (aba `Despesa` da planilha) — não têm tela nenhuma ainda,
  então não entram em lucro nenhum.
- **Toque no card levando à lista filtrada** por aquela empresa e período.
- **Coleção inteira baixada** — mesma dívida da lista e dos gráficos; esta tela
  reusa o mesmo stream, então não é leitura nova.

## Perguntas em aberto

Nenhuma bloqueante. Forma do lucro, período, card de total, empresa zerada, taxa
em % e custo por km foram respondidos antes desta spec.

---

# Plano de implementação

```
(1) Utils/companySummary.dart ──→ (2) widget/companySummaryCard.dart ──→ (3) summaryScreen + home
     teste primeiro                    teste de widget                      fiação
```

Três passos, e o primeiro carrega o risco: é onde moram a mistura de líquido com
bruto, a divisão por zero da taxa e do custo por km, e o `null` virando zero.

O passo 3 é pequeno — a `SummaryScreen` hoje é um stub, e a `home.dart` só
precisa passar o `user` que já tem.

## Riscos

| Risco | Mitigação |
|---|---|
| Lucro somando bruto sem ninguém perceber | `uncalculatedValue` é campo do resultado, com teste, e a tela é obrigada a mostrá-lo |
| Custo por km diluído por rota sem provisão | Teste dedicado: rota sem provisão não entra em nenhum dos dois lados |
| Divisão por zero em taxa e custo/km | `null` em todo divisor zero, com teste |
| `null` de pacotes/paradas virando zero | Coberto por teste antes de existir tela |
| Card zerado quebrando o layout | Estado 4 no teste de widget, com `CompanySummary` vazio |
| Bairro único aparecendo como mais **e** menos rodado | Teste de widget verifica que a segunda linha some |

Checkpoint depois de cada tarefa: `flutter analyze lib/` sem nada novo, mais o
teste da tarefa.

---

# Tarefas

- [x] **1. `Utils/companySummary.dart` — as contas, teste primeiro** — 27 testes.
  - `kmOf` veio de `vehicleCost.dart` em vez de refazer a subtração: é a mesma
    definição de "KM rodado" que a provisão e o card da rota já usam, com a
    guarda de diferença não positiva. Uma definição só, e o resumo nunca vai
    discordar do card sobre quanto a rota rodou.
  - `summaryByCompany` devolve **sempre as três** empresas, zeradas quando não
    houver rota — decidido no mapa e não na tela, para o card não precisar saber
    da regra.
  - Aceite: `CompanySummary` + `companySummary(List<NewRouteModal>)` cobrindo os
    onze campos, com todos os casos da "Estratégia de teste" escritos **antes**
    da implementação.
  - Verificar: `flutter test test/unit/companySummary_test.dart`
  - Arquivos: `lib/Utils/companySummary.dart`,
    `test/unit/companySummary_test.dart`

- [x] **2. `widget/companySummaryCard.dart` + teste de widget** — 14 testes.
  - `formatRate` saiu de `widget/partsEditor.dart` para `Utils/currencyFormat.dart`
    junto com um `formatNumber` novo: com três telas consumindo (editor de
    peças, card do veículo e este), formatador morando dentro de um widget
    obrigava a importar widget para formatar número. Os 369 testes seguem
    passando depois da mudança.
  - Um widget só serve empresa e total geral (`company: null`): mesma estrutura,
    outra roupa, para os números ficarem nas mesmas posições e o olho não ter de
    reaprender o layout entre um card e outro.
  - Aceite: cabeçalho com logo, nome e contagem; valor e lucro; linha de
    ressalva que aparece e some; grade de KM/pacotes/paradas/insucessos;
    custo/km; bairros; estado "sem rotas no período"; `—` no incalculável.
    Serve para o card de empresa **e** para o de total geral (que recebe
    `company: null`).
  - Verificar: `flutter test test/widget/companySummaryCard_test.dart`
  - Arquivos: `lib/widget/companySummaryCard.dart`,
    `test/widget/companySummaryCard_test.dart`

- [x] **3. `summaryScreen.dart` + `home.dart` — a fiação** — 7 testes.
  - **Bug meu, pego na revisão:** o rótulo do card de total usava
    `_end.difference(month.end).inDays == 0`, que também dá zero para **meio dia
    a menos** — 01/08 a 30/08 apareceria como "AGOSTO". As roletas de data
    devolvem horário junto, então virou comparação por dia, extraída para a
    função pura `periodLabel(start, end)` com teste. Data é onde eu acabei de
    escorregar; não podia ficar dentro de um getter privado de `State`.
  - `monthLabel()` entrou em `Utils/routeStyle.dart`, ao lado de
    `weekdayLabel` e `companyLabel` — é onde os rótulos do app moram.
  - Aceite: `PeriodFilter` no mês corrente e fora do `StreamBuilder`; stream de
    rotas criado uma vez em campo; total geral no topo e as três empresas
    abaixo; estados de carregando, erro e período vazio.
  - Verificar: `flutter analyze lib/` e `flutter test`
  - Arquivos: `lib/screens/summaryScreen.dart`, `lib/screens/home.dart`

- [ ] **4. Verificação no simulador**
  - Aceite: abrir a aba, conferir os números contra a lista, trocar o período e
    ver tudo recalcular.
  - Verificar: `flutter run`
