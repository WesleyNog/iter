# Spec: Tela de Gráficos

Status: **aprovada** · Criada em 2026-08-01 · Plano e tarefas no fim do arquivo

## Objetivo

Transformar `GraficsScreen` (hoje `Center(child: Text('Gráficos'))`, primeira aba
da `HomeScreen`) num painel que responde, para um período escolhido pelo
usuário, as sete perguntas abaixo — lendo as rotas de `iter/{uid}/routes`.

O layout é o da tela de gráficos do `meu_negocio`: cards com gradiente azul,
três `_infoCard` no topo de cada card, carrosséis de `PageView` com indicadores
de bolinha e filtro de período no topo da tela. **Só o layout vem de lá.** Todo
o dado é deste app.

| # | Pergunta | Onde aparece |
|---|---|---|
| 1 | Valor total de rotas no período | Card resumo (fixo, topo) |
| 2 | Ranking por empresa, em valor **e** em quantidade | Carrossel Empresas, pág. 1 e 2 |
| 3 | Ranking de insucesso por empresa (quantidade) | Carrossel Empresas, pág. 3 |
| 7 | Empresa com maior **índice** de insucesso (%) | Carrossel Empresas, pág. 4 |
| 5 | Bairros mais rodados | Carrossel Bairros, pág. 1 |
| 6 | Bairros com mais insucesso | Carrossel Bairros, pág. 2 |
| 4 | Valor por dia da semana e por faixa de horário | Carrossel Tempo, pág. 1 e 2 |

Usuário: o entregador. Sucesso = ele escolhe um mês e entende, sem abrir rota
nenhuma, quanto fez, com qual empresa vale mais a pena rodar, onde está perdendo
entrega e em que dia/horário costuma faturar mais.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1 · cloud_firestore 6.7.1 · firebase_auth 6.5.6 ·
**fl_chart 1.2.0 (dependência nova, aprovada)** — resolve limpo no
`pubspec.lock` atual, trazendo junto `equatable 2.1.0`.

Sem pacote de gerência de estado: `StreamBuilder` + `setState`, como no resto
do app.

## Comandos

```bash
flutter pub add fl_chart                 # uma vez, no início
flutter pub get
flutter run                              # simulador iOS já em uso
flutter analyze lib/                     # precisa ficar sem error/warning novo
flutter test test/unit/routeStats_test.dart
flutter test test/widget/barRankChart_test.dart
flutter test                             # widget_test.dart segue quebrado (template)
```

## Estrutura

```
lib/Utils/routeStats.dart          → filtros e agregações puras (novo)
lib/widget/chartCard.dart          → moldura gradiente + título + infoCards (novo)
lib/widget/barRankChart.dart       → gráfico de barras top-4 (novo)
lib/widget/lineChartCard.dart      → gráfico de linha fl_chart (novo)
lib/widget/periodFilter.dart       → seletor de início/fim (novo)
                                     desde 2026-08-22 ele não é mais o
                                     cabeçalho da tela: virou filho do
                                     periodPresetFilter, que oferece Este Mês,
                                     Mês Anterior, Esta Semana, Semana Anterior
                                     e Personalizado, e só mostra as duas
                                     roletas no último. Ver filtros.md
lib/widget/chartCarousel.dart      → PageView + indicadores de bolinha (novo)
lib/screens/graficsScreen.dart     → a tela (hoje stub)
lib/screens/home.dart              → passa o User para GraficsScreen (1 linha)
lib/Utils/routeStyle.dart          → + companyColor e weekdayFullLabel
lib/widget/dataPicker.dart         → + minimumDate/maximumDate (opcionais)
test/unit/routeStats_test.dart     → agregações (novo)
test/widget/barRankChart_test.dart → card de barras (novo)
test/widget/lineChartCard_test.dart → linha + carrossel, na altura real (novo)
```

A separação é a resposta direta ao "eu criei na mão e fiz do jeito que achava
mais fácil": na referência, os seis gráficos são seis métodos de ~200 linhas
que repetem a mesma moldura, e a matemática mora dentro do `build`. Aqui:

- **Toda conta vai para `Utils/routeStats.dart`**, em funções puras sobre
  `List<NewRouteModal>`. Testável sem Firebase, sem `BuildContext`, sem widget.
- **A moldura vira widget**: `ChartCard` (gradiente + título + linha de
  `_infoCard`) é escrita uma vez e usada por todos os cards.
- **O gráfico de barras vira widget**: `BarRankChart` recebe uma lista de
  `RankEntry` e um formatador. Os seis rankings são a mesma barra com dados
  diferentes.

O `build` da tela fica sendo composição, não cálculo.

## Dados

Origem: `iter/{uid}/routes/{routeId}` via `RouteController.watchAll(uid)` — o
mesmo stream da lista, nenhuma consulta nova. Campos usados:

| campo | tipo | uso |
|---|---|---|
| `startAt` | `DateTime` | filtro de período, dia da semana, faixa horária |
| `status` | enum | recorte "realizadas" (ver Decisão 1) |
| `value` | double | total, ranking por valor, séries de linha |
| `company` | enum | rankings por empresa |
| `adress` | `List<String>?` | rankings por bairro |
| `insucessoQnt` | `int?` | insucessos (quando `isInsucesso == true`) |
| `packages` | `int?` | denominador do índice de insucesso |

`startAt` é a data de referência de tudo — e não `dateRoute`, que é string
`dd/MM/yyyy` e já obrigou a lista a ordenar em memória. `NewRouteModal._readStart`
reconstrói `startAt` para os documentos antigos, então o filtro funciona para
rota gravada antes desse campo existir.

Nada é escrito. A tela é somente leitura.

## Estilo de código

Agregação como função pura de topo, no `Utils` (o padrão de `routeTime.dart`):

```dart
/// Um degrau de ranking: rótulo já legível e o número que ordena a barra.
class RankEntry {
  const RankEntry(this.label, this.value);
  final String label;
  final double value;
}

/// Soma o valor das rotas por empresa, da maior para a menor.
List<RankEntry> valuePerCompany(List<NewRouteModal> routes) {
  final totals = <Company, double>{};
  for (final route in routes) {
    totals.update(route.company, (v) => v + route.value, ifAbsent: () => route.value);
  }

  return totals.entries
      .map((e) => RankEntry(companyLabel(e.key), e.value))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
}
```

Regras que valem para o arquivo inteiro: recebe `List<NewRouteModal>` já
filtrada, nunca busca nada; devolve lista ordenada, nunca `Map` (a ordem é o
produto); `DateTime` de referência entra por parâmetro opcional onde "hoje"
importa, para o teste não depender do relógio — igual a
`RouteController.sortByDate`.

Stream criado uma única vez em campo `late final`, nunca dentro do `build`.
Texto de interface em pt-BR. Nomes de arquivo em camelCase.

## Como cada número é calculado

**Recorte base.** Duas faixas, ver Decisão 8. Os cards de dinheiro do topo
usam as rotas com `startAt` dentro do período (comparando só a data, início e
fim inclusive), **em qualquer status**. Os gráficos de análise usam esse mesmo
período restrito a `concluido` ou `pago`.

**1. Total do período.** `Σ value`. O card resumo mostra também a quantidade de
rotas e a média por rota (`routeTotal ÷ count` — **não** `total ÷ quantidade`:
desde `sem-rota.md` o total inclui as idas sem rota e a contagem não, e dividir
um pelo outro cruzaria populações, sempre para mais), além de uma barra de proporção
por empresa com a legenda `Empresa (xx%) · R$ y`, no lugar da barra de métodos
de pagamento da referência. Onde a referência mostrava "Meta atingida", aqui vai
**taxa de entrega**: `(Σ packages − Σ insucessos) ÷ Σ packages`, considerando só
rotas com `packages` preenchido.

**2. Ranking por empresa.** Duas páginas: `Σ value` por empresa e contagem de
rotas por empresa.

**3. Insucesso por empresa (quantidade).** `Σ insucessoQnt` por empresa,
contando só rotas com `isInsucesso == true`; `insucessoQnt` nulo nessas conta
como 1, que é o mínimo que o formulário permite.

**7. Índice de insucesso por empresa (%).** `Σ insucessos ÷ Σ packages × 100`,
usando **apenas rotas com `packages` preenchido e maior que zero**. Empresa sem
nenhuma rota com pacotes informados fica fora do ranking — não entra como 0%,
que seria mentira. O card avisa em rodapé: "considera só rotas com pacotes
informados".

**5. Bairros mais rodados.** Cada bairro de `adress` conta 1 por rota em que
aparece. Rota sem bairro não entra.

**6. Bairros com mais insucesso.** Usa a distribuição que o usuário informou no
`addIter` e rateia só o restante entre os bairros da rota (ver
`docs/specs/insucesso-por-bairro.md`). Rota sem distribuição — todas as
gravadas antes daquela entrega — continua inteiramente rateada: 3 insucessos
numa rota de 3 bairros dá 1,0 para cada. Em qualquer combinação o total do
ranking bate com o total real de insucessos do período. Valores fracionados
aparecem com uma casa decimal.

**4a. Por dia da semana.** `Σ value` agrupado por `startAt.weekday`, sempre com
os 7 pontos (Seg→Dom), inclusive os zerados — buraco no gráfico de linha lê
pior que um vale.

**4b. Por faixa de horário.** `Σ value` agrupado pela **hora de início**
(`startAt.hour`), dentro do turno escolhido num dropdown. Quatro turnos, que
juntos cobrem as 24 horas sem sobra:

| Turno | Horas |
|---|---|
| Madrugada | 00–04 |
| Manhã | 05–11 |
| Tarde | 12–17 |
| Noite | 18–23 |

São quatro, e não os três da referência, porque rota de entrega começa antes das
6h e nenhuma hora pode ficar sem turno — senão some rota do gráfico sem aviso.
Padrão ao abrir: Manhã.

## Layout

```
┌─ Filtro: [Início ▾]            [Fim ▾] ──────────────┐
│                                                       │
│ ┌─ RESUMO DO PERÍODO ────────────────────────────┐   │
│ │  TOTAL         ROTAS         MÉDIA/ROTA         │   │  ← fixo
│ │  ▓▓▓▓▓▓▓▓░░░░░░░░  (proporção por empresa)      │   │
│ │  ● ML (62%) R$ x  ● Amazon (25%) …              │   │
│ │  Taxa de entrega: ▓▓▓▓▓▓▓▓▓░ 97%                │   │
│ └────────────────────────────────────────────────┘   │
│                                                       │
│ ── Insucessos das rotas concluídas e pagas ──────     │
│ ┌─ INSUCESSOS ───────────────────────────────────┐   │
│ │  (3 págs de barras + 1 card de índice)          │   │  ← PageView, 4 págs
│ └────────────────────────────────────────────────┘   │
│                  ● ○ ○ ○                              │
│ ── Análise das rotas concluídas e pagas ─────────     │
│ ┌─ EMPRESAS ─────────────────────────────────────┐   │
│ │  (barras top-4)                                 │   │  ← PageView, 2 págs
│ └────────────────────────────────────────────────┘   │
│                    ● ○                                │
│ ┌─ BAIRROS ──────────────────────────────────────┐   │
│ │  (barras top-4)                                 │   │  ← página única
│ └────────────────────────────────────────────────┘   │
│                   (sem bolinha)                       │
│ ┌─ TEMPO ────────────────────────────[Manhã ▾]───┐   │
│ │  (linha fl_chart)                               │   │  ← PageView, 2 págs
│ └────────────────────────────────────────────────┘   │
│                    ● ○                                │
└───────────────────────────────────────────────────────┘
```

Carrosséis separados em vez de um único gigante: uma fileira longa de bolinhas
vira um ponto onde o usuário perde a conta de onde está, e o agrupamento já diz
o que esperar antes de arrastar.

O carrossel de **Insucessos** é a exceção deliberada a esse agrupamento por eixo
(empresa / bairro / tempo): ele agrupa por **assunto**, juntando os recortes de
insucesso que antes moravam dentro de Empresas e de Bairros. Quem roda as rotas
acompanha insucesso como um tema só, e comparar "onde" com "em que tempo" exigia
arrastar dois carrosséis e decorar o número do primeiro. Ver
`docs/specs/insucessos-carrossel.md`.

`ChartCarousel` esconde as bolinhas quando há uma página só — é o caso de
Bairros depois que o insucesso saiu dele, e uma bolinha sozinha promete uma
página que não existe.

Cada carrossel tem altura fixa e seu próprio `PageController` (`dispose` em
todos). Cores das barras: a mesma paleta de quatro tons da referência
(`greenAccent.200`, `cyanAccent.100`, `amber.100`, `redAccent.100`), ciclando
por índice. Gradiente dos cards: `0xFF0D47A1 → 0xFF1976D2 → 0xFF42A5F5`.

Valores em R$ usam `CurrencyFormatterHelper.formatDoubleToMoney`, que já existe
— com o cuidado que o `RouteCard` documenta: ela devolve string vazia para zero,
então zero precisa virar `'R$ 0,00'` na mão.

O `Scaffold` da `HomeScreen` tem `AppBar` sólida e `GlassNavBar` embaixo, então
o padding da referência (`MediaQuery.padding.top + 8` no topo, 110 na base) não
se aplica: aqui é `EdgeInsets.fromLTRB(16, 16, 16, 24)`, como na lista.

## Estados da tela

1. **Carregando** — `CircularProgressIndicator` centralizado.
2. **Erro** — mensagem amigável; em `kDebugMode`, o erro real; sempre
   `debugPrint`. Mesmo tratamento da `ListIterScreen`.
3. **Sem rota nenhuma** — ícone + "Nenhuma rota cadastrada ainda" + dica do
   botão `+`.
4. **Sem rota no período** — os cards continuam desenhados, cada um com o
   próprio vazio (revisto depois da primeira entrega, ver Decisão 7). O card de
   resumo mostra `R$ 0,00` e "Sem rotas no período."
5. **Card sem dado** — cada gráfico tem seu próprio vazio (ex.: ninguém
   preencheu bairro no período → só o card de bairros mostra a mensagem, o resto
   da tela continua útil).

## Estratégia de teste

`test/unit/routeStats_test.dart` (sem Firebase, sem widget — é onde erro
silencioso dói):

- período inclusivo nas duas pontas; rota fora do período não entra;
- `agendado` e `andamento` ficam de fora dos números de dinheiro;
- ranking por empresa em valor e em quantidade, ordenado do maior para o menor;
- insucesso por empresa: `isInsucesso == true` com `insucessoQnt` nulo conta 1;
- índice de insucesso ignora rota com `packages` nulo ou zero — e empresa sem
  nenhuma rota elegível não aparece no ranking (sem divisão por zero);
- rateio por bairro: 3 insucessos / 3 bairros = 1,0 em cada, e a soma do ranking
  bate com o total de insucessos;
- rota sem bairro não entra em ranking de bairro;
- dia da semana devolve sempre 7 pontos, inclusive os zerados;
- faixa horária: os quatro turnos cobrem 0–23 sem sobreposição, e a rota é
  classificada pela hora de `startAt`;
- lista vazia devolve lista vazia em todas as funções, sem lançar.

`test/widget/barRankChart_test.dart`: monta o card com quatro `RankEntry` e
verifica rótulos, valores formatados e a mensagem de vazio. Não toca em rede.

Os carrosséis, o filtro de data e o gráfico de linha ficam em verificação manual
no simulador — mesma linha da spec da lista.

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; texto em pt-BR; `User` recebido por
  construtor; stream criado uma vez fora do `build`; `dispose` em todo
  `PageController`; conta em `Utils/routeStats.dart`, nunca dentro do `build`.
- **Perguntar antes:** qualquer dependência além de `fl_chart`; mudar
  `NewRouteModal` ou o formato gravado; mexer em `addIter.dart`; criar índice
  composto no Firestore.
- **Nunca:** escrever, alterar ou apagar documento (a tela é read-only); deploy
  de regras; hardcodar chave de API.

## Critérios de sucesso

- [ ] A aba "Gráfico" abre com o mês corrente selecionado e mostra o total,
      a quantidade e a média por rota do período.
- [ ] Trocar início ou fim recalcula todos os cards; fim anterior ao início é
      **impossível** de escolher (a roleta trava no limite da outra data).
- [ ] Carrossel Empresas: valor, quantidade, insucessos e índice de insucesso,
      cada um em sua página, com indicador de bolinha acompanhando o arrasto.
- [ ] Carrossel Bairros: mais rodados e mais insucesso.
- [ ] Carrossel Tempo: linha por dia da semana com os 7 pontos, e linha por hora
      com o dropdown dos quatro turnos.
- [ ] Rota `agendado`/`andamento` não entra em nenhum número.
- [ ] Rota sem `packages` não derruba o índice de insucesso (nem vira 0%).
- [ ] Período sem rota mostra a mensagem de período vazio, não tela branca nem
      gráfico zerado.
- [ ] Salvar uma rota nova atualiza a tela sem reabrir (stream, não `Future`).
- [ ] `flutter analyze lib/` sem error/warning novo.
- [ ] `flutter test test/unit/routeStats_test.dart` e
      `test/widget/barRankChart_test.dart` passam.

## Decisões

**1. Só `concluido` e `pago` entram.** Rota agendada é previsão, não
faturamento; somar as duas coisas num card chamado "TOTAL" faz o número mentir
justo no dia em que o usuário mais olha (começo do mês, agenda cheia). O mesmo
recorte vale para os gráficos operacionais, para os números baterem entre os
cards — bairro "rodado" numa rota que ainda não aconteceu também não é verdade.

**2. Insucesso por bairro é rateado.** ~~Uma rota tem vários bairros e um único
`insucessoQnt`: o dado de qual bairro falhou não existe.~~ **Superada por
`docs/specs/insucesso-por-bairro.md`**: o `addIter` passou a coletar em qual
bairro cada insucesso aconteceu, e o rateio virou o **fallback** — vale para os
documentos gravados antes disso e para a parte que o usuário não quis detalhar.
A dívida que estava registrada aqui ("precisão real exige registrar insucesso
por bairro no `addIter`") foi paga; o que fica é que as rotas antigas seguem
rateadas para sempre, por não haver de onde tirar a informação.

**3. Índice de insucesso é sobre pacotes, não sobre rotas.** "1 insucesso em 120
pacotes" e "1 insucesso em 8 pacotes" não são o mesmo problema. O preço é
depender de um campo opcional: quem não preenche "Pacotes" fica fora **desse**
card e continua aparecendo em todos os outros.

**4. Quatro turnos.** Os três da referência (6–12, 13–18, 19–23) deixariam
00h–05h sem turno nenhum, e rota de entrega começa cedo. Faixa não coberta some
do gráfico sem avisar, que é o tipo de erro que ninguém percebe.

**5. `StreamBuilder`, não `loadData()` imperativo.** A referência carrega no
`initState` e chama `setState` — a tela nasce desatualizada quando o usuário
salva uma rota e volta. Aqui o stream é o mesmo já usado pela lista, então
gráfico e lista nunca discordam.

**6a. Período inválido é impedido, não avisado** (decidido durante a
implementação, no lugar do `showNotification` previsto). `showCupertinoDatePicker`
dispara o callback **a cada tique da roleta**, então validar depois da escolha
significaria disparar um toast por tique enquanto o usuário gira. Cada roleta
passou a receber o limite da outra (`minimumDate`/`maximumDate`), e o estado
inválido deixou de existir. Custo: dois parâmetros opcionais novos em
`lib/widget/dataPicker.dart` — aditivos, `addIter.dart` não muda.

**6. `GraficsScreen` passa a receber `User`.** Hoje a `HomeScreen` a constrói
sem argumento (`final _grafics = GraficsScreen();`); vira `late final`, com o
`user`, como já é o `ListIterScreen`. Lendo o uid do construtor, a tela não pode
ser montada sem usuário.

**7. Período vazio desenha os gráficos** (pedido depois de ver a tela rodando).

Deixou de ser uma tela de mensagem: os cards aparecem, cada um com o próprio
vazio. Tela em branco não deixava claro que o problema era o período, e o
formato da tela mudava a cada troca de data. O estado de **nunca ter cadastrado
rota nenhuma** continua sendo mensagem com a dica do botão `+`: nenhuma troca de
período resolve aquele caso.

Isso tornou "ranking vazio" um caminho normal, e não mais impossível —
`entries.first` nos cards de empresa passou a ser acesso a lista potencialmente
vazia. Todos viraram `_highest`/`_lowest`, que devolvem `—`.

**8. A tela passou a ter dois recortes, e isso é proposital** (revisão da
Decisão 1, pedida depois de ver a tela rodando).

O carrossel do topo tem quatro páginas, e cobre o **período inteiro**:

| Página | Status | Para quê |
|---|---|---|
| Resumo do período | todos | quanto o período vale, dividido por status |
| Pago no período | `pago` + `semRota` | o que já caiu na conta |
| A receber no período | `concluido` | rodado e não pago |
| Pendentes no período | `agendado` + `andamento` | estimativa do que falta rodar |

A Decisão 1 mantinha `agendado` fora de tudo, para "TOTAL" não misturar previsão
com faturamento. O caso de uso que apareceu depois derruba isso para o bloco de
dinheiro: o entregador precisa saber a estimativa do que ainda vai entrar para
decidir se pega mais uma rota ou se já bateu a meta do dia. Um total que ignora
a agenda não responde essa pergunta.

A separação por status resolve o risco original sem perder o número: cada página
diz exatamente qual fatia está mostrando, e a barra da página 1 é o índice das
outras três — mostra para onde foi cada real do período.

**Os gráficos de análise (empresa, bairro, dia, hora) continuam só em
`concluido` + `pago`**, pelo motivo de sempre: bairro "rodado" numa rota que não
saiu e índice de insucesso de rota que não aconteceu não existem.

Consequência aceita: o **TOTAL do topo difere do TOTAL dos gráficos de baixo**.
Um rótulo entre os dois blocos ("Análise das rotas concluídas e pagas") diz qual
recorte está valendo, em vez de deixar a diferença parecer erro de conta.

Dois detalhes que caíram junto, para número nenhum mentir:
- **Pacotes e insucessos só contam de rota realizada.** Uma agendada com pacotes
  estimados inflaria o denominador e faria a taxa de entrega subir sem ninguém
  ter entregue nada.
- **A taxa de recebimento usa `realizedTotal`, não `total`.** Com o total do
  período no denominador, marcar uma rota nova na agenda derrubaria a taxa
  sozinha, como se um pagamento tivesse atrasado.

## Dívidas e fora de escopo

- **Coleção inteira baixada** — mesma dívida da lista (`docs/specs/lista-iter.md`,
  Decisão 1). Agrupar no Firestore exigiria campo ISO ordenável e backfill.
- **Sem tela de detalhe.** A referência tem `GraficsDetailsScreen` com "Ver
  mais" e Curva ABC; aqui os cards mostram o top 4 e nada mais. Fica para quando
  o top 4 não bastar.
- Comparação entre períodos, exportação, meta de faturamento, filtro por
  empresa dentro da tela de gráficos e gráfico de KM/hora rodada.

## Perguntas em aberto

Nenhuma bloqueante. As quatro decisões de produto (dependência, recorte de
status, rateio de bairro, definição de índice) foram confirmadas antes desta
spec.

---

# Plano de implementação

## Grafo de dependências

```
 (1) fl_chart no pubspec
      │
 (2) Utils/routeStats.dart ────────────────┐   ← puro, sem UI, testável já
      │                                     │
 (3) widget/chartCard.dart                  │   ← moldura, sem dado
      │  widget/chartCarousel.dart          │
      ├──────────────┬─────────────┐        │
 (4) barRankChart  (5) lineChartCard  (6) periodFilter
      └──────────────┴─────────────┴────────┘
                     │
 (7) screens/graficsScreen.dart + home.dart
                     │
 (8) verificação no simulador
```

Ordem escolhida por dependência, não por importância. `routeStats` vem antes de
qualquer widget de propósito: é onde mora o erro silencioso (divisão por zero,
rateio, turno sem cobertura) e é a única parte que dá para provar com teste
barato. Se ela estiver certa, o resto é layout.

(4), (5) e (6) não dependem entre si — dá para inverter a ordem sem prejuízo.

## Riscos

| Risco | Mitigação |
|---|---|
| API do fl_chart 1.2.0 diferente do código de referência (que usa `SideTitleWidget(meta:)`, `getTooltipColor`, `FlDotCirclePainter`) | Tarefa 5 monta **um** gráfico mínimo primeiro e roda `flutter analyze` antes de estilizar. Se a API mudou, o conserto é local e antecipado. |
| `withOpacity` está deprecado nesta versão do Flutter e aparece em todo o código de referência | Usar `withValues(alpha:)` desde a primeira linha — é o que `routeCard.dart` e `companyFilter.dart` já fazem. `flutter analyze` limpo é critério de aceite de cada tarefa. |
| `DropdownButtonFormField(value:)` deprecado | O seletor de turno usa `DropdownButton` simples, como na referência — não passa pelo campo deprecado. |
| `formatDoubleToMoney` devolve string vazia para zero | Helper local `_money(double)` na tela, mesma correção que `RouteCard._formattedValue` já documenta. |
| Rota com `packages` nulo/zero derrubando o índice de insucesso | Coberto por teste na tarefa 2, antes de existir tela. |
| Carrossel com altura errada estourando o layout (`Expanded` dentro de `PageView` dentro de `SingleChildScrollView`) | `ChartCarousel` recebe `height` fixa e é ele quem impõe — cada card usa `Expanded` dentro dessa altura, igual à referência. Erro de overflow aparece na hora, na tarefa 3. |
| Regras do Firestore | Nenhuma mudança: a tela reusa `RouteController.watchAll`, que a lista já lê hoje. |

## Checkpoints

Depois de **cada** tarefa: `flutter analyze lib/` sem error/warning novo, mais o
teste da tarefa quando houver. Nenhuma tarefa entra na seguinte com analyze sujo.

---

# Tarefas

- [x] **1. Adicionar fl_chart**
  - Aceite: `fl_chart: ^1.2.0` no `pubspec.yaml`, `pubspec.lock` atualizado, app
    ainda compila.
  - Verificar: `flutter pub add fl_chart && flutter analyze lib/`
  - Arquivos: `pubspec.yaml`, `pubspec.lock`

- [x] **2. `routeStats.dart` — as contas, com teste primeiro**
  - Aceite: `RankEntry` + funções puras para os 7 recortes (período+status,
    total, valor/qtd por empresa, insucesso por empresa em quantidade e em
    índice, bairros rodados, bairros com insucesso rateado, série por dia da
    semana, série por faixa horária + os 4 turnos). Todos os casos da seção
    "Estratégia de teste" cobertos, **escritos antes** da implementação.
  - Verificar: `flutter test test/unit/routeStats_test.dart` verde e
    `flutter analyze lib/` limpo.
  - Arquivos: `lib/Utils/routeStats.dart`, `test/unit/routeStats_test.dart`

- [x] **3. Moldura: `ChartCard` e `ChartCarousel`**
  - Aceite: `ChartCard` (gradiente, título, `trailing` opcional, até 3 infoCards,
    `child`) e `ChartCarousel` (`PageView` + bolinhas, dono do próprio
    `PageController`, com `dispose`). Nenhum dado de rota envolvido.
  - Verificar: `flutter analyze lib/`; montagem visual conferida na tarefa 7.
  - Arquivos: `lib/widget/chartCard.dart`, `lib/widget/chartCarousel.dart`

- [x] **4. `BarRankChart` + teste de widget**
  - Aceite: recebe `List<RankEntry>`, um formatador de valor e um subtítulo
    opcional (padrão: participação no total); desenha até 4 barras com altura
    proporcional ao maior; estado vazio com mensagem própria.
  - Verificar: `flutter test test/widget/barRankChart_test.dart` verde.
  - Arquivos: `lib/widget/barRankChart.dart`,
    `test/widget/barRankChart_test.dart`

- [x] **5. `LineChartCard` (fl_chart)** — API 1.2.0 confere com o código de
  referência (`SideTitleWidget(meta:)`, `getTooltipColor`); risco descartado.
  - Aceite: gráfico mínimo compilando **primeiro** (checar a API 1.2.0), depois
    grade, eixos, tooltip, ponto e área. Rótulos de eixo X injetados por
    callback, para servir tanto a dia-da-semana quanto a hora.
  - Verificar: `flutter analyze lib/`.
  - Arquivos: `lib/widget/lineChartCard.dart`

- [x] **6. `PeriodFilter`**
  - Aceite: dois cards de data (Início/Fim) abrindo `showCupertinoDatePicker`;
    padrão = mês corrente; fim anterior ao início é recusado com
    `showNotification`, sem alterar o filtro.
  - Verificar: `flutter analyze lib/`; comportamento conferido na tarefa 8.
  - Arquivos: `lib/widget/periodFilter.dart`

- [x] **7. Montar `GraficsScreen` e ligar na `HomeScreen`**
  - Aceite: `StreamBuilder` sobre `RouteController.watchAll(uid)` criado uma vez
    em `late final`; card resumo + 3 carrosséis; os 5 estados de tela; `User`
    por construtor.
  - Verificar: `flutter analyze lib/` e `flutter test` (sem regressão nos testes
    existentes).
  - Arquivos: `lib/screens/graficsScreen.dart`, `lib/screens/home.dart`

- [ ] **8. Verificação no simulador**
  - Aceite: percorrer os critérios de sucesso com dados reais — trocar período,
    arrastar os 3 carrosséis, trocar turno, conferir que rota agendada não soma.
  - Verificar: `flutter run`
  - Arquivos: nenhum (ajustes viram tarefa nova)
