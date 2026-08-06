# Spec: Consumo real em km/l

Status: **concluída** · Criada, aprovada e implementada em 2026-08-06 ·
Verificada no iPhone do Wesley em 2026-08-06

## Objetivo

Transformar o hodômetro que já é gravado em cada abastecimento no **consumo
medido** do veículo — e oferecer trocar por ele o `10 km/l` que hoje está no
cadastro porque alguém digitou uma vez.

Usuário: o entregador. Sucesso = ele abre "Meus veículos" e vê
`10,0 km/l cadastrado · 10,96 km/l medido`, e decide se corrige.

### Por que isto fecha um ciclo

`cadastro-veiculo.md` registrou o consumo como **impossível de obter**: nenhuma
API brasileira tem esse dado, o INMETRO publica PDF, e as APIs que têm consumo
cobrem o mercado americano. A saída documentada foi: *"quando a tela de
Abastecimento existir, o app passa a calcular o consumo real"*.

A tela existe, o hodômetro está sendo gravado desde a tarefa 6 daquela spec, e
o consumo é o último dos três números do veículo que ainda é chute:

| número | como estava | quem corrigiu |
|---|---|---|
| Preço do litro | digitado | `abastecimento.md` |
| Preço da peça | digitado | `manutencao.md` |
| **Consumo km/l** | **digitado** | **esta spec** |

Com os três medidos, o `R$ 0,8193/km` da provisão deixa de ser estimativa e
passa a ser o custo real dele.

## A conta

Média acumulada, sem campo novo — funciona com o que já está gravado.

```
abast. 1   KM 128.000   40 L        ← este abasteceu a distância ANTERIOR
abast. 2   KM 128.400   35 L
abast. 3   KM 128.800   38 L

distância = 128.800 − 128.000 = 800 km
litros    = 35 + 38            =  73 L     (exclui o primeiro)
consumo   = 800 ÷ 73           = 10,96 km/l
```

**O primeiro abastecimento não entra nos litros.** Ele encheu o tanque que
rodou a distância *anterior* à janela; contá-lo faria o consumo parecer pior do
que é.

### O erro, e por que ele encolhe

A conta assume que o tanque estava no **mesmo nível** no primeiro e no último
abastecimento. Não é garantido — foi por isso que o checkbox "enchi o tanque"
esteve em cima da mesa e ficou de fora.

O erro é limitado pela diferença de nível entre as duas pontas, no máximo um
tanque. Como o denominador cresce a cada abastecimento, ele **encolhe sozinho**:

| abastecimentos | litros acumulados | erro máximo aprox. |
|---|---|---|
| 3 | ~75 L | ~15% |
| 5 | ~150 L | ~10% |
| 20 | ~700 L | ~2% |

Por isso o número **aparece** com 2 registros mas só é **oferecido ao cadastro**
com 3 ou mais: mostrar cedo ajuda, mudar a provisão de toda rota futura com uma
leitura só, não.

## ⚠️ O caso que faria o número mentir para melhor

Litros é campo opcional. Se um abastecimento **dentro da janela** não informar
litros, aquele combustível entrou no tanque e não entra na conta — e o consumo
sai **melhor do que é**.

Um km/l inflado significa provisão de gasolina menor, e portanto **lucro
superestimado** em toda rota. É o lado que engana, e o mesmo que já guiou o
custo por km e o preço médio do litro.

Então: **abastecimento sem litros dentro da janela invalida a janela**. O app
diz o que falta em vez de mostrar um número bonito e errado.

## Separado por combustível

O Fit é flex, e etanol roda cerca de 30% menos por litro. Uma média única
ficaria entre os dois e não descreveria nenhum.

`measuredEconomy` devolve **um resultado por combustível**. De quebra, isso
responde uma pergunta que ele faz na bomba: *com o preço de hoje, qual sai mais
barato por quilômetro?* — que é `preço do litro ÷ km/l` de cada um.

## Quando não dá

Cada caso tem uma frase própria, porque cada um se resolve de um jeito:

| situação | o que a tela diz |
|---|---|
| Nenhum abastecimento com KM | "Informe o KM do painel para o app calcular seu consumo." |
| Só um com KM | "Informe o KM em mais 1 abastecimento." |
| Abastecimento sem litros na janela | "Um abastecimento do período está sem litros — informe para o cálculo fechar." |
| Hodômetro não avança | "O KM informado não avança entre os abastecimentos." |

O último cobre erro de digitação (`128.800` virando `12.880`) e troca de
veículo. Sem essa guarda a divisão daria negativo ou infinito.

## Onde aparece

**Card do veículo** — consumo de **toda a vida**, ao lado do custo por km:

```
┌──────────────────────────────────────┐
│ [img] Fiorino do trabalho   ● EM USO │
│       Fiat Fiorino 1.4 · 2020        │
│       R$ 0,8193/km                   │
│       10,0 km/l cadastrado           │
│       10,96 km/l medido  (gasolina)  │
└──────────────────────────────────────┘
```

**Tela de abastecimento** — depois de salvar, o consumo daquele intervalo, e a
pergunta de atualizar o cadastro quando couber.

**Card de gastos do Resumo** — consumo **do período**, junto do preço médio do
litro que já está lá. Período e vida inteira são números diferentes de
propósito: um responde "como foi este mês", o outro "quanto meu carro faz".

## Modelo

**Nenhum campo novo no Firestore.** Tudo sai de `Supply.odometer` e
`Supply.liters`, que já existem.

```dart
/// Consumo medido de um combustível.
typedef FuelEconomy = ({
  SupplyFuel fuel,
  double kmPerLiter,
  double km,
  double liters,
  int fills,        // quantos abastecimentos sustentam o número
});

/// Por que ainda não dá.
enum EconomyGap { semKm, faltamRegistros, litrosFaltando, kmNaoAvanca }

typedef EconomyResult = ({
  FuelEconomy? economy,
  EconomyGap? gap,
  int missing,      // quantos registros com KM ainda faltam
});

/// Um resultado por combustível, do veículo pedido.
Map<SupplyFuel, EconomyResult> measuredEconomy(
  List<Supply> supplies, {
  required String vehicleId,
});
```

## Oferecer ao cadastro

Em `Utils/expenseRules.dart`, ao lado das outras duas — é a mesma pergunta
("este gasto deve corrigir o veículo?") pela terceira vez.

```dart
bool shouldOfferConsumptionUpdate(Vehicle? vehicle, FuelEconomy economy);
```

Não oferece quando: não há veículo; menos de **3** abastecimentos sustentam o
número; o veículo não é flex e o combustível é outro; ou o valor já é
praticamente o mesmo.

Em veículo flex, oferece para os dois — só o motorista sabe qual dos dois o
`consumption` dele representa, e o diálogo mostra qual foi:

```
10,96 km/l medido com gasolina
O Fit está com 10,0 km/l. Atualizar?
Isso muda o custo por km das próximas rotas.
[ Agora não ]  [ Atualizar ]
```

**Nunca automático**, como as outras duas.

## Estrutura

```
lib/Utils/fuelEconomy.dart          → a conta, pura (novo)
lib/Utils/expenseRules.dart         → + shouldOfferConsumptionUpdate
lib/screens/addSupply.dart          → mostra e oferece depois de salvar
lib/widget/vehicleCard.dart         → consumo de toda a vida
lib/screens/vehiclesScreen.dart     → stream de abastecimentos para o card
lib/widget/expenseCard.dart         → consumo do período
lib/screens/summaryScreen.dart      → passa os abastecimentos ao card
test/unit/fuelEconomy_test.dart     → (novo)
```

## Estratégia de teste

`test/unit/fuelEconomy_test.dart` — o coração:

- **o teste âncora**: 128.000/40 L, 128.400/35 L, 128.800/38 L → **10,96 km/l**,
  com `km: 800`, `liters: 73`, `fills: 3`;
- o primeiro abastecimento **não** entra nos litros;
- dois registros bastam para haver número;
- um só devolve `faltamRegistros` com `missing: 1`;
- nenhum com KM devolve `semKm` com `missing: 2`;
- **abastecimento sem litros na janela invalida** — `litrosFaltando`, e não um
  número inflado;
- abastecimento sem litros **fora** da janela não atrapalha;
- hodômetro igual ou decrescente devolve `kmNaoAvanca`, nunca infinito nem
  negativo;
- gasolina e etanol saem **separados**, cada um com os próprios litros;
- abastecimento de outro veículo não entra;
- abastecimento sem `vehicleId` não entra;
- lista vazia não lança.

`shouldOfferConsumptionUpdate` (em `expenseRules_test.dart`):

- 3 registros oferece, 2 não;
- veículo não-flex com outro combustível não oferece;
- flex oferece para gasolina e para etanol;
- valor praticamente igual não incomoda;
- sem veículo não oferece.

Os widgets ganham casos de exibição e de cada `EconomyGap`.

## Fronteiras

- **Sempre:** conta em `Utils/`, nunca no `build`; `null` para "não dá para
  calcular"; texto em pt-BR.
- **Perguntar antes:** qualquer campo novo no Firestore; qualquer dependência.
- **Nunca:** mostrar consumo com abastecimento sem litros dentro da janela;
  atualizar `Vehicle.consumption` sem o usuário mandar; misturar combustíveis
  num número só.

## Critérios de sucesso

- [x] Com 3 abastecimentos do exemplo, o app mostra **10,96 km/l**.
- [x] O card do veículo mostra cadastrado e medido lado a lado.
- [x] Gasolina e etanol aparecem separados num veículo flex.
- [x] Abastecimento sem litros na janela **impede** o número e diz o porquê.
- [x] Hodômetro que não avança não vira número.
- [x] Com 3 ou mais registros, salvar um abastecimento oferece atualizar o
      cadastro; com 2, não.
- [x] Aceitar muda o custo por km do veículo — e **não** muda o lucro de
      nenhuma rota já concluída.
- [x] `flutter analyze lib/` sem error/warning novo; 639 testes passando
      (`widget_test.dart`, o template do contador, segue quebrado).

## Decisões

**1. Média acumulada, sem campo novo.** Funciona com o que já está gravado e o
erro encolhe sozinho. O checkbox "enchi o tanque" daria exatidão desde o
segundo registro, mas cobra um toque em todo abastecimento — e o app é usado
depois de um dia de trabalho.

**2. Mostrar com 2, oferecer com 3.** Ver o número cedo ajuda; mudar a provisão
de toda rota futura com base numa leitura só, não.

**3. Sem litros invalida a janela.** Um km/l inflado vira provisão menor e lucro
superestimado. Não mostrar é melhor que mostrar bonito e errado.

**4. Separado por combustível.** Etanol roda ~30% menos; a média única não
descreveria nenhum dos dois.

**5. Vida inteira no veículo, período no Resumo.** São perguntas diferentes:
"quanto meu carro faz" e "como foi este mês".

## Dívidas e fora de escopo

- **Checkbox "enchi o tanque"** — ver decisão 1. Entra se a imprecisão
  incomodar.
- **Lembrete de manutenção por KM** — usa o hodômetro da *manutenção*, é outra
  spec.
- **Qual combustível compensa hoje** (`preço ÷ km/l` dos dois) — o dado passa a
  existir aqui, mas a tela que compara é outra entrega.
- **Consumo por rota** — exigiria abastecer sempre no mesmo ponto do trajeto.
- **Gráfico de consumo ao longo do tempo.**

## Perguntas em aberto

Nenhuma bloqueante. Método, separação por combustível, onde aparece e o que
mostrar sem dado foram respondidos antes desta spec.

---

# Tarefas

- [x] **1. `Utils/fuelEconomy.dart` — a conta, teste primeiro** — 18 testes,
  âncora batendo: `800 km ÷ 73 L = 10,96 km/l`.
  - A monotonicidade do hodômetro é checada em **todos** os registros, não só
    nas pontas. O erro de digitação no meio (`12.880` em vez de `128.800`)
    deixaria as pontas fechando e o dado errado passando — agora vira
    `kmNaoAvanca`.
  - Combustível sem abastecimento nenhum **não entra no mapa**: "Etanol:
    informe o KM" para quem nunca abasteceu etanol é ruído.
  - Um teste afirma o que a separação por combustível evita: com gasolina a
    11,43 e etanol a 8,00, a média única daria 9,41 — que não descreve nenhum
    dos dois. O teste usa `isNot` contra esse valor.
  - Verificar: `flutter test test/unit/fuelEconomy_test.dart`

- [x] **2. `shouldOfferConsumptionUpdate` em `expenseRules.dart`** — 9 testes;
  os 18 das outras duas regras seguem passando.
  - `expenseRules.dart` fecha as três frentes: preço do litro, preço da peça e
    consumo. As três respondem a mesma pergunta e têm a mesma resposta padrão —
    **nunca decidir sozinho**, porque as três mudam o custo por km de toda rota
    futura.
  - `_minimumFills = 3` é a única diferença de comportamento entre elas: as
    outras duas medem um fato único (o que ele pagou), esta é uma média que
    precisa de amostra.
  - Aceite: os cinco casos listados, mais o de combustível único aceitando o
    próprio líquido e o de consumo zerado.
  - Verificar: `flutter test test/unit/expenseRules_test.dart`

- [x] **3. `addSupply.dart` — mostrar e oferecer** — 5 testes novos em
  `fuelEconomy_test.dart` (frases e formatação).
  - **Um diálogo para os dois números, não dois em sequência.** Preço do litro
    e consumo saem do mesmo abastecimento e respondem a mesma pergunta — "o
    cadastro está desatualizado?". Dois modais empilhados depois de salvar seria
    atrito onde deveria haver alívio. `_offerPriceUpdate` virou
    `_offerVehicleUpdate`.
  - Ao aceitar, `fuelPrice: price ?? vehicle.fuelPrice` — aceitar **não pode
    apagar** o campo que não foi oferecido naquela vez.
  - A dica do que falta só aparece quando ele **informou o KM** desta vez. Quem
    não usa o campo não precisa ser cobrado a cada abastecimento.
  - São quatro `EconomyGap` e **três frases**: `semKm` e `faltamRegistros`
    pedem a mesma coisa e diferem só na contagem. O teste afirma isso
    explicitamente — a primeira versão dele exigia quatro distintas e reprovou
    um comportamento correto.
  - Verificar: `flutter test test/unit/fuelEconomy_test.dart` e
    `flutter build apk --debug`

- [x] **4. `vehicleCard.dart` + `vehiclesScreen.dart` — consumo de toda a vida**
  — 9 testes novos.
  - `consumptionLine` é função pura, testada: `10,00 km/l no cadastro · 10,96
    medido`. Com **um** combustível o nome dele não aparece — seria repetição
    do óbvio; com **dois**, cada um é nomeado.
  - A dica "informe o KM" só aparece quando **não há consumo cadastrado**. Quem
    já configurou um valor não precisa de dica ocupando a linha do número.
  - `SupplyController.fetchAll` e não `watchAll`: o consumo medido só muda
    quando um abastecimento é registrado, o que acontece em **outra tela**.
    Listener permanente numa tela que se abre para trocar de carro seria escuta
    parada.
  - Falhar ao ler os abastecimentos **não** derruba a lista: os cards aparecem
    inteiros, só sem a linha de consumo.
  - Verificar: `flutter test test/widget/vehicleCard_test.dart` e
    `flutter build apk --debug`

- [x] **5. `expenseCard.dart` + `summaryScreen.dart` — consumo do período**
  — 4 testes novos no card, 4 em `fuelEconomy`.
  - `periodEconomy` devolve `null` quando os abastecimentos do período **não
    são todos do mesmo veículo** — incluindo o caso de algum estar sem
    `vehicleId`. Um mês com Fiorino e moto renderia um km/l que não descreve
    nenhum dos dois; e um registro sem carro é a mesma incerteza que a falta de
    litros, com a diferença de que aqui ela passaria despercebida.
  - Entra **no fim** da linha de contexto, depois do preço médio: `2
    abastecimentos · 72,5 L · R$ 5,9379/L · 10,96 km/l`. Com dois combustíveis
    cada um é nomeado, como no card do veículo.
  - Não medir **não** vira cobrança aqui. A dica "informe o KM" mora no card do
    veículo, que é onde ele resolve isso; repetir no Resumo seria pedir a mesma
    coisa duas vezes na mesma sessão.
  - Vida inteira lá, período aqui — a decisão 5 do "Decidido pelo caminho". O
    card do veículo responde "quanto meu carro faz"; este responde "como foi
    este mês".
  - Verificar: `flutter test test/widget/expenseCard_test.dart`

- [x] **6. Verificação no aparelho** — feita pelo Wesley em 06/08/2026, no
  iPhone. Confirmado item a item:
  - O consumo medido apareceu **no terceiro** abastecimento e não antes —
    `_minimumFills` fazendo o que devia. Com dois registros o número seria uma
    janela só, e um dia de mão pesada viraria "o carro faz 8 km/l".
  - O número foi **10,96 km/l**, exatamente o do exemplo da spec.
  - O preço do litro foi oferecido em todo abastecimento, o consumo só quando
    mudou mais que 0,05 km/l. Cadências diferentes de propósito: o preço muda
    de posto para posto, o consumo é uma medição que só se refina.
  - **O pilar: nenhuma rota já concluída mudou de lucro** depois de aceitar a
    correção. A provisão continuou congelada, que é a razão de o app existir.

  Fica registrado o que **não** é bug e pode incomodar um dia: o preço proposto
  é o do **último** abastecimento, não a média. Um abastecimento caro propõe
  aquele preço. Foi a decisão da spec do abastecimento — o app mostra e o dono
  decide —, e trocar pela média ponderada é um ajuste pequeno, porque
  `averagePricePerLiter` já existe.
