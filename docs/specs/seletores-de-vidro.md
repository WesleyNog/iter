# Spec: Período e empresas no vidro

Status: **implementada, falta o aparelho** · Criada, aprovada e implementada
em 2026-10-11, depois de `docs/specs/redesenho-amigos.md` · As três decisões
foram tomadas antes da spec: período em **Mês · Semana · Personalizado com
setas**, empresas em **trilho de vidro com pílulas brancas**, folha de filtros
**mantida em chips** · Conferida em quadros renderizados com Roboto a 390 dp

## Objetivo

Levar o padrão das abas de Amigos — vidro, pílula que desliza — aos outros
seletores do topo das telas, **onde ele cabe**:

- **Gráficos e Resumo**: o seletor de período deixa de ser uma fileira de cinco
  chips que rola e passa a ser três abas de vidro com uma barra de navegação
  embaixo, a mesma do Ranking.
- **Lista**: o filtro de empresas ganha o trilho de vidro, mas **continua**
  acendendo cada empresa com a própria pílula branca.

Sucesso:

- o "Personalizado" fica à vista sem rolar, e nenhum rótulo é cortado na borda;
- qualquer mês ou semana do passado fica a um toque de seta por vez, sem
  roleta;
- as três telas do topo (Gráficos, Lista, Resumo) e Amigos parecem o mesmo
  material.

### Por que o período muda de forma, e não só de cor

Cinco opções não cabem em fatias iguais: "Semana Anterior" não cabe num quinto
da largura do iPhone, e é por isso que os chips rolam hoje (ver o comentário em
`periodPresetFilter.dart` e o `CLAUDE.md` sobre "Substituição"). O print do
aparelho mostra o custo: "Seman…" cortado na borda e o "Personalizado"
escondido fora da tela — quem não sabe que ele existe nunca o encontra.

Mas "Mês anterior" e "Semana anterior" não são opções novas, são **o mesmo
recorte um passo para trás**. Com uma seta, o passo para trás vira gesto e as
cinco opções viram três — que cabem.

### Por que as empresas não ganham a pílula que desliza

Duas razões, cada uma suficiente:

- **É múltipla escolha.** Vazio e completo querem dizer "tudo" (`filtros.md`);
  uma pílula que desliza só sabe estar num lugar. Virar escolha única desfaria
  aquela decisão.
- **Os logos têm a cor das marcas.** O X azul da Amazon some sobre a pílula
  azul. A pílula branca de hoje é o que deixa os três legíveis.

## Layout

### Gráficos e Resumo

```
┌──────────────────────────────────────────────┐
│ ╭──────────────────────────────────────────╮ │
│ │ ▐█ Mês █▌       Semana     Personalizado │ │  ← GlassTabs (as de Amigos)
│ ╰──────────────────────────────────────────╯ │
│        ‹        OUTUBRO 2026        ›         │  ← Mês: › apagada no atual
│                                              │
│ ╭──────────────────────────────────────────╮ │
│ │  (cards de sempre)                       │ │
```

```
│        ‹    05/10 – 11/10/2026      ›         │  ← Semana: segunda a domingo
```

```
│  [📅 Início 01/08/2026] → [📅 Fim 12/08/2026] │  ← Personalizado: as roletas
```

**"Personalizado" encolhe antes de cortar.** É o rótulo mais comprido das
abas e, renderizado com Roboto a 390 dp, ocupa 96 dos 116 px da terça parte —
no iPhone a fonte é mais larga, e com a fonte do sistema aumentada ele não
cabe. As `GlassTabs` desenham o rótulo num `FittedBox(scaleDown)`: encolhe um
pouco em vez de virar "Personaliza…".

O rótulo do mês é o do Ranking (`OUTUBRO 2026`). A semana mostra as duas
pontas; o ano vai uma vez quando as duas são do mesmo ano, e nas duas quando a
semana atravessa a virada (`29/12/2025 – 04/01/2026`).

O card de total do Resumo **mantém** o título `OUTUBRO 2026`. Fica repetido com
a barra logo acima, mas é o mesmo `periodLabel` que a tela de gastos recebe
quando é empurrada sozinha — sem a barra em cima — e tirá-lo de um lugar só
seria a segunda regra para o mesmo texto.

### Lista

```
│ ╭──────────────────────────────────────╮ ╭──╮ │
│ │  🤝     ▐ ✕ ▌      SPX               │ │⚙ │ │  ← vidro; pílula branca por
│ ╰──────────────────────────────────────╯ ╰──╯ │     empresa marcada
```

O botão de filtros vira um círculo de vidro da mesma altura do trilho (48), com
o badge de sempre.

**A pílula branca sobre o vidro é discreta**, como já era sobre o trilho cinza:
quem diz o que está marcado é sobretudo o logo aceso contra os apagados. Se no
aparelho ela sumir, o remédio que preserva os logos é tingi-la de azul bem
claro (`blue.shade50`) — nunca a pílula azul das abas.

### A folha de filtros da Lista não muda

Continua com os chips, "Todo o período" incluído. Ali todas as seções são
chips empilhados, e o `FilterPill` existe para elas parecerem uma família; um
trilho de vidro no meio da folha seria o estranho. É a única tela que continua
usando `PeriodPresetFilter` e o enum `PeriodPreset`.

### AppBar: o veículo e o menu da conta

Pedido depois, na mesma leva. O botão do veículo era um `IconButton` com o
render num **círculo cinza** de 30 px: o carro largo, cortado pelo `cover`,
sobrava como uma porta no meio de um disco. Virou um `GlassTileButton` — vidro
quadrado de 44, cantos de 14, o branco das abas — com o render em `contain`
dentro de 36 px de cantos 10 (concêntricos com os 14). A foto do dono continua
cobrindo, e o card da lista de veículos não muda: `VehicleThumb` ganhou
`radius`, `background` e `renderFit` com os padrões de antes.

**No iPhone o carro ainda ficou pequeno**: o render padrão da imagin põe o
carro no meio de uma tela com margem larga, e com `contain` ele ocupava menos
da metade do botão. A correção é pedir à CDN o carro enquadrado —
`zoomType=fullscreen`, parâmetro documentado da API, não edição da imagem —
em `framedCarImageUrl`, aplicado **na exibição** sobre a URL gravada, então
vale também para os veículos confirmados antes. Só a `AppBar` pede; o card e o
formulário mostram o enquadramento que o usuário confirmou. O mesmo print
mostrou a sombra do botão cortada numa linha reta: a `AppBar` recorta o que
passa da altura dela, e a `pillShadow` descia além dos 6 px que sobram embaixo
do botão — o `GlassTileButton` tem sombra própria, rente.

O menu "⋮" saiu da `HomeScreen` para `AccountMenu` (com teste) e ficou branco
de verdade: o Material 3 tingia a superfície com o lilás do tema. Abre
**embaixo** do botão em vez de por cima, os ícones vão em quadrados de cantos
suaves como o do veículo, e uma divisória separa Sair de Excluir conta — o que
se desfaz no próximo login do que não se desfaz nunca.

## As regras do período

Moram em `Utils/periodSelection.dart`, puras, com o "hoje" injetável — a mesma
razão de `periodPreset.dart`: "que semana vem depois desta" é conta, e conta
dentro do `build` não se prova.

**1. O passo é sempre de um mês ou de uma semana inteiros.** `monthAt(offset)` e
`weekAt(offset)`, com o `DateTime` construído pelo construtor (nunca
`Duration`, ver `CLAUDE.md` sobre semanas). `previousMonth` e `previousWeek`
passam a ser `monthAt(-1)` e `weekAt(-1)` — uma conta, dois nomes.

**2. A seta › para no período atual.** Hoje o seletor só oferece o atual e o
anterior; o futuro nunca esteve a um toque, e o Ranking também não vai além do
mês corrente. Quem precisa do mês que vem (rotas agendadas) usa o
Personalizado, como hoje.

**3. A seta ‹ não tem limite.** As rotas são lidas inteiras do aparelho
(`RouteController.watchAll`), então não há janela como a dos doze baldes do
Ranking. Mês sem rota é mês sem rota, e as telas já dizem isso.

**4. Trocar entre Mês e Semana cai no período que contém o último dia que
estava na tela, sem passar de hoje.**

| estava em | toca em | vai para |
|---|---|---|
| Mês atual (outubro) | Semana | a semana atual — o fim de outubro é futuro, então vale hoje |
| Agosto | Semana | a última semana de agosto |
| Semana atual | Mês | o mês atual |
| Semana de 28/09 a 04/10 | Mês | outubro — o mês do último dia |
| Personalizado | Mês ou Semana | o que contém o fim das roletas, limitado a hoje |
| qualquer um | Personalizado | **as mesmas datas** que estavam na tela |

A alternativa — sempre voltar para o atual — é mais simples e joga fora o lugar
onde o usuário estava: quem olha agosto e quer ver as semanas de agosto teria
de tocar ‹ nove vezes. A última linha é a regra que o `PeriodPresetFilter` já
tem: quem entra no Personalizado quer ajustar o recorte em que estava.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1. Nenhuma dependência nova: `GlassTabs`,
`GlassSurface` e `SegmentedSelector` já existem.

## Comandos

```bash
flutter analyze lib/ test/
flutter test test/unit/periodSelection_test.dart
flutter test test/unit/periodPreset_test.dart
flutter test test/widget/periodNavigator_test.dart
flutter test test/widget/segmentedSelector_test.dart test/widget/companyFilter_test.dart
flutter test
```

## Estrutura

```
lib/Utils/periodPreset.dart        monthAt / weekAt; current/previous passam por eles
lib/Utils/periodSelection.dart     novo — PeriodKind, PeriodSelection, o rótulo
lib/widget/periodNavigator.dart    novo — GlassTabs + setas ou roletas
lib/widget/glassSurface.dart       a sombra de pílula vira constante
lib/widget/glassNavBar.dart        GlassPill usa a constante; GlassCircleButton
                                   ganha iconSize
lib/widget/glassTabs.dart          usa a constante
lib/widget/segmentedSelector.dart  tom `glass`: trilho de vidro
lib/widget/companyFilter.dart      usa o tom `glass`
lib/widget/periodPresetFilter.dart só a folha usa agora — comentários
lib/screens/graficsScreen.dart     PeriodNavigator
lib/screens/summaryScreen.dart     PeriodNavigator
lib/screens/listIterScreen.dart    botão de filtros de vidro
test/unit/periodSelection_test.dart      novo
test/widget/periodNavigator_test.dart    novo
test/widget/segmentedSelector_test.dart  ganha o tom glass
```

## Estratégia de teste

`periodSelection_test.dart` — as regras acima, uma a uma, com "hoje" fixo:
`monthAt`/`weekAt` com deslocamento e virada de ano; a seta › presa no zero; as
seis linhas da tabela de troca; o rótulo de mês, de semana no mesmo ano e de
semana atravessando a virada.

`periodNavigator_test.dart` — as três abas com keys `periodo-mes`,
`periodo-semana`, `periodo-personalizado`; ‹ e › emitem um passo; › desligada
no período atual; as roletas só existem no Personalizado, e as setas só fora
dele.

`segmentedSelector_test.dart` — no tom `glass`, um `BackdropFilter`; a múltipla
escolha continua com um `Opacity` por segmento. `companyFilter_test.dart` passa
**sem edição**.

As telas de Gráficos, Resumo e Lista abrem o Firestore no `initState` e não
têm teste de widget; o que elas fazem com o período é guardar uma
`PeriodSelection` e ler `range` — a decisão está toda no que tem teste.

## Fronteiras

- **Sempre:** texto em pt-BR; semana de segunda a domingo; datas pelo
  construtor; a folha de filtros intocada.
- **Perguntar antes:** mudar o padrão de abertura (continua o mês atual); deixar
  a seta › ir ao futuro.
- **Nunca:** a pílula azul no filtro de empresas; transformar o filtro de
  empresas em escolha única; dependência nova.

## Critérios de sucesso

- [x] Gráficos e Resumo abrem no mês atual, com a aba Mês acesa e `› `apagada.
- [x] ‹ volta um mês ou uma semana por toque, sem limite.
- [x] Trocar entre Mês e Semana segue a tabela da regra 4.
- [x] Personalizado mostra as roletas com as datas que estavam na tela.
- [x] Nenhum rótulo do seletor de período é cortado, e não há rolagem lateral.
- [x] O filtro de empresas é vidro, acende cada empresa com pílula branca, e o
      vazio continua sendo "todas".
- [x] O botão de filtros é um círculo de vidro alinhado ao trilho, com o badge.
- [x] A folha de filtros da Lista não mudou.
- [x] `flutter analyze` sem aviso novo; a suíte passa, com a falha de sempre
      (1502 testes, 22 novos).
- [ ] Conferido no iPhone: "Personalizado" inteiro, a pílula branca visível no
      vidro, as setas no Resumo e nos Gráficos.

## Fora de escopo

- **O futuro na seta ›** (regra 2).
- **Lembrar o período entre abas.** `home.dart` desmonta a tela ao trocar de
  aba (`filtros.md`); o período volta ao mês atual, como hoje.
- **Legenda "esta semana" / "semana passada"** embaixo das datas. As datas já
  dizem, e a legenda faria a barra mudar de altura entre um passo e outro.
