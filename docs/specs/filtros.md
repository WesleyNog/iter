# Spec: Filtros da Lista e do Período

Status: **implementada e conferida no simulador** (2026-08-22) · Plano e tarefas
no fim do arquivo

## Objetivo

Duas mudanças de filtro, em telas diferentes, pelo mesmo motivo: hoje cada
filtro só responde **uma** pergunta por vez, e o entregador precisa cruzar
duas.

**1. Lista de rotas** (`listIterScreen`). O trilho de empresa é exclusivo — ao
marcar Amazon, o Mercado Livre sai. Passa a ser **múltipla escolha**: marcar
Amazon *e* Mercado Livre mostra as duas. O segmento "Todas" some, porque
nenhum marcado já quer dizer todas. E entra um `IconButton` ao lado do trilho
abrindo os filtros que não cabem nele: status, período, veículo, faixa de valor
e ordenação.

**2. Período dos Gráficos e do Resumo** (`graficsScreen`, `summaryScreen`).
Os dois campos de data viram um seletor de atalhos — Este Mês, Mês Anterior,
Esta Semana, Semana Anterior, Personalizado — e as datas só aparecem no
Personalizado. Padrão continua Este Mês.

Usuário: o entregador. Sucesso = ele responde "quanto fiz de Amazon e Shopee
na semana passada, só o que já foi pago" sem abrir rota nenhuma e sem
descobrir o recorte por eliminação.

Nada é gravado. As duas telas são somente leitura, os dois filtros rodam em
memória sobre o stream que já existe (`RouteController.watchAll`), e nenhuma
consulta nova vai ao Firestore.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1. **Nenhuma dependência nova** — `RangeSlider`,
`Wrap`, `SingleChildScrollView` horizontal e `showModalBottomSheet` são todos
do Material que já vem no SDK.

Sem pacote de gerência de estado: `setState` + `StreamBuilder`, como o resto do
app.

## Comandos

```bash
flutter pub get
flutter analyze lib/ test/                    # sem error/warning novo
flutter test test/unit/periodPreset_test.dart
flutter test test/unit/routeFilter_test.dart
flutter test test/widget/companyFilter_test.dart
flutter test test/widget/segmentedSelector_test.dart
flutter test test/widget/routeFilterSheet_test.dart
flutter test test/widget/periodPresetFilter_test.dart
flutter test                                  # widget_test.dart segue quebrado (template)
flutter run -d <device-id>                    # conferir no aparelho: ver "Fronteiras"
```

## Estrutura

```
lib/Utils/periodPreset.dart          → os cinco recortes de data, puros (novo)
lib/widget/filterPill.dart           → a pílula compartilhada dos filtros (novo)
lib/Utils/routeFilter.dart           → o filtro e a ordenação, puros (novo)
lib/widget/segmentedSelector.dart    → + modo múltipla escolha
lib/widget/companyFilter.dart        → passa a receber Set<Company>
lib/widget/routeFilterSheet.dart     → a folha dos outros filtros (novo)
lib/widget/periodPresetFilter.dart   → chips de atalho + datas ocultas (novo)
lib/widget/periodFilter.dart         → intocado; vira filho do de cima
lib/screens/listIterScreen.dart      → estado do filtro + estado vazio novo
lib/screens/graficsScreen.dart       → troca PeriodFilter por PeriodPresetFilter
lib/screens/summaryScreen.dart       → idem
test/unit/periodPreset_test.dart     → os recortes, sem relógio (novo)
test/unit/routeFilter_test.dart      → filtro e ordenação (novo)
test/widget/routeFilterSheet_test.dart   → a folha (novo)
test/widget/periodPresetFilter_test.dart → os chips (novo)
test/widget/companyFilter_test.dart      → reescrito para múltipla escolha
```

**A conta não mora no widget.** É a mesma separação que `routeStats.dart`
impôs aos gráficos: `periodPreset.dart` e `routeFilter.dart` são funções puras
sobre tipos do app, testáveis sem Firebase, sem `BuildContext` e sem bombear
widget. O `build` das telas fica sendo composição.

## Dados

Nenhum campo novo, nenhuma escrita, nenhuma regra do Firestore tocada. O que
cada filtro lê de `NewRouteModal`:

| filtro | campo lido | disponível em |
|---|---|---|
| Empresa | `company` | toda rota |
| Status | `status` | toda rota |
| Período | `startAt` | toda rota (`_readStart` reconstrói as antigas) |
| Faixa de valor | `value` | toda rota |
| Veículo | `provision.vehicleId` | **só** rota concluída, paga ou sem rota |
| Ordenação | `startAt`, `value`, `createdAt` | toda rota |

A linha do veículo é o único dado que não existe para toda rota — ver
Pergunta em aberto 1.

## Regras

### 1. Nenhum marcado e todos marcados são a mesma coisa

Vale para empresa e para status. `Set<Company>` vazio ou com os três: passa
tudo. Um marcado: só ele. Dois marcados: os dois. Tocar num marcado desmarca
**só ele**.

A regra mora **uma vez**, em `routeFilter.dart`, e não uma vez por filtro:

```dart
/// Vazio ou completo passa tudo — é a mesma resposta, e escrever a segunda
/// metade em cada filtro é onde uma delas um dia fica para trás.
bool _passes<T>(Set<T> selected, T value, int total) =>
    selected.isEmpty || selected.length == total || selected.contains(value);
```

Os filtros se combinam com **E**: Amazon + Concluído é rota concluída da
Amazon, não a união das duas.

Nota de desenho: com o conjunto vazio, os três logos ficam apagados. É
literalmente o que foi pedido, e é o estado inicial — mas "tudo apagado" e
"nada aparece" se parecem. Quem resolve isso é o estado vazio da regra 4, que
nunca deixa a lista em branco sem dizer por quê.

### 2. Os cinco recortes de data

`PeriodPreset { esteMes, mesAnterior, estaSemana, semanaAnterior, personalizado }`,
com `reference` opcional para o teste não depender do relógio — igual
`sortByDate` já faz.

| preset | início | fim |
|---|---|---|
| Este Mês | dia 1 do mês de `reference` | último dia do mesmo mês |
| Mês Anterior | dia 1 do mês anterior | último dia do mês anterior |
| Esta Semana | segunda-feira da semana de `reference` | domingo seguinte |
| Semana Anterior | segunda sete dias antes | domingo seis dias depois dela |
| Personalizado | o que o usuário girar nas roletas | idem |

Semana é **segunda a domingo**, que é `DateTime.weekday` 1..7 sem conversão
nenhuma. A aritmética passa pelo construtor, nunca por `Duration`:

```dart
// DateTime(2026, 8, 0) é 31/07 e DateTime(2026, 13, 1) é janeiro de 2027 — o
// construtor normaliza. `subtract(Duration(days: 7))` não: ele soma 168 horas,
// e num fuso com horário de verão isso cai na hora errada do dia certo.
DateTime _monday(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
```

Fortaleza não tem horário de verão e o Brasil o extinguiu em 2019, então hoje
os dois caminhos dão o mesmo resultado. O construtor é escolhido mesmo assim
porque é o que continua certo se alguém rodar o app em outro fuso — o custo de
acertar é zero e o erro é do tipo que aparece uma vez por ano.

`inPeriod` já compara **por dia** e com as duas pontas inclusive
(`routeStats.dart:174`), então a hora que a roleta devolver não muda recorte
nenhum.

`PeriodFilter.currentMonth` **fica onde está**: `periodLabel` do Resumo e
`test/unit/periodLabel_test.dart` dependem dela. Ela passa a delegar para
`periodPreset.dart` — uma implementação só, dois nomes, como
`VehicleController.activeFrom`.

### 3. Trocar de preset reescreve as datas; girar as roletas não troca de preset

Escolher Esta Semana carrega 17/08–23/08 nos campos ocultos. Abrir o
Personalizado mostra as datas do último preset ativo, já preenchidas — o
usuário ajusta a partir do recorte em que estava, em vez de começar do zero.

O caminho de volta é único: mexer numa roleta só é possível dentro do
Personalizado, então nenhuma ação pode deixar o chip ativo mentindo sobre o
período. Isso é o que evita a tela mostrar "Este Mês" sobre um recorte de nove
dias.

### 4. Lista vazia por filtro diz qual filtro

Hoje a mensagem é `'Nenhuma rota da ${companyLabel(_companyFilter!)}'` — com
`!` num campo que passa a ser um `Set`, e com uma empresa só num filtro que
passa a ter cinco eixos. Some.

Três estados distintos, porque cada um pede uma ação diferente:

1. **Sem rota nenhuma** — "Nenhuma rota por aqui ainda", botão `+`. (Já existe.)
2. **Tem rota, nenhuma passa nos filtros** — "Nenhuma rota com os filtros
   atuais", com um botão **Limpar filtros** que zera tudo de uma vez. Mandar o
   usuário desmarcar cinco coisas na mão para voltar a enxergar a lista é o
   caminho que ninguém percorre.
3. **Erro / carregando** — como está.

### 5. Ordenação é aplicada depois do filtro, e o padrão não muda

`RouteController.watchAll` ordena por **proximidade com hoje** e continua
ordenando: é a decisão registrada em `lista-iter.md`, nenhum índice do
Firestore a expressa, e ela é o padrão da lista.

As outras ordens são reordenação em memória do resultado já filtrado, em
`routeFilter.dart`: mais recente, mais antiga, maior valor, menor valor. O
padrão `perto de hoje` devolve a lista **na ordem em que chegou**, sem
reordenar — assim a regra do controller segue sendo a única dona dela.

### 6. A faixa de valor tem os limites vindos dos dados, não de um número redondo

`RangeSlider` de 0 a 1000 é inútil para quem faz rota de R$ 250 e quebra para
quem faz de R$ 1.400. Os limites saem do **mínimo e do máximo da lista inteira**,
antes de qualquer filtro — senão o slider encolhe conforme o usuário filtra, e
a alça que ele acabou de arrastar sai do trilho.

Dois casos que derrubam o widget e por isso são tratados antes dele:

- **Todas as rotas valendo o mesmo** — a rota única incluída. `RangeSlider`
  exige `min < max` e lança, e não há o que discriminar de qualquer forma. Os
  dois motivos apontam para o mesmo `null`, e a seção não é desenhada.
  A comparação é dos valores **crus**, antes do arredondamento: escrita depois
  dele, uma rota única de R$ 123 virava a faixa 120–130, perfeitamente válida e
  perfeitamente inútil. O teste unitário é que apontou a diferença.
- **Limites colados** (R$ 199,00 a R$ 212,00): as pontas ficam impossíveis de
  agarrar. Arredonda-se o mínimo para baixo e o máximo para cima na dezena mais
  próxima.

### 6b. A faixa guardada é conferida contra os limites de agora

Os limites saem da lista, e **a lista muda entre uma abertura e a outra** — pela
própria tela que abre a folha, que apaga rota deslizando o card e edita valor no
formulário. Apagar a rota de R$ 500 de uma lista de 100/250/500 derruba o teto
para R$ 250 com a faixa 300–500 ainda gravada, e aí `RangeSlider` **lança**
(`assert(values.start >= min)`): tela vermelha no debug, alça fora do trilho no
release.

A faixa é **descartada**, não espremida. Uma faixa 300–500 encolhida à força
para 100–250 não é o que o usuário escolheu, e um filtro que se reescreve
sozinho engana mais do que um que se desliga — e ele sai do badge junto, porque
deixou mesmo de cortar. Com os limites em `null`, a faixa também cai: esconder a
seção mantendo o eixo ligado deixaria o badge contando um filtro cujo botão de
limpar mora dentro da seção que sumiu.

Isto é a Regra 6 vista do outro lado. Ela cuidou de os limites virem da lista
inteira; faltava o caso em que a lista inteira é outra.

A faixa fica **inativa** enquanto o usuário não a tocar. Um slider que já nasce
cobrindo tudo parece filtro ligado quando não é, e entraria na contagem do
badge sem estar filtrando nada.

### 6c. Os veículos vêm de um stream, e `null` é "não deu para saber"

A folha precisa **nomear** o filtro, e `provision` guarda só o id. Ler os
veículos com um `get()` na abertura seria uma consulta nova por toque no ícone —
o que a seção Fronteiras põe em "Nunca" — e obrigaria a folha a esperar a rede
para aparecer: dois toques durante a espera empilhavam duas folhas, e confirmar
a de baixo depois desfazia a escolha feita na de cima. Sem `await` antes de
abrir, esse caminho deixa de existir.

A tela assina `VehicleController.watchAll` uma vez, em `initState`, e guarda a
última leitura **sem `setState`**: nada na lista desenha veículo.

`null` quer dizer **não deu para saber** — a leitura ainda não chegou, ou
falhou —, nunca "não tem veículo". Colapsar as duas esconderia a seção inteira
de um entregador com carro cadastrado e sem sinal, que iria procurar o filtro
que sumiu. É a mesma distinção que `getWeather` faz com o clima e que
`norouterule` faz entre regra ausente e falha de leitura, pelo mesmo motivo. A
seção desenha a frase quando alguma rota tem veículo e os nomes não vieram; some
de vez quando não há rota com veículo, porque aí não há mesmo o que filtrar.

### 7. A folha aplica no "Aplicar", não a cada toque

`showModalBottomSheet` cobre a lista: filtro que aplica ao vivo muda algo que
o usuário não está vendo. A folha guarda um rascunho, e devolve um
`RouteFilter` no `Navigator.pop` — ou `null` se for descartada, e aí nada
muda. Isso também é o que a torna testável como função pura de ida e volta,
sem bombear a tela inteira.

Duas ações no rodapé: **Limpar tudo** e **Aplicar**.

### 8. O ícone diz quantos filtros estão ligados

Sem badge, o entregador fecha a folha e não tem como saber que sobrou um status
marcado — e vai jurar que sumiu rota. O badge conta **eixos ativos** (status,
período, veículo, faixa), não opções marcadas: "3" querendo dizer três status
do mesmo eixo seria mentira sobre quantos cortes estão valendo.

Empresa não entra na conta: ela está desenhada na tela ao lado, marcada.

### 9. O filtro vive enquanto a aba está aberta, e só

Não é gravado em disco: filtro que persiste entre sessões é a origem clássica do
"sumiram minhas rotas" uma semana depois, e persistir exigiria
`shared_preferences`, que é dependência nova.

**E ele também não sobrevive a trocar de aba.** A primeira versão desta regra
dizia que sim, porque `HomeScreen` guarda as telas em campos `late final` — o
que preserva o *widget* e nunca o *estado*. `home.dart:337` monta
`body: screens[current]`, não um `IndexedStack`: na troca de aba o elemento é
desmontado e o `State` vai junto, com `_filter`, `_expandedId` e a última
leitura do stream. É o mesmo motivo pelo qual `_expandedId` já voltava fechado,
muito antes deste filtro existir.

Fica registrado porque a frase errada estava a caminho de virar comentário no
código — e um comentário que descreve um mundo que não existe é o que faz a
próxima pessoa preservar um caso que ninguém tem.

## Estilo de código

Função pura de topo no `Utils`, o padrão de `routeTime.dart` e `routeStats.dart`:

```dart
/// O recorte de datas de um atalho.
///
/// [reference] existe para o teste não depender do relógio — mesma escolha de
/// `sortByDate`, pelo mesmo motivo: "este mês" muda de resposta todo dia 1.
({DateTime start, DateTime end}) rangeOf(
  PeriodPreset preset, [
  DateTime? reference,
]) {
  final now = reference ?? DateTime.now();
  switch (preset) {
    case PeriodPreset.esteMes:
      return (start: DateTime(now.year, now.month, 1),
              end: DateTime(now.year, now.month + 1, 0));
    ...
  }
}
```

O filtro como objeto imutável com `copyWith`, para a folha montar o rascunho
sem espalhar cinco campos soltos pela tela:

```dart
class RouteFilter {
  const RouteFilter({
    this.companies = const {},
    this.statuses = const {},
    this.period,
    this.vehicleId,
    this.valueRange,
    this.order = RouteOrder.pertoDeHoje,
  });
  ...
  /// Quantos eixos além da empresa estão cortando a lista — o número do badge.
  int get extraCount => ...;

  /// Nada está sendo cortado e a ordem é a padrão.
  ///
  /// Não é `isEmpty`, e o nome mudou na implementação por isso: com as três
  /// empresas marcadas isto é `true`, porque marcar todas é exatamente o que
  /// "mostre tudo" quer dizer. Quem precisa limpar as marcas usa `none`.
  bool get filtersNothing => ...;
}
```

Texto de interface em pt-BR. Arquivos em camelCase, como o projeto.

## Estratégia de teste

O que dá para testar de verdade vai para teste unitário; o widget é testado
pela **causa**, nunca por "o texto cabe" — a fonte do teste é quadrada e o
CLAUDE.md já registra um `SegmentedButton` que passou em três testes de
largura e quebrou linha no iPhone do usuário.

**Unitário — `periodPreset_test.dart`** (sem relógio, `reference` fixo):
- os cinco recortes, com uma referência no meio do mês e da semana;
- **quarta-feira, domingo e segunda-feira** como referência de "esta semana" —
  domingo é o dia em que um cálculo errado devolve a semana seguinte;
- virada de ano: mês anterior a janeiro é dezembro do ano passado;
- fevereiro bissexto fecha no dia 29;
- semana que atravessa a virada do mês.

**Unitário — `routeFilter_test.dart`**:
- vazio passa tudo; completo passa tudo; um passa um; dois passam dois;
- empresa **e** status se cruzam com E, não com OU;
- faixa de valor inclui as duas pontas;
- rota sem `provision` não passa em nenhum filtro de veículo;
- cada ordem, incluindo `pertoDeHoje` devolvendo a lista **intacta**;
- `extraCount` não conta empresa e não conta faixa não tocada.

**Widget — `companyFilter_test.dart`** (reescrito): três segmentos e nenhum
"todas"; tocar num desmarcado devolve o conjunto com ele; tocar num marcado
devolve o conjunto sem ele; conjunto vazio deixa os três apagados.

**Widget — `segmentedSelector_test.dart`**: o modo de escolha única continua
com exatamente um `Opacity` em 1 (é o teste que existe hoje, e ele não pode
mudar de resultado); o modo múltiplo aceita dois.

**Widget — `routeFilterSheet_test.dart`**: descartar devolve `null` e não
altera nada; Aplicar devolve o rascunho; Limpar tudo devolve o filtro vazio;
com `min == max` a seção de valor não é desenhada.

**Widget — `periodPresetFilter_test.dart`**: as roletas **não** estão na
árvore fora do Personalizado; estão dentro dele; trocar de chip emite o
recorte certo. A causa, não a aparência: que os chips vivam num scroll
horizontal (`find.byType(SingleChildScrollView)` com `scrollDirection ==
Axis.horizontal`), que é o que garante que rótulo nenhum quebre linha
independentemente da fonte.

Fora de teste automatizado, por decisão: se "Semana Anterior" *parece* certo na
tela é chamada do aparelho.

## Fronteiras

- **Sempre:** `flutter analyze lib/ test/` limpo; texto em pt-BR; conta em
  função pura no `Utils`, nunca dentro do `build`; stream criado uma vez em
  campo `late final`; rodar no aparelho antes de dar por pronto — os dois
  controles são de largura apertada e teste de widget não responde por isso.
- **Perguntar antes:** mudar `NewRouteModal` ou o formato gravado em
  `iter/{uid}/routes`; alterar `firestore.rules`; adicionar dependência
  (inclusive `shared_preferences` para persistir filtro); mudar a ordenação
  padrão de `RouteController.watchAll`.
- **Nunca:** fazer o **filtro** disparar consulta ao Firestore — a leitura dos
  veículos é um stream assinado uma vez em `initState`, nunca um `get()` por
  abertura da folha (ver Regra 6c); gravar `vehicleId` na rota "só para o filtro
  funcionar" sem que isso seja decidido à parte — é campo novo em documento existente, e as rotas
  antigas ficariam sem ele; fazer o filtro disparar consulta nova ao Firestore;
  aplicar o filtro de período **antes** de `summarize` de um jeito que mude o
  significado dos cards do topo.

## Critérios de sucesso

**Lista de rotas**

- [x] O trilho tem três segmentos — Mercado Livre, Amazon, Shopee — e nenhum "Todas".
- [x] Abrir a aba com nenhum marcado mostra todas as rotas.
- [x] Marcar Mercado Livre mostra só Mercado Livre; marcar Amazon em seguida mostra as duas, com as duas acesas.
- [x] Tocar no Mercado Livre já marcado desmarca só ele; sobra Amazon.
- [x] Marcar os três mostra o mesmo que não marcar nenhum.
- [x] Existe um `IconButton` ao lado do trilho que abre a folha de filtros.
- [x] A folha filtra por status (múltipla escolha), período, veículo, faixa de valor e ordenação.
- [x] Empresa e status se cruzam: Amazon + Concluído mostra rota concluída da Amazon, e nada mais.
- [x] O ícone mostra um badge com o número de eixos ativos, e nenhum badge quando não há filtro extra.
- [x] Filtro que não casa com nada mostra "Nenhuma rota com os filtros atuais" e um botão que limpa tudo — nunca uma tela em branco.
- [x] Trocar qualquer filtro fecha o card expandido.

**Gráficos e Resumo**

- [x] As duas telas abrem em Este Mês, com o mesmo recorte de hoje.
- [x] Os cinco atalhos aparecem sem quebrar linha, rolando na horizontal.
- [x] Início e Fim não estão na tela fora do Personalizado, e aparecem nele.
- [x] Esta Semana cobre de segunda a domingo da semana corrente — provado em teste
      com domingo, segunda e quarta como referência, e conferido no simulador.
- [x] Semana Anterior cobre as sete anteriores a essa segunda.
- [x] Trocar o atalho redesenha todos os cards com o novo período.
- [x] Entrar no Personalizado traz as datas do atalho anterior já preenchidas.
- [x] O card de total do Resumo continua dizendo "AGOSTO 2026" em mês inteiro e as duas datas fora dele.
- [x] `flutter test` passa (menos `widget_test.dart`, que já estava quebrado).

## Perguntas em aberto — resolvidas

**1. O filtro de veículo esconde toda rota agendada.** Resolvida como **(a)**:
assumir e escrever na tela. `vehicleId` mora em `provision`
(`newRouteModal.dart:124`), que só existe em rota concluída, paga ou sem rota —
rota agendada não tem veículo nenhum para comparar. A seção diz isso numa linha
de apoio, com teste (`veiculo-aviso`), em vez de o filtro parecer estar comendo
rotas.

As alternativas ficam registradas para quando alguém quiser voltar ao assunto:
**(b)** um balde "Sem veículo", que mistura "ainda não rodou" com "rodou antes
de haver cadastro"; **(c)** gravar `vehicleId` na rota desde o agendamento, que
é o único caminho que faz o filtro significar o que parece significar — e é
campo novo em documento existente, com decisão de backfill à parte.

**2. A faixa de valor conta a ida Sem Rota pelo líquido.** Confirmado. Uma ida
de R$ 250 bruto entra na faixa como R$ 100, que é o que `value` guarda e o que
faz o resto do app somar certo (`docs/specs/sem-rota.md`).

**3. Período na lista abre em "Todo o período".** Confirmado — abrir já
filtrando esconderia rota sem o usuário ter pedido.

## Plano

Quatro blocos, nesta ordem, porque cada um só depende do anterior:

1. **As duas bases puras** (`periodPreset.dart`, `routeFilter.dart`) com os
   testes unitários. Nada de UI. É onde mora todo o risco de lógica — semana
   que vira o mês, "vazio ou completo", ordem que não reordena — e é o único
   bloco que dá para provar sem aparelho.
2. **O trilho múltiplo** (`SegmentedSelector` + `CompanyFilter` + a lista).
   Entrega sozinho a metade mais pedida da mudança, e o app fica utilizável
   entre um bloco e outro.
3. **A folha de filtros.** O bloco maior: cinco seções, o badge, o estado vazio
   novo e a ordenação.
4. **O seletor de período**, nas duas telas de uma vez — o widget é o mesmo, e
   entregar em duas etapas deixaria o app com dois seletores diferentes no
   meio do caminho, que é justamente o que a resposta ao spec descartou.

Risco maior, e onde eu paro para conferir: o bloco 3 é o único que pode ficar
grande demais para uma folha de fundo em tela de celular. Se as cinco seções
não couberem com conforto, a saída é a folha rolar, nunca cortar seção.

Ponto de verificação entre blocos: `flutter analyze` limpo e `flutter test`
verde. Ponto de verificação no fim dos blocos 2, 3 e 4: rodar no aparelho.

## Tarefas

- [x] **T1** `lib/Utils/periodPreset.dart` — enum, `rangeOf`, `label`.
  - Aceite: os cinco recortes corretos, com `reference` opcional.
  - Verificar: `flutter test test/unit/periodPreset_test.dart`.
  - Arquivos: `Utils/periodPreset.dart`, `test/unit/periodPreset_test.dart`.

- [x] **T2** `PeriodFilter.currentMonth` passa a delegar para `rangeOf`.
  - Aceite: `periodLabel` e seu teste seguem passando sem alteração.
  - Verificar: `flutter test test/unit/periodLabel_test.dart`.
  - Arquivos: `widget/periodFilter.dart`.

- [x] **T3** `lib/Utils/routeFilter.dart` — `RouteFilter`, `RouteOrder`,
      `applyFilter`, `extraCount`.
  - Aceite: vazio/completo passam tudo; eixos cruzam com E; `pertoDeHoje`
    devolve a lista intacta.
  - Verificar: `flutter test test/unit/routeFilter_test.dart`.
  - Arquivos: `Utils/routeFilter.dart`, `test/unit/routeFilter_test.dart`.

- [x] **T4** `SegmentedSelector` ganha modo múltipla escolha.
  - Aceite: o construtor atual não muda de assinatura nem de comportamento; o
    teste de escolha única passa sem edição.
  - Verificar: `flutter test test/widget/segmentedSelector_test.dart`.
  - Arquivos: `widget/segmentedSelector.dart`, o teste.

- [x] **T5** `CompanyFilter` passa a `Set<Company>` e perde o "Todas".
  - Aceite: tocar em marcado desmarca só ele.
  - Verificar: `flutter test test/widget/companyFilter_test.dart`.
  - Arquivos: `widget/companyFilter.dart`, o teste (reescrito).

- [x] **T6** `listIterScreen` usa o filtro novo e o estado vazio novo.
  - Aceite: some o `_companyFilter!`; "Limpar filtros" volta a mostrar a lista.
  - Verificar: `flutter analyze lib/` + aparelho.
  - Arquivos: `screens/listIterScreen.dart`.

- [x] **T7** `lib/widget/routeFilterSheet.dart` — as cinco seções, Limpar e
      Aplicar.
  - Aceite: descartar devolve `null`; `min == max` não desenha a faixa.
  - Verificar: `flutter test test/widget/routeFilterSheet_test.dart`.
  - Arquivos: `widget/routeFilterSheet.dart`, o teste.

- [x] **T8** O `IconButton` com badge, ligado à folha.
  - Aceite: badge conta eixos, não opções; some sem filtro extra.
  - Verificar: aparelho.
  - Arquivos: `screens/listIterScreen.dart`.

- [x] **T9** `lib/widget/periodPresetFilter.dart` — chips roláveis + as datas
      só no Personalizado.
  - Aceite: as roletas não estão na árvore fora do Personalizado.
  - Verificar: `flutter test test/widget/periodPresetFilter_test.dart`.
  - Arquivos: `widget/periodPresetFilter.dart`, o teste.

- [x] **T10** `graficsScreen` e `summaryScreen` passam a usar o seletor novo.
  - Aceite: as duas abrem em Este Mês; o rótulo "AGOSTO 2026" do Resumo segue.
  - Verificar: `flutter test` + aparelho.
  - Arquivos: `screens/graficsScreen.dart`, `screens/summaryScreen.dart`.

- [x] **T11** Atualizar `docs/specs/lista-iter.md` (a Decisão 3 e o "Fora de
      escopo: filtro por status" deixaram de valer) e `docs/specs/graficos.md`.
  - Aceite: nenhuma spec descrevendo comportamento que não existe mais.
  - Arquivos: as duas specs, e `CLAUDE.md` se alguma regra merecer registro.

## Fora de escopo

Persistir o filtro entre sessões do app (exige dependência nova); filtrar por
bairro, clima ou insucesso; filtro de empresa nos Gráficos e no Resumo; salvar
combinações de filtro como atalho; paginação da lista — que continua baixando
a coleção inteira, pela razão registrada em `lista-iter.md`.
