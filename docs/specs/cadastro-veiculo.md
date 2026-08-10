# Spec: Cadastro de Veículo e Provisão por Rota

Status: **concluída** · Criada, aprovada e implementada em 2026-08-05 ·
Verificada em aparelho em 2026-08-06

## Objetivo

Cadastrar os veículos do entregador e, com eles, os parâmetros de custo que
transformam **KM rodado** em **provisão gravada na rota** — reproduzindo a aba
de `Gastos` da planilha `Entregas.xlsx`, que hoje é onde essa conta vive.

O acesso é um `IconButton` na `AppBar`, antes do "Sair". Sem veículo cadastrado
ele é um ícone de carro; com veículo ativo, é a imagem do próprio carro no
tamanho de ícone.

Usuário: o entregador. Sucesso = ele cadastra o carro uma vez e, a partir daí,
toda rota concluída sai com a provisão e o lucro real dentro dela — números que
hoje só existem dentro de uma célula do Excel.

### Por que esta tela existe

Ela não é um cadastro por si. É a **entrada de dados** de uma conta que roda
toda vez que uma rota é concluída:

```
                 ┌── cadastro de veículo (esta tela) ──┐
                 │  R$ 7,00/L ÷ 10 km/l  = 0,700/km    │
                 │  R$ 200 ÷ 10.000 km   = 0,020/km    │
                 │  …                                   │
                 └──────────────┬───────────────────────┘
                                │ taxa R$/km
                                ▼
rota concluída ──→ KM rodado × taxa ──→ provisão GRAVADA na rota
 (kmFinal−kmInitial)                     └─→ lucro = valor − gasolina − peças
   já existe hoje                             aparece no card da rota
```

`kmInitial` e `kmFinal` **já existem** em `NewRouteModal` e já são preenchidos
em `addIter.dart` — o KM rodado já está gravado em toda rota. O que falta é o
outro lado da multiplicação, e é isso que esta entrega traz.

Os campos desta tela existem **só** para alimentar esse cálculo. Nada de placa,
cor ou valor FIPE: não entram em conta nenhuma e por isso ficam de fora.

## A planilha, decodificada

Bloco `V8:Z15` da aba JUL (idêntico em ABR, MAI e JUN — as taxas nunca mudaram):

| Gastos | Parâmetro | Preço | KM | Fórmula real na planilha |
|---|---|---|---|---|
| Gasolina | 0,700 | R$ 7,00 | 10 | `=X9/Y9` |
| P. Óleo | 0,020 | R$ 200,00 | 10 000 | `=X10/Y10` |
| P. Pneu | 0,040 | R$ 500,00 | 50 000 | `=(X11/Y11)*4` |
| P. Bateria | 0,0133 | R$ 800,00 | 60 000 | `=X12/Y12` |
| P. Freio | 0,016 | R$ 200,00 | 50 000 | `=(X13/Y13)*4` |
| P. Geral | 0,03 | — | — | valor digitado |

O raciocínio é o do dono da planilha, e a implementação é literalmente ele:
*custo real da peça ÷ quilômetros que ela dura*. Óleo e filtro custam R$ 200 e
duram 10 000 km, então cada quilômetro consome R$ 0,02 — rodou 20 km, provisionou
R$ 0,40. Nunca uma fração do ganho, sempre o preço real dividido pela vida útil.

Quatro fatos que só apareceram ao abrir o arquivo, e que a spec inteira depende:

**1. É uma fórmula só para todas as linhas.** `taxa = preço ÷ vida`. A Gasolina
não é um caso especial: o "KM" dela (10) é o **consumo km/l** e o "Preço" (7,00)
é o litro. Óleo é R$ 200 a cada 10 000 km. Mesma conta.

**2. Pneu e Freio multiplicam por 4** — está explícito na fórmula, `*4`. São as
quatro rodas. Por isso o app pede **quantidade**: você informa "pneu R$ 500,
dura 50 000 km, são 4" e a taxa 0,040 sai sozinha, sem você multiplicar de
cabeça. Sem esse campo, `500 ÷ 50 000 = 0,01` — quatro vezes menos do que você
provisiona hoje.

**3. `Total P.` (coluna L) soma só as peças.** `=SUM(G3:K3)`, de Óleo a Geral. A
gasolina fica **fora** e é subtraída à parte no lucro: `O3 = C3 − F3 − L3`.
Somar a gasolina dentro da provisão daria o mesmo total, mas quebraria a
distinção entre "combustível" e "provisão" que a sua tabela por plataforma
(coluna `Provisão`, `=SUMIF($M:$M,$V3,$L:$L)`) usa.

**4. Sem KM não provisiona.** Toda linha é `IF(AND($C3>0,$D3>0), …, 0)`. Rota
sem valor ou sem KM rodado não gera custo nenhum — não é zero por acaso, é
regra. A linha 7 de JUL (domingo, sem rota) é exatamente esse caso.

Conferência do total: `0,700 + 0,020 + 0,040 + 0,013̅3 + 0,016 + 0,03 =
R$ 0,8193̅/km`, × 898,1 km = **R$ 735,84** — bate com `X15` até o último decimal.
Esse é o teste de aceite do módulo de cálculo.

## A provisão na rota

Este é o coração da entrega e o que mudou depois da primeira versão da spec.

### Quando é calculada

Quando a rota é salva **e ela rodou**. Rota `agendado` ou `andamento` não tem
provisão — ela ainda não rodou, e não há KM para multiplicar.

> Desde `sem-rota.md`, "rodou" são **três** status e não dois: `concluido`,
> `pago` e `semRota`. A regra virou o getter `NewRouteModal.hasRun`, porque
> estava escrita em três arquivos e a cópia de `addIter._withProvision` roda
> primeiro. A ida ao CD queimou gasolina de verdade — provisiona como qualquer
> outra. Leia `concluido`/`pago` como `hasRun` na tabela abaixo.

### É um retrato, não uma fórmula

O que fica gravado são **valores em reais já calculados**, não a taxa. Isso tem
uma consequência que precisa estar clara antes de aprovar:

> Se em setembro o pneu subir para R$ 700, o lucro de julho **não muda**.

**Isso é diferente da sua planilha — e é um dos motivos de o app existir.** Lá,
as colunas F..K são fórmulas apontando para o bloco de parâmetros do mês; editar
o preço do pneu recalcula todas as linhas daquela aba na hora, reescrevendo o
lucro de dias que já aconteceram. A planilha não guarda o custo de julho, ela
recalcula julho com o preço de hoje toda vez que é aberta — e isso está errado.

Aqui, cada rota carrega o custo que era verdade no dia em que ela foi concluída.
Julho foi rodado com pneu de R$ 500, e o lucro de julho conta pneu de R$ 500 para
sempre. Quem quiser refazer a conta tem o botão **"recalcular provisão"** na
rota — sob comando, nunca de surpresa.

É por isso que o campo `provision` guarda **valores em reais**, e não o
`vehicleId` com a taxa para multiplicar depois: taxa guardada é taxa que alguém
edita. Só o valor congelado é imune.

### Regra exata de escrita

No salvamento, com o status resolvido:

| situação | o que acontece com `provision` |
|---|---|
| status vira `agendado` ou `andamento` | apagada — a rota voltou a não ter rodado |
| `concluido`/`pago`, sem provisão ainda | **calcula agora** |
| `concluido`/`pago`, já tinha, mesmo KM e mesmo veículo | **mantém** a antiga (é o retrato) |
| `concluido`/`pago`, já tinha, KM ou veículo mudou | **recalcula** — o retrato antigo virou mentira |
| sem veículo ativo cadastrado | fica `null` + aviso na tela |
| KM rodado ≤ 0 ou valor ≤ 0 | fica `null` (a guarda da planilha) |

A terceira linha é a que preserva o histórico: corrigir o endereço de uma rota
de junho não pode reescrever a provisão dela com o preço de gasolina de hoje.

### O que fica gravado

```dart
/// Provisão de uma rota, congelada no momento em que ela foi concluída.
class RouteProvision {
  final String vehicleId;            // qual veículo rodou
  final double km;                   // kmFinal − kmInitial, o que foi usado
  final double fuel;                 // coluna F da planilha
  final Map<String, double> parts;   // colunas G..K, peça a peça
  final double totalParts;           // coluna L — SEM a gasolina
  final String calculatedAt;         // ISO 8601
}
```

Em `iter/{uid}/routes/{id}`, como mapa aninhado em `provision`. Ausente nas
rotas antigas e nas não concluídas — `fromMap` devolve `null` sem reclamar,
igual ao que `insucessoPorBairro` já faz com documento antigo.

**`profit` não é gravado.** `value − fuel − totalParts` é derivável em uma linha,
e valor derivado gravado é valor que uma hora discorda da sua origem. A planilha
guarda a coluna O porque em planilha tudo é célula; aqui é um getter.

`parts` guarda o nome da peça junto: se você renomear "Freio" para "Pastilha" no
veículo amanhã, a rota de julho continua sabendo que aqueles R$ 0,75 eram de
freio.

### Onde aparece

No card da rota já expandido, ao lado do que ele mostra hoje:

```
┌────────────────────────────────────────┐
│ Amazon              01/07/2026    Pago │
│ R$ 152,50                     46,9 km  │
│ ────────────────────────────────────── │
│ Gasolina    R$ 32,83                   │
│ Provisão    R$  5,60                   │
│ Lucro       R$ 114,07                  │  ← em verde
└────────────────────────────────────────┘
```

Incluí isso por conta própria: gravar um número que ninguém consegue ver não
entrega nada. É pouca coisa (o card expandido já existe), mas se você preferir
deixar a exibição para a spec dos gráficos, é só dizer que eu tiro.

## As APIs — o que existe de graça e o que não existe

Testado endpoint por endpoint, não só lido na documentação.

### ✅ FIPE (`parallelum.com.br/fipe/api/v1`) — marca e modelo

Sem chave, sem cadastro, em pt-BR e com o mercado brasileiro. 500 requisições
por dia sem token (1 000 com token grátis) — folgadíssimo para um app que
consulta só na hora de cadastrar um carro.

```
/carros/marcas                                  → 100+ marcas
/carros/marcas/{marca}/modelos                  → Fiat: 585 modelos
/carros/marcas/{marca}/modelos/{modelo}/anos    → anos disponíveis
/motos/…                                        → mesma árvore para motos
```

É o que resolve o "não quero que ele escreva qual é o carro". **585 modelos por
marca exige campo de busca** — um `DropdownButton` com essa lista é inutilizável.

O endpoint de preço FIPE existe e é grátis, mas **não é usado**: o valor do carro
não entra em nenhuma conta desta spec.

### ❌ Consumo (km/l) — não existe API grátis para o Brasil

A única fonte oficial é a tabela PBE Veicular do INMETRO, publicada em **PDF e
XLS, sem API**. As APIs que têm consumo (EPA FuelEconomy, API Ninjas) cobrem o
mercado americano: Onix, HB20, Strada e Fiorino não estão nelas.

Decisão: **o campo é digitado**, e já vem com o seu `10` km/l como sugestão.
Quando a tela de Abastecimento existir (já está no menu "+" marcada como "Em
breve"), o app passa a calcular o consumo **real** pelos abastecimentos — que
vale mais que qualquer tabela, porque considera o seu trânsito e o seu pé.

### ⚠️ Imagem (`cdn.imagin.studio`) — funciona, com três ressalvas

Render 3D sem chave. Testei 17 veículos de entrega (Fiorino, Strada, Doblo,
Toro, Saveiro, Gol, Onix, Montana, HB20, Kwid, Kangoo, Partner, Berlingo, Uno,
Hilux) — **todos** devolveram imagem.

| Ressalva | Evidência | Mitigação nesta spec |
|---|---|---|
| Marca d'água | `customer=img` é o demo: "IMAGIN studio" atravessa a imagem | Aceita; some no ícone de 32 px da `AppBar`, incomoda só no cabeçalho do formulário |
| Licença proprietária | Exige licença paga; o contrato proíbe baixar, cachear e modificar | **A URL é montada e exibida, nunca salva em bytes.** Publicar na loja exige licença — registrado em Dívidas |
| **Devolve o carro errado calado** | Pedi `honda/cg` (moto) e veio `found=true` resolvendo para **Honda Pilot**, um SUV | O usuário confirma: "É esse o seu carro? / Usar outra foto" |

A terceira é a séria, e é o mesmo padrão do bug do clima que o `CLAUDE.md`
documenta: "não achei" e "achei" desenhando a mesma coisa. O header
`x-imaginstudio-request-found` **não basta** como filtro — o Pilot veio com
`true`. Quem valida é o olho do usuário, e é por isso que a confirmação não é
enfeite.

Motos a imagin não cobre: o cadastro de moto vai direto para foto própria ou
ícone.

## Layout

```
AppBar ──────────────────────────────────────────┐
│ (avatar) Olá, Wesley | @wesley    [🚗] [Sair]  │  ← sem veículo: ícone de carro
│                                   [(碗)] [Sair] │  ← com veículo: a imagem dele
└────────────────────────────────────────────────┘
                    │ toque
                    ▼
┌── Meus veículos ──────────────────────────────┐
│  ┌──────────────────────────────────────────┐ │
│  │ [img] Fiorino do trabalho      ● ATIVO   │ │  ← toque = torna ativo
│  │       Fiat Fiorino 1.4 · 2020            │ │
│  │       R$ 0,8193/km                       │ │
│  └──────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────┐ │
│  │ [img] Biz                                │ │  ← arrasta = excluir
│  │       Honda Biz 125 · 2019               │ │
│  │       R$ 0,1120/km                       │ │
│  └──────────────────────────────────────────┘ │
│                                        [ + ]  │
└───────────────────────────────────────────────┘
                    │ + ou toque para editar
                    ▼
┌── Novo veículo ───────────────────────────────┐
│         ╭────────────────────────╮            │
│         │   imagem do veículo    │            │  ← render, foto ou silhueta
│         ╰────────────────────────╯            │
│          É esse o seu carro?                  │  ← só quando veio da imagin
│          [ Sim ]   [ Usar minha foto ]        │
│                                               │
│  Tipo      ( • Carro )  ( ○ Moto )            │
│  Marca     [ Fiat                        ▾ ]  │  ← abre busca (FIPE)
│  Modelo    [ Fiorino Endurance 1.4       ▾ ]  │  ← 585 itens: com busca
│  Ano       [ 2020 Flex                   ▾ ]  │
│  Apelido   [ Fiorino do trabalho          ]   │  ← p/ diferenciar na troca
│                                               │
│  ── Combustível ────────────────────────────  │
│  Tipo      [ Flex ▾ ]  Preço/L [ R$ 7,00  ]   │
│  Consumo   [ 10,0 km/l ]        → R$ 0,700/km │
│                                               │
│  ── Provisão de peças ──────────────────────  │
│  Peça      Preço      Dura(km)  Qtd    R$/km  │
│  Óleo      R$ 200,00   10.000    1     0,0200 │
│  Pneu      R$ 500,00   50.000    4     0,0400 │
│  Bateria   R$ 800,00   60.000    1     0,0133 │
│  Freio     R$ 200,00   50.000    4     0,0160 │
│  Geral     — taxa direta —             0,0300 │
│                                    [+ peça]   │
│                                               │
│  ╔═══════════════════════════════════════════╗│
│  ║ Custo total     R$ 0,8193 / km            ║│  ← atualiza ao digitar
│  ║ Numa rota de 46,9 km → R$ 38,43           ║│
│  ╚═══════════════════════════════════════════╝│
│                        [ SALVAR VEÍCULO ]     │
└───────────────────────────────────────────────┘
```

O rodapé com o custo total é o que fecha o ciclo: você digita e vê na hora se
bateu com a planilha.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1 · cloud_firestore 6.7.1 · firebase_auth 6.5.6 ·
http 1.6.0 (já usado pelo OpenWeather).

**Uma dependência nova: `image_picker`.** Necessária para o "Usar minha foto".
Não precisa de pacote de redimensionamento: o próprio `image_picker` aceita
`maxWidth` e `imageQuality`, o que já resolve o tamanho.

**Sem Firebase Storage.** A foto vai como base64 no próprio documento do
veículo: em `maxWidth: 800, imageQuality: 70` uma foto fica em 40–70 KB, contra
o limite de 1 MB por documento do Firestore. Storage exigiria o plano Blaze, e
um usuário com dois ou três veículos não justifica essa migração. Registrado em
Dívidas para o dia em que justificar.

`setState` e `StreamBuilder`, como no resto do app.

## Comandos

```bash
flutter pub get                                  # depois de somar image_picker
flutter run
flutter analyze lib/                             # sem error/warning novo
flutter test test/unit/vehicleCost_test.dart
flutter test test/unit/routeProvision_test.dart
flutter test test/unit/fipe_test.dart
flutter test test/unit/vehicle_test.dart
flutter test                                     # widget_test.dart segue quebrado (template)
```

## Estrutura

```
lib/model/vehicle.dart                  → Vehicle + MaintenancePart + enums (novo)
lib/Utils/vehicleCost.dart              → a matemática, pura e testável (novo)
lib/Utils/carImage.dart                 → nome FIPE → URL da imagin (novo)
lib/services/fipe.dart                  → marcas / modelos / anos (novo)
lib/controller/vehicleController.dart   → CRUD em iter/{uid}/vehicles (novo)
lib/screens/vehiclesScreen.dart         → lista + trocar o ativo (novo)
lib/screens/addVehicle.dart             → o formulário (novo)
lib/widget/vehicleCard.dart             → card da lista (novo)
lib/widget/vehicleAvatar.dart           → o ícone da AppBar (novo)
lib/widget/fipePicker.dart              → sheet de busca marca/modelo/ano (novo)
lib/widget/partsEditor.dart             → a tabela de peças (novo)
lib/model/newRouteModal.dart            → + RouteProvision
lib/screens/addIter.dart                → grava a provisão ao concluir
lib/widget/routeCard.dart               → mostra gasolina, provisão e lucro
lib/screens/home.dart                   → o IconButton na AppBar
lib/model/users.dart                    → + activeVehicleId
firestore.rules                         → + subcoleção vehicles
```

`Utils/carImage.dart` e não dentro de `services/`: montar uma URL é função pura
de string, testável sem rede — o mesmo critério que separa `Utils/weather.dart`
de `services/openWeather.dart`.

## Dados

### `iter/{uid}/vehicles/{vehicleId}`

Subcoleção irmã de `routes`, no mesmo documento de usuário — mesmo dono, mesma
regra de segurança.

| campo | tipo | por que existe |
|---|---|---|
| `id` | String | `Uuid().v4()` |
| `type` | String | `carro` \| `moto` — decide `/carros` ou `/motos` na FIPE |
| `brandCode` / `brandName` | String | FIPE, como veio (`"VW - VolksWagen"`) |
| `modelCode` / `modelName` | String | FIPE (`"Saveiro Robust 1.6 Flex 8V CD"`) |
| `yearCode` / `year` | String? / int? | FIPE (`"2020-1"` → 2020) |
| `nickname` | String? | diferenciar os veículos na hora de trocar |
| `fuel` | String | `flex` \| `gasolina` \| `etanol` \| `diesel` \| `eletrico` |
| `fuelPrice` | double? | **R$/litro — entra na conta** |
| `consumption` | double? | **km/l — entra na conta** |
| `imageUrl` | String? | URL da imagin, **só a URL** |
| `photoBase64` | String? | foto do usuário, quando escolhida |
| `parts` | List\<Map\> | **as peças — entram na conta** |
| `createdAt` / `updatedAt` | String | ISO 8601, como no resto do app |

Marca, modelo e ano não entram em nenhuma conta — existem para identificar o
veículo na lista e para montar a URL da imagem. `placa`, `cor` e `valor FIPE`
ficaram de fora por não servirem a nem uma coisa nem outra.

`imageUrl` e `photoBase64` são exclusivos: a foto vence quando existe. Não
guardar bytes da imagin é o que mantém o uso dentro do "só da CDN" da licença.

### Peça (dentro de `parts`)

| campo | tipo | exemplo |
|---|---|---|
| `name` | String | `"Pneu"` |
| `price` | double? | `500.0` — **unitário** |
| `lifeKm` | double? | `50000.0` |
| `quantity` | int | `4` |
| `fixedRate` | double? | só a "Geral": `0.03` |

### `iter/{uid}/routes/{routeId}.provision`

Mapa aninhado, ausente em rota antiga e em rota não concluída. Detalhado na
seção "A provisão na rota".

### `user/{uid}.activeVehicleId`

O veículo ativo é **um campo no perfil**, não um booleano em cada veículo.
Trocar de carro vira uma escrita só, atômica por natureza. Um `isActive` por
documento exigiria transação para garantir que só um fica ligado, e um erro no
meio deixaria zero ou dois ativos.

### `firestore.rules`

```
match /iter/{userId}/vehicles/{vehicleId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

Mesma regra das rotas. Nada de novo em segurança.

## O cálculo

`lib/Utils/vehicleCost.dart`, funções puras sobre `Vehicle` e `NewRouteModal`,
sem Firestore e sem `BuildContext`.

```dart
/// Taxa da peça em R$/km. `null` = não dá para calcular, nunca zero.
///
/// `quantity` existe por causa do `*4` que a planilha aplica em pneu e freio:
/// o preço informado é de **uma** peça, e o carro gasta quatro por vez.
double? ratePerKm(MaintenancePart part) {
  if (part.fixedRate != null) return part.fixedRate;      // a "Geral"
  final price = part.price, life = part.lifeKm;
  if (price == null || life == null || life <= 0) return null;
  return price * part.quantity / life;
}
```

| função | conta | espelha |
|---|---|---|
| `fuelRatePerKm(v)` | `fuelPrice ÷ consumption` | `W9 = X9/Y9` |
| `partsRatePerKm(v)` | `Σ ratePerKm(peça)` | `W10:W14` |
| `totalRatePerKm(v)` | fuel + parts | `0,8193̅` |
| `provisionFor(v, rota)` | `RouteProvision?` | colunas F..L |
| `profitOf(rota)` | `value − fuel − totalParts` | coluna O |

**Divisão em zero devolve `null`, nunca infinito.** Consumo 0 km/l e vida 0 km
são dado incompleto, não custo infinito — e um `double.infinity` gravado
contaminaria toda soma que o encontrasse.

**Sem KM ou sem valor, não há provisão.** `IF(AND($C3>0,$D3>0), …, 0)` da
planilha, traduzido para `null` em vez de zero: "não deu para calcular" e "custou
zero" são coisas diferentes, e a segunda não existe numa rota que rodou.

`km` sai de `kmFinal − kmInitial`, com a mesma guarda que `routeCard.dart` já
usa: diferença não positiva é dado incompleto e vale `null`.

## Valores iniciais

O formulário abre com **os seus números**, não com campos vazios:

| | preço | dura | qtd | taxa |
|---|---|---|---|---|
| Gasolina | R$ 7,00/L | 10 km/l | — | 0,700 |
| Óleo | R$ 200,00 | 10 000 | 1 | 0,0200 |
| Pneu | R$ 500,00 | 50 000 | 4 | 0,0400 |
| Bateria | R$ 800,00 | 60 000 | 1 | 0,0133 |
| Freio | R$ 200,00 | 50 000 | 4 | 0,0160 |
| Geral | taxa direta | | | 0,0300 |

Cadastrar um carro e não mexer em nada reproduz a planilha exatamente. Tudo é
editável, e `[+ peça]` adiciona linha nova (correia, embreagem, amortecedor) —
a planilha resolve isso com a "Geral", o app não precisa se limitar a ela.

Moto abre com a mesma lista, mas quantidade 2 em pneu e freio.

## Estilo de código

Modelo com `toMap`/`fromMap` como `NewRouteModal`, enums gravados como string
bare — e a mesma armadilha vale aqui: **renomear um valor de enum quebra os
documentos gravados**, mude os dois lados juntos.

`fromMap` tolerante: peça sem `quantity` assume 1, veículo sem `parts` assume a
lista vazia, rota sem `provision` devolve `null`. Documento fora do formato não
pode derrubar a lista inteira — `VehicleController` faz `try/catch` por
documento e `debugPrint`, como `RouteController._parseAll` já faz.

Widgets em `lib/widget/` como funções de topo quando mostram algo
(`showFipePicker`), classes quando são pedaço de tela (`VehicleCard`,
`VehicleAvatar`). Arquivos em camelCase. Texto de interface em pt-BR.

## Estados

1. **Sem veículo** — o ícone da `AppBar` é um carro; a tela mostra "Cadastre seu
   primeiro veículo para o app calcular o custo das suas rotas" e o botão.
2. **Concluir rota sem veículo cadastrado** — a rota salva normalmente, sem
   provisão, e aparece "Cadastre um veículo para o app calcular a provisão desta
   rota." O salvamento **não** é bloqueado por isso.
3. **FIPE fora do ar / sem rede** — "Não foi possível carregar as marcas.
   Tentar de novo", com botão. O formulário **continua utilizável**: marca e
   modelo aceitam texto digitado como escape. Ficar refém de uma API de
   terceiro para cadastrar o próprio carro é pior do que digitar.
4. **Imagem não encontrada** — a imagin devolve uma silhueta coberta; o app
   mostra o ícone neutro e a pergunta de confirmação **não** aparece.
5. **Imagem encontrada** — render + "É esse o seu carro? / Usar minha foto".
   Enquanto não confirmar, não grava `imageUrl`.
6. **Foto escolhida** — vence a URL; o campo `imageUrl` é limpo.
7. **Taxa incalculável** — `—` na linha e a peça **não entra** na soma. Nunca
   `0,00`, nunca infinito.
8. **Rota concluída sem KM** — sem provisão, e o card mostra "Informe o KM para
   calcular o lucro" em vez de "Lucro R$ 0,00".
9. **Excluindo o veículo ativo** — `activeVehicleId` volta para o próximo da
   lista, ou `null` se era o último. Confirmação antes de excluir. As rotas que
   já usaram esse veículo **mantêm** a provisão gravada.
10. **Carregando a lista** — `CircularProgressIndicator`; o ícone da `AppBar`
    fica no carro genérico até o stream responder.

## Estratégia de teste

`test/unit/vehicleCost_test.dart` — o coração, sem Firebase e sem widget:

- **o teste âncora**: os seis parâmetros da planilha devolvem `0,8193̅/km`, e
  898,1 km dão `R$ 735,84` (tolerância de 1 centavo);
- pneu com quantidade 4 dá `0,040` e não `0,010` — o `*4` da planilha;
- gasolina é `preço ÷ consumo`: 7,00 ÷ 10 = 0,700;
- `totalParts` **não** inclui a gasolina;
- `profitOf` confere contra a linha 3 de JUL: 152,50 · 46,9 km → **114,07**;
- consumo zero ou nulo devolve `null`, não infinito nem zero;
- vida 0 km devolve `null` e a peça sai da soma;
- rota sem KM, com KM negativo ou com valor zero devolve `null`;
- `fixedRate` (a "Geral") ignora preço e vida;
- veículo sem peça nenhuma tem taxa só de combustível.

`test/unit/routeProvision_test.dart` — a regra de escrita, que é onde mora o
risco de corromper histórico:

- status `agendado`/`andamento` apaga a provisão existente;
- `concluido` sem provisão calcula;
- `concluido` com provisão, mesmo KM e mesmo veículo, **mantém byte a byte** —
  inclusive quando as taxas do veículo mudaram no meio;
- KM alterado recalcula;
- veículo trocado recalcula;
- sem veículo ativo devolve `null` sem lançar;
- `toMap`/`fromMap` de `RouteProvision` ida e volta, com `parts` preservado;
- rota antiga sem o campo devolve `null`.

`test/unit/fipe_test.dart` — parse sem rede, com JSON fixo capturado da API
real; marca inexistente e corpo inválido devolvem lista vazia em vez de lançar.

`test/unit/vehicle_test.dart` — `toMap`/`fromMap` ida e volta; documento sem
`parts`, sem `quantity` e com enum desconhecido não lançam.

`test/unit/carImage_test.dart` — `"GM - Chevrolet"` → `chevrolet`,
`"VW - VolksWagen"` → `volkswagen`, `"Citroën"` → `citroen`;
`"Strada Adventure 1.8 mpi Flex CE"` → `strada`; moto devolve `null`.

`test/widget/vehicleCard_test.dart` — nome, selo de ativo, taxa formatada,
silhueta quando não há imagem.

`test/widget/routeCard_test.dart` (já existe, ganha casos) — rota com provisão
mostra gasolina, provisão e lucro; rota sem provisão não mostra a seção.

Nenhum teste toca a rede: as duas APIs entram por JSON fixo.

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; texto em pt-BR; conta em
  `Utils/vehicleCost.dart`, nunca dentro do `build`; `withValues(alpha:)` no
  lugar de `withOpacity`; `FirestoreService.instance` como único acesso ao
  Firestore; `null` para "não dá para calcular", nunca zero.
- **Perguntar antes:** qualquer dependência além de `image_picker`; adotar
  Firebase Storage; mudar o formato de campo **já gravado** em rota
  (`provision` é campo novo, então entra livre).
- **Nunca:** baixar ou cachear bytes da imagin (a licença proíbe); gravar
  `imageUrl` sem o usuário confirmar; deixar uma taxa incalculável virar zero na
  soma; **reescrever a provisão de uma rota que não teve KM nem veículo
  alterados**; hardcodar chave de API no código.

## Critérios de sucesso

- [ ] O `IconButton` aparece na `AppBar` **antes** do "Sair" e abre a tela.
- [ ] Sem veículo: ícone de carro. Com veículo ativo: a imagem dele, redonda,
      no tamanho de ícone.
- [ ] Escolher a marca lista os modelos **daquela marca**, com busca — o usuário
      nunca digita o nome do carro.
- [ ] O render aparece com "É esse o seu carro?" e só vira `imageUrl` depois do
      "Sim"; "Usar minha foto" abre câmera/galeria.
- [ ] Cadastrar um carro sem alterar nada dá **R$ 0,8193/km** no rodapé.
- [ ] Salvar uma rota de 46,9 km e R$ 152,50 como **concluída** grava
      `provision` com gasolina R$ 32,83, peças R$ 5,60 e lucro **R$ 114,07**.
- [ ] Reabrir e salvar essa rota sem mexer no KM **não** altera a provisão.
- [ ] Mudar o KM e salvar **recalcula**.
- [ ] Mudar o preço do pneu no veículo **não** altera nenhuma rota já concluída.
- [ ] Voltar a rota para "agendado" apaga a provisão.
- [ ] Concluir rota sem veículo cadastrado salva a rota e avisa, sem travar.
- [ ] O card da rota mostra gasolina, provisão e lucro quando há provisão.
- [ ] Cadastrar mais de um veículo e alternar o ativo com um toque; o ícone da
      `AppBar` troca junto.
- [ ] Excluir o ativo promove outro e não apaga a provisão das rotas antigas.
- [ ] Com a FIPE fora do ar dá para cadastrar digitando marca e modelo.
- [ ] `flutter analyze lib/` sem error/warning novo.
- [ ] Os testes novos passam e os que já existem continuam passando.

## Decisões

**1. FIPE para marca/modelo, consumo digitado.** É a divisão que os fatos
impõem: a FIPE resolve a listagem de graça e em pt-BR, e consumo de carro
brasileiro simplesmente não tem API gratuita — o INMETRO publica PDF. Fingir que
tem, chutando um valor "médio", seria pior que perguntar.

**2. Quantidade é campo, não conta de cabeça.** A planilha esconde o `*4` dentro
da fórmula. Sem esse campo o usuário teria que informar "R$ 2.000" de pneu, ou o
app provisionaria quatro vezes menos. É o único jeito de "R$ 500 o pneu" ser
verdade na tela e certo na conta.

**3. A provisão é um retrato gravado, não uma fórmula viva.** Calculada na
conclusão e congelada ali. Não é uma divergência acidental da planilha: corrigir
esse comportamento é **um dos pilares do app**. A planilha reescreve o lucro do
passado toda vez que um preço muda, e um lucro que muda depois do fato não é
lucro, é estimativa. O botão "recalcular" existe para quem quiser refazer a
conta, mas sob comando, nunca de surpresa.

**4. Lucro derivado, não gravado.** `value − fuel − totalParts` é uma linha. Todo
valor derivado que se grava acaba discordando da origem um dia.

**5. Confirmação da imagem.** `honda/cg` devolveu um Honda Pilot com
`found=true`. Um render errado no cabeçalho é ruído; um render errado que o
usuário nunca é convidado a corrigir é o bug do clima de novo.

**6. URL da imagin, nunca os bytes.** A licença proíbe baixar, cachear e
modificar. Guardar só a URL mantém o uso dentro do que a CDN entrega e deixa a
migração barata se um dia a imagem tiver de sair.

**7. `activeVehicleId` no perfil.** Uma escrita, atômica. `isActive` em cada
documento precisaria de transação e ainda poderia acabar com zero ou dois
ativos.

**8. Base64 no documento, sem Storage.** 40–70 KB contra o limite de 1 MB.
Storage exigiria o plano Blaze para guardar duas ou três fotos.

**9. As peças são lista, não enum.** As cinco da planilha vêm prontas, mas
correia e embreagem entram sem mudar o modelo.

**10. Só campo que entra em conta.** Placa, cor e valor FIPE saíram do escopo por
não alimentarem o cálculo nem identificarem o veículo na lista. Marca, modelo,
ano e apelido ficam porque identificam e porque montam a URL da imagem.

**11. A FIPE não pode bloquear o cadastro.** Marca e modelo aceitam texto quando
a API cai. O carro é do usuário; um servidor de terceiro fora do ar não pode
impedi-lo de registrar o próprio veículo.

## Dívidas e fora de escopo

- **Rotas já concluídas antes desta entrega ficam sem provisão.** Um botão
  "calcular provisão das rotas antigas" resolveria, mas aplicaria as taxas de
  **hoje** a rotas de abril — exatamente o que a decisão 3 evita. Fica de fora
  até você decidir se prefere o número aproximado ou o campo vazio.
- **Licença da imagin.** Marca d'água e uso não licenciado são aceitáveis para o
  app pessoal; publicar na loja exige plano pago ou trocar a fonte da imagem.
- **Consumo real por abastecimento** — depende da tela de Abastecimento, hoje
  "Em breve" no menu "+".
- **Lembrete de manutenção por KM** — os dados já ficam todos aqui (dura 10 000
  km, você rodou 8 300), mas exige hodômetro acumulado, que esta entrega não
  guarda.
- **Provisão e lucro nos gráficos e no resumo** — o dado passa a existir em toda
  rota concluída, então `graficsScreen`, `summaryCards` e `profileStats` podem
  usá-lo. Fica para a spec seguinte.
- **Agregação por plataforma** (a tabela `V2:AA6` da planilha: ganhos, pendente,
  pago, provisão, total, lucro por Amazon/ML/Shopee) — mesma spec seguinte.
- **Despesas avulsas** (a aba `Despesa`, `R2:T32`) — outra tela.
- **Foto no Firebase Storage** — quando base64 apertar.
- **Mapa de acentos duplicado.** `Utils/carImage.dart` e
  `controller/nicknameController.dart` têm a mesma tabela de `á→a`. Unificar é
  refatoração de dez linhas, mas a normalização de apelido tem o regex
  espelhado em `firestore.rules` e **zero teste** cobrindo — mexer nela por
  arrumação arrisca quebrar a reserva de apelidos em troca de nada. Fica para
  quando alguém precisar tocar em apelido de verdade.

## Perguntas em aberto

Uma, não bloqueante: **a moto usa 2 pneus e 2 freios** — vou abrir o formulário
de moto com quantidade 2 nessas duas linhas. Se a sua conta de moto for
diferente, é um número no seed.

E uma confirmação: incluí a exibição de gasolina/provisão/lucro no card da rota
(tarefa 12) por conta própria, porque gravar um número invisível não entrega
nada. Se preferir deixar para a spec dos gráficos, é só cortar a tarefa.

---

# Plano de implementação

```
(1) model/vehicle.dart ──┬──→ (2) Utils/vehicleCost.dart ──→ [âncora: 735,84]
                         │         teste primeiro
                         └──→ (3) services/fipe.dart + Utils/carImage.dart
                                        │
                    (4) controller/vehicleController.dart + rules
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              │ interface do veículo                              │ lado da rota
   (5) fipePicker + partsEditor              (10) newRouteModal: RouteProvision
   (6) screens/addVehicle                    (11) addIter: grava ao concluir
   (7) vehicleCard → (8) vehiclesScreen      (12) routeCard: exibe
   (9) vehicleAvatar → home.dart
              └─────────────────────────┬─────────────────────────┘
                                  (13) simulador
```

A ordem não é por importância, é por dependência: nada pode ser escrito antes de
`vehicleCost` provar que reproduz a planilha. Se o número não bater em (2), todo
o resto está construído sobre uma conta errada.

Os dois ramos são independentes depois de (4) — o lado da rota só precisa do
cálculo e do controller. Vêm depois na ordem porque, para testar (11) à mão, é
preciso ter um veículo cadastrado, e quem cadastra é (6).

Passos 1–4 e 10 não têm tela e são inteiramente testáveis sem simulador. É onde
mora o risco real.

**Nota sobre o `CLAUDE.md`:** ele diz que `AddIter._saveRoute()` é código morto
com guarda invertida. Está desatualizado — a função está ligada no botão
(`addIter.dart:835`) e a guarda está correta (`if (!validate()) return`,
linha 910). A tarefa 11 estende um salvamento que funciona. Vale corrigir essa
linha do `CLAUDE.md` junto.

## Riscos

| Risco | Mitigação |
|---|---|
| A conta não bater com a planilha | Tarefa 2 tem o teste âncora dos R$ 735,84 **antes** da implementação; se não bater, nada de tela é escrito |
| `*4` esquecido em pneu/freio | Teste dedicado: pneu com qtd 4 dá `0,040`, não `0,010` |
| **Reescrever a provisão de rota antiga ao editar outro campo** | A regra de escrita é tabela explícita na spec e o primeiro teste de `routeProvision_test.dart`; o caso "taxas mudaram, KM igual → mantém byte a byte" é o teste que trava isso |
| Divisão por zero virando `Infinity` gravado | `null` em todo divisor ≤ 0, com teste; a peça sai da soma |
| 585 modelos travando a lista | `ListView.builder` + busca por substring; nunca uma `Column` inteira |
| FIPE fora do ar bloqueando o cadastro | Marca e modelo aceitam texto digitado (estado 3) |
| Imagem errada tida como certa | Confirmação explícita do usuário (decisão 5) |
| Base64 estourando o documento | `maxWidth: 800, imageQuality: 70`; validar o tamanho antes de gravar e recusar acima de 700 KB |
| Excluir o ativo deixando o app sem veículo | Promove o próximo; teste do controller |
| Gastar as 500 req/dia da FIPE | Marcas pedidas uma vez por abertura do formulário, modelos só depois de escolher a marca; um cadastro custa ~3 requisições |

Checkpoint depois de cada tarefa: `flutter analyze lib/` sem nada novo, mais o
teste da tarefa.

---

# Tarefas

- [x] **1. `model/vehicle.dart` — o modelo** — 14 testes.
  - Aceite: `Vehicle`, `MaintenancePart`, `VehicleType`, `FuelType`, com
    `toMap`/`fromMap` tolerante (sem `parts`, sem `quantity`, enum desconhecido
    não lançam).
  - Verificar: `flutter test test/unit/vehicle_test.dart`
  - Arquivos: `lib/model/vehicle.dart`, `test/unit/vehicle_test.dart`,
    `lib/Utils/mapRead.dart`

- [x] **2. `Utils/vehicleCost.dart` — a matemática, teste primeiro** — 31 testes,
  **âncora batendo**: `R$ 735,8432667` contra o `X15` da planilha e
  `R$ 114,073267` contra o `O3`.
  - Aceite: todos os casos da "Estratégia de teste" escritos **antes** da
    implementação, incluindo o âncora (`0,8193̅/km` e `R$ 735,84` em 898,1 km) e
    a linha 3 de JUL (152,50 · 46,9 km → lucro 114,07).
  - Verificar: `flutter test test/unit/vehicleCost_test.dart`
  - Arquivos: `lib/Utils/vehicleCost.dart`, `test/unit/vehicleCost_test.dart`,
    `lib/model/newRouteModal.dart` (a classe `RouteProvision`)

- [x] **3. `services/fipe.dart` + `Utils/carImage.dart`** — 27 testes.
  - **Correção do que esta spec dizia:** era "erro devolve lista vazia". Isso
    torna *"a consulta falhou"* indistinguível de *"a marca não tem modelo"* —
    o mesmo defeito do clima, que esta base já pagou uma vez. Ficou
    `Future<List<FipeItem>?>` com **`null` = não deu para saber**, igual a
    `getWeather`. Lista vazia passa a significar só o que ela diz.
  - Duas armadilhas da API real, travadas por teste: `codigo` é **String** em
    `/marcas` e **int** em `/modelos` (um cast direto derrubaria a lista de
    modelos), e `/modelos` vem embrulhado em `{"modelos": […]}` enquanto os
    outros dois são array cru. O corpo é decodificado por `utf8.decode` sobre
    `bodyBytes`: `response.body` assume latin-1 e "Citroën" viraria "CitroÃ«n".
  - Aceite: marcas, modelos e anos para `/carros` e `/motos`; parse isolado da
    rede e testado com JSON fixo. Normalização de marca (`GM - Chevrolet` →
    `chevrolet`) e extração da família (`Strada Adventure…` → `strada`); moto
    devolve `null`.
  - Verificado também **fora do teste**, contra as duas APIs reais: 14 nomes
    vindos da FIPE (Fiorino, Strada, Toro, Doblo, Saveiro, Gol, HB20, Kwid,
    Celta…) atravessaram a normalização e a CDN respondeu `found=true` em todos.
  - Verificar: `flutter test test/unit/fipe_test.dart test/unit/carImage_test.dart`
  - Arquivos: `lib/services/fipe.dart`, `lib/Utils/carImage.dart`, + 2 testes

- [x] **4. `controller/vehicleController.dart` + `firestore.rules`** — 9 testes
  nas duas funções puras. **Falta publicar a regra** (`firebase deploy --only
  firestore:rules`); sem isso o Firestore nega a subcoleção e a tarefa 13 trava.
  - `activeFrom(vehicles, activeId)` é a **única** resolução de "qual veículo
    está em uso", chamada tanto pela AppBar quanto pelo cálculo da provisão. Se
    fossem duas, a tela poderia desenhar um carro e a conta usar outro.
  - `id` órfão (veículo excluído com o app offline) cai no primeiro da lista em
    vez de devolver `null`: o usuário tem carro, dizer "nenhum veículo" seria
    mentira. `ensureActive` conserta o campo no servidor depois.
  - `delete` apaga **antes** de reapontar, de propósito: morrer no meio deixa um
    `activeVehicleId` órfão, que `activeFrom` já sabe resolver. A ordem inversa
    deixaria o usuário sem ativo tendo veículos.
  - `sortByCreation` desempata pelo `id` quando o `createdAt` empata — ordem que
    dança entre rebuilds trocaria o veículo ativo sozinho.
  - Aceite: `watchAll`, `fetchAll`, `save`, `delete` em `iter/{uid}/vehicles`,
    com `try/catch` por documento; `setActive` grava em
    `user/{uid}.activeVehicleId`; excluir o ativo promove o próximo.
  - Verificar: `flutter test test/unit/vehicleController_test.dart`
  - Arquivos: `lib/controller/vehicleController.dart`, `lib/model/users.dart`,
    `firestore.rules`, `test/unit/vehicleController_test.dart`

- [x] **5. `widget/fipePicker.dart` + `widget/partsEditor.dart`** — 16 testes.
  - **Bug pego na revisão, antes de rodar:** os dois campos numéricos precisam
    de regras **opostas** para o ponto. Em "Dura (km)" o ponto é milhar
    (`50.000` = cinquenta mil); no campo de taxa direta ele é decimal, porque o
    teclado numérico do celular oferece ponto e `0.03` lido como milhar viraria
    `3` — cem vezes a taxa, num campo em que ninguém confere de cabeça. Viraram
    `parseKm` e `parseRate`, com teste para cada.
  - O escape de texto livre ficou **dentro do picker** ("Não encontrou?
    Digite"), então marca e modelo ganham o mesmo escape sem código repetido —
    e ele serve tanto para a FIPE fora do ar quanto para veículo que ela não
    lista.
  - Aceite: sheet com busca aguentando 585 itens sem travar, estados de
    carregando e de erro com "tentar de novo"; editor de peças com preço, vida,
    quantidade, taxa ao vivo, `[+ peça]`, remover linha, `—` na incalculável.
  - Verificar: `flutter test test/widget/partsEditor_test.dart`
  - Arquivos: `lib/widget/fipePicker.dart`, `lib/widget/partsEditor.dart`, + teste

- [x] **6. `screens/addVehicle.dart` — o formulário** — 9 testes de widget, e o
  primeiro deles é o critério de aceite da spec inteira: abrir e não tocar em
  nada mostra **R$ 0,8193 / km**.
  - A spec previa só `flutter run` aqui. Virou teste de widget porque nada do
    `initState` toca rede ou Firestore — o rodapé é conta pura sobre estado
    local, e um `flutter run` para conferir um número que um teste confere em
    dois segundos seria desperdício.
  - Duas camadas para a imagem, e nenhuma basta sozinha: `imaginHasImage` (HEAD
    na CDN, lê `x-imaginstudio-request-found`) descarta o *"não tenho esse
    veículo"*, e a confirmação do usuário descarta o *"tenho, mas é o carro
    errado"* — que foi o caso do Honda Pilot. `_pendingImageUrl` é separado de
    `_imageUrl`: enquanto ninguém confirmou, **nada é gravado**.
  - Trocar carro↔moto zera marca e modelo (coleções diferentes na FIPE) e refaz
    as peças com a quantidade de rodas certa.
  - `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` entraram no
    `ios/Runner/Info.plist`: sem elas o iOS **derruba o app** ao abrir a câmera,
    sem sequer pedir permissão.
  - Aceite: imagem no topo com confirmação, tipo, marca/modelo/ano pela FIPE,
    apelido, bloco de combustível, tabela de peças pré-preenchida com os valores
    da planilha, rodapé com o custo/km ao vivo. Cria **e** edita com o mesmo id.
  - Verificar: `flutter test test/widget/addVehicle_test.dart`
  - Arquivos: `lib/screens/addVehicle.dart`, `lib/services/imagin.dart`,
    `pubspec.yaml` (`image_picker: ^1.2.3`), `ios/Runner/Info.plist`, + teste

- [x] **7. `widget/vehicleCard.dart`** — 11 testes.
  - A precedência da imagem (foto do dono → render da CDN → silhueta) saiu para
    `widget/vehicleThumb.dart`, porque o card e o ícone da `AppBar` mostram o
    mesmo veículo: duas implementações acabariam discordando sobre qual imagem
    vale.
  - **Bug encontrado pelo teste:** `base64Decode` **lança**, e lança antes de
    qualquer `errorBuilder` rodar — um único documento com a foto corrompida
    derrubaria a lista inteira, justamente o que o `try/catch` por documento do
    controller existe para impedir. Virou `decodePhoto()`, usada também no
    formulário, onde o mesmo risco existia ao editar.
  - Aceite: imagem, apelido, marca/modelo/ano, taxa R$/km, selo de ativo,
    silhueta quando não há imagem.
  - Verificar: `flutter test test/widget/vehicleCard_test.dart`
  - Arquivos: `lib/widget/vehicleCard.dart`, `lib/widget/vehicleThumb.dart`,
    `lib/screens/addVehicle.dart`, + teste

- [x] **8. `screens/vehiclesScreen.dart` — lista e troca do ativo**
  - Sem teste de widget: a tela é `StreamBuilder` sobre Firestore de ponta a
    ponta e não sobrou lógica pura para isolar — `activeFrom`, que é a decisão
    de verdade, já está coberta na tarefa 4. Fica para o simulador (tarefa 13).
  - O diálogo de exclusão diz que **as rotas já concluídas mantêm a provisão**:
    o medo natural na hora de apagar um veículo é perder o lucro já calculado,
    e é justamente o que não acontece.
  - Aceite: lista pelo stream, toque troca o ativo, `Slidable` exclui com
    confirmação, `+` abre o formulário, estado vazio com a dica.
  - Verificar: `flutter analyze lib/`
  - Arquivos: `lib/screens/vehiclesScreen.dart`

- [x] **9. `widget/vehicleAvatar.dart` + `home.dart` — o ícone da AppBar**
  - A `AppBar` inteira passou para dentro do `StreamBuilder` (via
    `PreferredSize`), e não só o título: o botão de veículos precisa do
    `activeVehicleId`, que mora no **mesmo** documento que o apelido. Deixar o
    `VehicleAvatar` ler o perfil por conta própria seria escutar `user/{uid}`
    duas vezes — a mesma decisão que a spec do perfil já tinha tomado.
  - O avatar mantém um listener sobre `vehicles`: são dois ou três documentos, e
    é o que faz o ícone trocar sozinho quando o veículo em uso muda na outra
    tela.
  - Aceite: `IconButton` antes do "Sair"; carro genérico sem veículo, imagem do
    ativo quando existe; troca sozinho ao mudar o ativo.
  - Verificar: `flutter analyze lib/`, `flutter test` e `flutter build apk
    --debug` (compila)
  - Arquivos: `lib/widget/vehicleAvatar.dart`, `lib/screens/home.dart`

- [x] **10. Campo `provision` na rota + a regra de escrita** — 16 testes, com
  destaque para *"preço mudou, KM igual → mantém"*, que é o pilar do app virado
  em asserção: a mesma rota, com o combustível reprecificado de R$ 7,00 para
  R$ 9,00, continua gravando `fuel: 32,83` e o mesmo `calculatedAt`.
  - `NewRouteModal.withProvision()` resolve um ovo e galinha do salvamento: a
    provisão é calculada **a partir** da rota (precisa do status, KM e valor
    novos), então a rota tem de existir antes dela. Repetir os dezoito
    argumentos do construtor no `addIter.dart` seria pedir para esquecer um.
  - `_kmEpsilon` de um metro em vez de `==` entre `double`: nenhuma edição real
    muda menos que isso, e comparar ponto flutuante com igualdade exata deixaria
    "reescrever o histórico ou não" nas mãos do último bit da representação.
  - A classe `RouteProvision` saiu daqui e foi para a tarefa 2: `vehicleCost`
    precisa construí-la para o teste âncora existir, e um tipo intermediário só
    para respeitar a ordem seria cerimônia. Sobra aqui o que é de fato desta
    tarefa — pendurar o campo na rota e escrever a regra de quando ele muda.
  - Aceite: campo `provision` opcional em `NewRouteModal`, gravado e lido; rota
    antiga sem o campo devolve `null` sem lançar. Toda a tabela "Regra exata de
    escrita" coberta por teste, com destaque para "mesmo KM e mesmo veículo
    mantém byte a byte, mesmo com as taxas do veículo alteradas".
  - Verificar: `flutter test test/unit/routeProvision_test.dart`
  - Arquivos: `lib/model/newRouteModal.dart`, `lib/Utils/vehicleCost.dart`,
    `test/unit/routeProvision_test.dart`

- [x] **11. `addIter.dart` — gravar a provisão ao concluir**
  - O veículo só é lido quando a rota está concluída ou paga: uma consulta ao
    Firestore a cada rascunho salvo seria leitura jogada fora.
  - Falha ao ler o veículo **não** impede o salvamento: o dado da rota é do
    usuário, a provisão é conveniência.
  - Aceite: ao salvar com `concluido`/`pago`, lê o veículo ativo e aplica a
    regra de escrita; sem veículo, salva a rota e avisa sem bloquear; voltar
    para `agendado` apaga a provisão.
  - Verificar: `flutter analyze lib/` e `flutter run`
  - Arquivos: `lib/screens/addIter.dart`

- [x] **12. `widget/routeCard.dart` — mostrar gasolina, provisão e lucro** — 6
  testes novos, incluindo um que falha se a gasolina algum dia entrar dentro de
  `Provisão` (viraria R$ 38,43 no lugar de R$ 5,60) e outro que confere o
  prejuízo em vermelho.
  - Aceite: com provisão, o card expandido mostra as três linhas com o lucro em
    verde; sem provisão, a seção não aparece; concluída sem KM mostra "Informe o
    KM para calcular o lucro".
  - Verificar: `flutter test test/widget/routeCard_test.dart`
  - Arquivos: `lib/widget/routeCard.dart`, `test/widget/routeCard_test.dart`

- [x] **13. Verificação no aparelho** — feita pelo Wesley em 06/08/2026, em
  Android e iPhone físicos.
  - Já verificado sem o simulador: `flutter build apk --debug` e
    `flutter build ios --simulator --debug` **compilam** (o `image_picker` traz
    código nativo nos dois lados), regras publicadas no `iter-mn`, 328 testes
    passando e `flutter analyze` sem nada novo.
  - Roteiro:
    1. Ícone de carro na `AppBar`, antes do "Sair" → abre "Meus veículos".
    2. `+` → escolher Fiat, depois Fiorino na lista (nunca digitando o nome).
    3. Conferir o render e responder "É esse o seu carro?".
    4. Sem mexer em mais nada, o rodapé mostra **R$ 0,8193 / km**.
    5. Salvar. O ícone da `AppBar` vira a imagem do veículo.
    6. Nova rota: R$ 152,50, KM 1000 → 1046,9, status **concluído**.
    7. Abrir o card da rota: Gasolina R$ 32,83 · Provisão R$ 5,60 ·
       Lucro **R$ 114,07**.
    8. Reabrir a rota e salvar sem mudar nada → a provisão **não** muda.
    9. Editar o veículo, pneu de R$ 500 para R$ 700, salvar → a rota de antes
       continua com R$ 114,07. **Este é o passo que prova o pilar.**
    10. Cadastrar um segundo veículo, alternar o ativo, excluir o ativo e ver
        outro ser promovido.
  - Verificar: `flutter run`
