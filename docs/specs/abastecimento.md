# Spec: Abastecimento

Status: **proposta** · Criada em 2026-08-05 · Aguardando aprovação

## Objetivo

Ligar o "Abastecimento" do menu "+", hoje marcado como *Em breve*, a uma tela de
registro: valor, litros, preço do litro calculado, hodômetro, veículo e — quando
der — o posto e a localização.

Cada registro vira um documento em `iter/{uid}/supply/{id}`, alimenta a coleção
global `gastop` com o preço daquele posto, e aparece somado num card de **gastos
do período** na aba Resumo.

Usuário: o entregador. Sucesso = ele sai do posto, registra em quinze segundos e
o app passa a saber o preço real que ele paga pelo litro — em vez do R$ 7,00 que
ele digitou uma vez e que envelhece sozinho.

### Por que isto vale mais do que parece

Três dívidas de specs anteriores morrem aqui:

1. **`Vehicle.fuelPrice` deixa de ser um chute datado.** Hoje é digitado à mão e
   entra em toda provisão de rota. Cada abastecimento passa a oferecer o preço
   real medido na bomba.
2. **O consumo real (km/l) fica ao alcance.** Com o hodômetro de dois
   abastecimentos seguidos e os litros do segundo, sai o km/l de verdade — o
   dado que `cadastro-veiculo.md` registrou como impossível de obter, porque
   nenhuma API brasileira o tem.
3. **A aba Resumo ganha o lado das despesas**, que hoje só mostra receita e
   lucro.

## ⚠️ A armadilha desta feature: contar o combustível duas vezes

A provisão de rota **já cobra combustível**: `fuel = km × (preço ÷ consumo)`. Se
o card de gastos do período for subtraído do lucro, a gasolina entra duas vezes
— uma como provisão estimada, outra como despesa real.

**São coisas diferentes e não se somam:**

| | o que é | onde vive |
|---|---|---|
| Provisão | **estimativa** por km rodado, congelada na rota | dentro do lucro |
| Abastecimento | **dinheiro que saiu** do bolso, na data em que saiu | card de gastos, à parte |

O card de gastos é um **extrato**, não uma dedução. O lucro dos cards de empresa
continua sendo `valor − gasolina provisionada − peças`, sem tocar em nada daqui.

Um dia vai fazer sentido comparar os dois — "provisionei R$ 628 de gasolina e
gastei R$ 590, então minha estimativa está boa". Essa comparação é o valor real
que este dado destrava, e fica registrada como trabalho futuro. Somar não é.

## As APIs — testadas, não lidas

### ✅ Postos: Overpass API (OpenStreetMap), sem chave

```
POST https://overpass-api.de/api/interpreter
[out:json][timeout:25];
nwr["amenity"="fuel"](around:3000,{lat},{lon});
out center tags;
```

Cobertura medida em Fortaleza, raio de 3 km:

| ponto | postos | mais próximo |
|---|---|---|
| Centro | 60 | 325 m |
| Aldeota | 51 | 245 m |
| Messejana | 25 | 570 m |
| Carlito Pamplona | 31 | 495 m |

Três detalhes que só apareceram testando, e que a implementação **depende** de
acertar:

1. **`nwr`, não `node`.** A primeira query devolveu 5 postos no Centro; com
   `nwr` foram 60 — **49 deles são polígonos (`way`)**. Consultar só nós perde
   80% dos postos.
2. **`out center`** é obrigatório para polígono ter coordenada. Sem isso, o
   `way` volta sem `lat`/`lon` e não dá para ordenar por distância.
3. **User-Agent descritivo, ou 406.** A Overpass recusa cliente genérico com
   `406 Not Acceptable` — foi o que aconteceu no teste com o `urllib` padrão. A
   política de uso pede que a aplicação se identifique.

Nem todo posto tem `name`; muitos têm só `brand` (Ipiranga, BR, Shell). O rótulo
cai em `name → brand → "Posto sem nome"`.

A Overpass é serviço comunitário gratuito com política de uso: uma consulta por
abastecimento é uso doméstico e cabe folgado. `429` e `504` acontecem e são
tratados como "não deu para saber".

### ✅ Localização: `geolocator` 14.0.3

Perfil oposto ao do pacote de vidro que recusamos: **6.116 likes, ~2 milhões de
downloads por mês, 160/160 pub points, 133 versões**, publisher verificado
(Baseflow). É o padrão de fato no ecossistema.

Exige permissão declarada nas duas plataformas — hoje o projeto **não tem
nenhuma**:

- `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription`
- `android/app/src/main/AndroidManifest.xml`: `ACCESS_FINE_LOCATION` e
  `ACCESS_COARSE_LOCATION`

Sem localização o formulário **continua inteiro**: perde a lista de postos, e o
campo de posto vira texto livre. Registrar o próprio abastecimento não pode
depender de GPS.

## Layout

```
┌── Abastecimento ──────────────────────────┐
│  Veículo    [ Fit EXL 1.5 Flex · em uso ▾]│
│                                           │
│  Valor      [ R$ 250,00 ]  ← obrigatório  │
│  Litros     [ 39,750    ]  ← opcional     │
│  ╔═════════════════════════════════════╗  │
│  ║  Preço do litro     R$ 6,2893       ║  │ ← readOnly, para conferir
│  ╚═════════════════════════════════════╝  │   com a bomba
│                                           │
│  Combustível ( • Gasolina ) ( ○ Etanol )  │ ← só quando o veículo é flex
│  KM atual   [ 128.500 ]    ← opcional     │
│                                           │
│  ── Posto ───────────────────────────────  │
│  📍 Usando sua localização                 │
│  ┌───────────────────────────────────────┐│
│  │ ● Posto Apiguana        325 m         ││ ← o primeiro é o mais próximo
│  │ ○ BR                    494 m         ││
│  │ ○ Shell                 512 m         ││
│  │ ○ Outro / não listado                 ││
│  └───────────────────────────────────────┘│
│                                           │
│           [ REGISTRAR ABASTECIMENTO ]     │
└───────────────────────────────────────────┘
```

Tela cheia, como `addIter` e `addVehicle` — um padrão só de formulário no app.

### Depois de salvar, uma pergunta

Quando o preço calculado difere do `fuelPrice` do veículo, aparece:

> **R$ 6,2893/L.** O cadastro do Fit está com R$ 7,00. Atualizar?
> `[ Atualizar ]` `[ Agora não ]`

**Nunca automático.** Mudar o preço do veículo muda o custo por km de toda rota
futura; isso é decisão do dono, não efeito colateral de registrar uma despesa. E
o preço de uma bomba de etanol não deve virar o preço do carro que roda a
gasolina.

## Os números

**Preço do litro = `valor ÷ litros`.** ReadOnly de propósito: quem calcula é o
app, para o entregador conferir com o painel da bomba. Sem litros informados,
mostra `—` — não zero.

**Não é gravado.** É derivável em uma linha, e valor derivado que se grava um
dia discorda da origem — a mesma decisão de `RouteProvision.profitFrom`.

A exceção é o preço reportado ao posto em `gastop`: ali ele **é** gravado,
porque é um *relato* de quanto custava naquele dia, não um derivado do documento
que o contém.

## Dados

### `iter/{uid}/supply/{id}`

| campo | tipo | |
|---|---|---|
| `id` | String | `Uuid().v4()` |
| `vehicleId` | String? | padrão: o veículo em uso |
| `value` | double | **obrigatório**, > 0 |
| `liters` | double? | opcional |
| `fuel` | String | `gasolina` \| `etanol` \| `diesel` \| `gnv` \| `eletrico` |
| `odometer` | double? | KM do painel — a semente do consumo real |
| `station` | Map? | `{ id, name, brand, lat, lng }` |
| `lat` / `lng` | double? | onde o usuário estava |
| `date` | String | ISO 8601 — a data do abastecimento |
| `createdAt` | String | ISO 8601 |

`pricePerLiter` **não existe** no documento: é `value / liters`, um getter.

### `gastop/{stationId}` — global

`stationId` é o id do OSM com o tipo junto: `way-123456`, `node-98765`. Vem da
fonte, então dois usuários no mesmo posto escrevem no mesmo documento sem
combinar nada.

```
gastop/{stationId}
  name, brand, lat, lng
  prices: { gasolina: 6.29, etanol: 4.19 }   ← por combustível
  updatedAt, updatedBy
```

**Preço por tipo de combustível, e não um preço só.** Um posto tem quatro bombas
com quatro preços; um campo único faria o registro de diesel apagar o de
gasolina, e o dado ficaria pior do que não existir.

### `gastop/{stationId}/precos/{id}` — o histórico

```
  price, fuel, uid, at
```

**Imutável**: as regras liberam `create` e negam `update` e `delete`. Histórico
que pode ser reescrito não é histórico — é a mesma razão de a provisão da rota
ser um valor congelado.

### `firestore.rules`

```
match /iter/{userId}/supply/{supplyId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}

match /gastop/{stationId} {
  allow read: if request.auth != null;
  allow create, update: if request.auth != null
                        && request.resource.data.updatedBy == request.auth.uid;
  allow delete: if false;

  match /precos/{reportId} {
    allow read: if request.auth != null;
    allow create: if request.auth != null
                  && request.resource.data.uid == request.auth.uid;
    allow update, delete: if false;   // relato não se reescreve
  }
}
```

**Risco assumido, registrado:** qualquer usuário autenticado pode relatar
qualquer preço para qualquer posto. Com um usuário isso é teórico; com mil, um
engano de digitação — ou má-fé — envenena a recomendação. A defesa quando
chegar a hora é ler a **mediana dos relatos recentes** em vez de `prices`, e é
exatamente para isso que o histórico existe. Não é para esta entrega.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1 · **uma dependência nova: `geolocator: ^14.0.3`**.
`http` (já usado) para a Overpass. `setState` + `StreamBuilder`, como sempre.

## Comandos

```bash
flutter pub get
flutter analyze lib/ test/
flutter test test/unit/supply_test.dart
flutter test test/unit/overpass_test.dart
flutter test test/unit/expenseSummary_test.dart
flutter test test/widget/addSupply_test.dart
flutter test
firebase deploy --only firestore:rules      # obrigatório antes de testar
```

## Estrutura

```
lib/model/supply.dart                  → Supply + FuelStation (novo)
lib/services/overpass.dart             → postos por raio (novo)
lib/services/location.dart             → geolocator embrulhado (novo)
lib/controller/supplyController.dart   → iter/{uid}/supply (novo)
lib/controller/stationController.dart  → gastop + histórico (novo)
lib/Utils/expenseSummary.dart          → gastos do período, puro (novo)
lib/screens/addSupply.dart             → o formulário (novo)
lib/screens/suppliesScreen.dart        → a lista do período (novo)
lib/widget/stationPicker.dart          → a lista de postos (novo)
lib/widget/expenseCard.dart            → o card do Resumo (novo)
lib/screens/summaryScreen.dart         → + o card de gastos
lib/screens/home.dart                  → "Abastecimento" ganha onTap
firestore.rules                        → + supply e gastop
ios/Runner/Info.plist                  → + NSLocationWhenInUseUsageDescription
android/.../AndroidManifest.xml        → + ACCESS_*_LOCATION
```

## Estados

1. **Sem permissão de localização** — o bloco do posto mostra "Ative a
   localização para ver os postos por perto" e um campo de texto livre. O
   formulário salva normalmente.
2. **Permissão negada para sempre** — mesma coisa, com um atalho para os
   ajustes do sistema. Não insistir: pedir de novo a cada abertura irrita.
3. **Overpass fora do ar / `429` / `504`** — "Não foi possível buscar os postos.
   Tentar de novo", e o texto livre continua ali.
4. **Nenhum posto no raio** — sobe para 5 km uma vez; ainda vazio, é texto
   livre. Zona rural existe.
5. **Sem litros** — preço do litro mostra `—`, e **nada é escrito em `gastop`**:
   sem litros não há preço para relatar.
6. **Posto digitado à mão** — grava dentro do abastecimento, **não** em
   `gastop`: sem coordenada da fonte não há como dois usuários concordarem que é
   o mesmo posto.
7. **Veículo flex** — aparece o seletor gasolina/etanol; nos outros, o
   combustível vem do cadastro sem perguntar.
8. **Nenhum veículo cadastrado** — salva a despesa sem `vehicleId` e avisa.

## Estratégia de teste

`test/unit/supply_test.dart` — modelo:

- `toMap`/`fromMap` ida e volta, com `station` aninhada e sem ela;
- `pricePerLiter` é `value / liters`, `null` sem litros e `null` com litros zero
  (nunca infinito);
- `pricePerLiter` **não** aparece no mapa gravado;
- documento antigo/incompleto não lança.

`test/unit/overpass_test.dart` — parse sem rede, com JSON real capturado:

- lê `node` **e** `way`, tirando a coordenada de `center` quando existe;
- ordena por distância, mais próximo primeiro;
- rótulo cai de `name` para `brand` para "Posto sem nome";
- corpo ilegível e lista vazia são **coisas diferentes** — `null` e `[]`;
- a distância haversine bate com valores conhecidos.

`test/unit/expenseSummary_test.dart` — o card:

- soma só os abastecimentos dentro do período;
- período sem gasto devolve zero, não `null`;
- manutenções entram como zero e a linha aparece marcada "em breve".

`test/widget/addSupply_test.dart`:

- o preço do litro reage a valor e litros ao digitar;
- sem litros mostra `—`;
- o campo do preço é readOnly (não aceita digitação);
- valor vazio ou zero bloqueia o salvamento;
- seletor de combustível só aparece com veículo flex.

Nenhum teste toca rede nem GPS: Overpass entra por JSON fixo e a localização é
injetada.

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; texto em pt-BR; contas em `Utils/`,
  nunca no `build`; `null` para "não dá para calcular"; User-Agent identificando
  o app na Overpass.
- **Perguntar antes:** qualquer dependência além de `geolocator`; mexer no
  cálculo da provisão de rota; alterar `Vehicle` além de `fuelPrice`.
- **Nunca:** subtrair os gastos do lucro dos cards de empresa (contaria
  combustível duas vezes); atualizar `Vehicle.fuelPrice` sem o usuário mandar;
  escrever em `gastop` sem litros ou sem posto da fonte; permitir `update` ou
  `delete` nos relatos de preço.

## Critérios de sucesso

- [ ] "Abastecimento" no menu "+" perde o selo *Em breve* e abre a tela.
- [ ] Valor é obrigatório; litros e hodômetro são opcionais.
- [ ] O preço do litro calcula ao digitar, é readOnly e mostra `—` sem litros.
- [ ] Com localização, a lista traz os postos por perto com o **mais próximo em
      primeiro**, com a distância ao lado.
- [ ] Sem localização ou com a Overpass fora do ar, dá para registrar mesmo
      assim, digitando o posto.
- [ ] Salvar grava em `iter/{uid}/supply/{id}`.
- [ ] Com posto e litros, grava `gastop/{stationId}` e um relato imutável em
      `precos/`.
- [ ] O preço fica separado por combustível — diesel não apaga gasolina.
- [ ] Depois de salvar, o app **pergunta** se atualiza o preço do veículo.
- [ ] A aba Resumo mostra o card de gastos abaixo do último card de empresa.
- [ ] O card **não** altera o lucro de nenhum card de empresa.
- [ ] O botão "Detalhar" lista os abastecimentos do período.
- [ ] `flutter analyze lib/` sem error/warning novo.
- [ ] Os 391 testes que já existem continuam passando.

## Decisões

**1. Gasto é extrato, não dedução.** A provisão já cobra combustível dentro do
lucro. Subtrair os abastecimentos também contaria a gasolina duas vezes. Ver o
aviso no topo — é o erro mais caro que esta feature pode introduzir.

**2. Preço do litro derivado, nunca gravado.** `value / liters` é uma linha.
Grava-se apenas o relato em `gastop`, que é um fato datado, não um derivado.

**3. Preço por combustível.** Um posto tem quatro bombas. Campo único faria
diesel apagar gasolina e deixaria o dado pior que inexistente.

**4. Relato de preço é imutável.** `create` sim, `update` e `delete` não.
Histórico reescrevível não é histórico — mesma razão da provisão congelada.

**5. Atualizar o preço do veículo é sempre uma pergunta.** Mudar `fuelPrice`
muda o custo por km de toda rota futura. É decisão do dono, não efeito colateral
de registrar despesa.

**6. GPS nunca bloqueia o registro.** Sem permissão, sem rede ou sem posto no
raio, o formulário continua inteiro com texto livre. O abastecimento é dele; um
serviço de terceiro fora do ar não pode impedi-lo de anotar.

**7. Posto digitado à mão não vai para `gastop`.** Sem coordenada da fonte não
há como dois usuários concordarem que é o mesmo posto, e "Posto do Zé" viraria
dez documentos diferentes.

**8. `stationId` vem do OSM.** `way-123456` é estável e global: dois usuários no
mesmo posto escrevem no mesmo documento sem combinar nada.

## Dívidas e fora de escopo

- **Consumo real (km/l).** O hodômetro passa a ser gravado nesta entrega, mas
  calcular km/l entre dois abastecimentos e oferecer ao veículo é a spec
  seguinte. Sem este campo, aquela spec não teria de onde começar.
- **Comparar provisionado x gasto** — "provisionei R$ 628 de gasolina e gastei
  R$ 590". É o valor real que este dado destrava, e merece tela própria.
- **Manutenções.** O card já reserva a linha, marcada "em breve". A tela é outra
  spec e este card a acolhe sem mudança.
- **Recomendação de preço por perto** — a razão de `gastop` existir. Precisa de
  vários usuários, e da mediana dos relatos em vez do último valor.
- **Envenenamento de preço** — ver o bloco das regras.
- **Editar e excluir abastecimento** — só cadastro e listagem nesta entrega.
- **Foto da nota** — não pedido, e traria a mesma discussão de base64 x Storage.

## Perguntas em aberto

Nenhuma bloqueante. Vínculo com veículo, hodômetro, formato de `gastop` e tela
cheia foram respondidos antes desta spec.

---

# Plano de implementação

```
(1) model/supply.dart ──┬─→ (2) services/overpass.dart
                        │      teste com JSON real
                        ├─→ (3) services/location.dart + permissões
                        │
              (4) controllers + firestore.rules
                        │
        (5) widget/stationPicker ──→ (6) screens/addSupply ──→ (7) home
                        │
        (8) Utils/expenseSummary ──→ (9) widget/expenseCard + summaryScreen
                        │
              (10) screens/suppliesScreen ──→ (11) simulador
```

Os passos 1–4 e 8 não têm tela e são testáveis sem simulador. O 3 é o único que
depende de aparelho de verdade — emulador dá localização falsa, o que serve para
o caminho feliz mas não para permissão negada.

## Riscos

| Risco | Mitigação |
|---|---|
| **Gastos serem subtraídos do lucro** (dupla contagem) | Está nas Fronteiras como "nunca", e o card de empresa tem teste que fixa o lucro atual — se alguém somar, ele quebra |
| Consultar só `node` na Overpass e perder 80% dos postos | Teste de parse com JSON real contendo `way` + `center` |
| `406` por User-Agent genérico | Header fixo no serviço, com teste de que ele é enviado |
| Divisão por zero em litros zerado | `null`, com teste |
| Diesel sobrescrevendo gasolina em `gastop` | Preço por combustível, com teste |
| Permissão negada travando o formulário | Estados 1 e 2, com teste de widget sem localização |
| Escrever em `gastop` com posto digitado à mão | Guarda explícita no controller, com teste |
| Regras não publicadas na hora de testar | Está nos Comandos; foi o que travou a tarefa 13 do veículo |

---

# Tarefas

- [x] **1. `model/supply.dart`** — 17 testes.
  - `SupplyFuel` é **enum próprio**, sem `flex`: flex é a capacidade do carro,
    não o líquido da bomba. `SupplyFuel.fromVehicle()` devolve `null` para
    flex, e é desse `null` que o seletor da tela depende — não de um
    `if (fuel == FuelType.flex)` espalhado pelo formulário. O tipo é que diz
    "pergunte".
  - **`gnv` saiu** da lista que a spec previa: `FuelType` do veículo não tem
    GNV, então um abastecimento de GNV seria um estado que nada consegue
    produzir. Entra junto com `FuelType.gnv`, quando alguém precisar.
  - Aceite: `Supply` + `FuelStation`, `toMap`/`fromMap` tolerante,
    `pricePerLiter` derivado e ausente do mapa, `null` com litros zero.
  - Verificar: `flutter test test/unit/supply_test.dart`
  - Arquivos: `lib/model/supply.dart`, `test/unit/supply_test.dart`

- [x] **2. `services/overpass.dart`** — 17 testes, sobre uma resposta **real**
  capturada da API (um `node` só com marca e um `way` com `center`).
  - Três testes existem só para travar as armadilhas descobertas na pesquisa: a
    query contém `nwr` e **não** `node["amenity"`, contém `out center`, e o
    User-Agent identifica o app. São os três erros que custam 80% dos postos,
    coordenada nenhuma e um `406`.
  - `id` é `way-243218168`, com **hífen** e não a barra do OSM: vira chave de
    documento no Firestore, onde barra separa coleção de documento.
  - Verificado também **fora do teste**: a string exata que o Dart monta,
    enviada à API real, devolve `HTTP 200` com **60 postos (11 nós + 49
    polígonos)**, zero polígono sem `center` e 13 sem nome — os três caminhos
    que o parse trata.
  - Aceite: consulta `nwr` + `out center`, User-Agent do app, parse de `node` e
    `way`, ordenação por distância, rótulo com fallback, `null` para falha e
    `[]` para vazio.
  - Verificar: `flutter test test/unit/overpass_test.dart`
  - Arquivos: `lib/services/overpass.dart`, `test/unit/overpass_test.dart`

- [x] **3. `services/location.dart` + permissões** — 7 testes.
  - `failureFor()` é pura e recebe o estado, então a **decisão** — a parte onde
    moram os bugs — é testável sem aparelho. `currentLocation()` fica sendo só
    a casca que fala com a plataforma.
  - **GPS desligado vence permissão concedida**, com teste: mandar "permita a
    localização" para quem já permitiu e só está com o GPS off é a mensagem
    errada. E "negado agora" é caso diferente de "negado para sempre" — o
    primeiro dá para perguntar de novo, o segundo só pelos ajustes, e
    `opensSettings()` separa os dois.
  - `ACCESS_COARSE_LOCATION` junto com `FINE`: no Android 12+ o usuário pode
    conceder só a aproximada, e ~100 m basta para achar o posto. Sem declarar
    as duas, negar a precisa derrubaria o recurso inteiro.
  - Precisão **média** e não `best`: achar o posto pede uns 100 m, e alta
    precisão come bateria de quem usa o celular o dia todo rodando.
  - Aceite: pede permissão, devolve posição ou `null` com o motivo; chaves no
    `Info.plist` (validado com `plutil -lint`) e no `AndroidManifest`;
    `flutter build` nas duas plataformas.
  - Verificar: `flutter build apk --debug` ✅ e `flutter build ios --simulator`
  - Arquivos: `lib/services/location.dart`, `test/unit/location_test.dart`,
    `pubspec.yaml`, `ios/Runner/Info.plist`,
    `android/app/src/main/AndroidManifest.xml`

- [x] **4. Controllers + `firestore.rules`** — 11 testes. **Regras publicadas**
  no `iter-mn` (compilaram e foram liberadas).
  - `StationController.canReport()` é pura e mora **no controller, não no
    formulário**: qualquer caminho futuro que grave abastecimento herda a
    guarda. Barra posto digitado à mão (sem id do OSM, "Posto do Zé" viraria
    dez documentos irreconciliáveis) e barra abastecimento sem litros (sem
    preço do litro não há o que relatar).
  - `prices` é mapa **por combustível** gravado com `SetOptions(merge: true)`:
    o Firestore funde mapa aninhado em vez de trocá-lo, então relatar etanol
    hoje não apaga o preço da gasolina de ontem.
  - `date` em ISO 8601 e não `dd/MM/yyyy`: ISO ordena como texto na mesma ordem
    em que ordena como data, então a lista sai ordenada do Firestore sem o
    remendo em memória que `RouteController` precisou fazer. Tem teste com a
    virada de ano.
  - Falhar ao escrever em `gastop` **não** derruba o registro do abastecimento:
    o gasto é dele, a coleção global é conveniência para os outros.
  - Aceite: `SupplyController` (`watchAll`, `fetchAll`, `save`, `delete`) e
    `StationController` (posto + relato imutável); regras publicadas; escrita
    em `gastop` bloqueada sem posto da fonte ou sem litros.
  - Verificar: `flutter test test/unit/supplyController_test.dart` e
    `firebase deploy --only firestore:rules`
  - Arquivos: `lib/controller/supplyController.dart`,
    `lib/controller/stationController.dart`, `firestore.rules`,
    `test/unit/supplyController_test.dart`

- [x] **5. `widget/stationPicker.dart`** — 17 testes.
  - Widget **controlado**: não busca localização nem consulta a Overpass, só
    desenha o que recebe. É o que torna os cinco estados — carregando, sem
    permissão, API fora do ar, nenhum posto, lista cheia — testáveis sem
    aparelho e sem rede.
  - **"Outro / não listado" existe em todos os estados**, e não só no de erro:
    a Overpass pode responder certinho e não ter o posto onde ele parou. A
    spec previa o texto livre como plano B da falha; virou saída permanente.
  - `otherSelected` é campo separado de `selected` porque `null` em `selected`
    também significa "ainda não escolheu nada". Sem a distinção, marcar "Outro"
    deixaria dois itens marcados ao mesmo tempo — tem teste.
  - O picker **não reordena**: quem ordena é `parseStations`. Duas noções de
    "mais próximo" acabariam discordando.
  - Aceite: lista ordenada com distância, mais próximo em primeiro, "Outro /
    não listado", estados de carregando, erro e vazio.
  - Verificar: `flutter test test/widget/stationPicker_test.dart`
  - Arquivos: `lib/widget/stationPicker.dart`, + teste

- [x] **6. `screens/addSupply.dart`** — 21 testes.
  - **Bug pego pelo teste:** a tela passava `canOpenSettings` para o
    `StationPicker` mas **nunca passava `onOpenSettings`** — e o botão só
    renderiza com os dois. Quem bloqueasse a permissão de vez ficaria sem saída
    nenhuma: sem lista, sem diálogo do sistema e sem atalho para os ajustes.
    Entrou `openLocationSettings()` no serviço.
  - A tela recebe dois **carregadores opcionais** (veículos e postos). Em
    produção ficam `null` e ela usa os serviços de verdade; no teste, montam a
    tela inteira sem Firestore, sem GPS e sem rede. Sem essa costura, a maior
    tela da spec ficaria sem teste nenhum.
  - `shouldOfferPriceUpdate` saiu para `Utils/supplyRules.dart` — é regra de
    domínio, não de tela, e é onde a próxima spec (consumo real em km/l) vai
    morar. Tem folga de meio centavo: o preço vem de uma divisão e quase nunca
    bate na terceira casa, então sem ela o app perguntaria a **cada**
    abastecimento.
  - Litros usa `parseRate` (ponto = decimal) e não `parseKm`: "39.75 L" é
    39,75 litros. Lido como milhar daria 3.975 L e um preço de seis centavos.
  - `parseKm` e `parseRate` mudaram de `widget/partsEditor.dart` para
    `Utils/currencyFormat.dart` — com um segundo consumidor, parser de número
    morando dentro de widget é a mesma deriva que o `formatRate` já teve.
  - Aceite: todos os campos, preço readOnly ao vivo, validação do valor,
    seletor de combustível só em veículo flex, bloco de posto degradando sem
    localização, e a pergunta de atualizar o preço do veículo depois de salvar.
  - Verificar: `flutter test test/widget/addSupply_test.dart`
  - Arquivos: `lib/screens/addSupply.dart`, `lib/Utils/supplyRules.dart`,
    `lib/services/location.dart`, `lib/Utils/currencyFormat.dart`,
    `lib/widget/partsEditor.dart`, + teste

- [x] **7. `home.dart` — tirar o "Em breve"**
  - O selo some **sozinho**: `CreateAction.comingSoon` é `onTap == null`, então
    ligar a ação já apaga a marca. Foi a decisão de modelagem do
    `createActionSheet` — `onTap` opcional em vez de um `bool` separado torna
    impossível escrever a linha inconsistente, e aqui ela se paga.
  - A Manutenção continua marcada, sem eu tocar nela.
  - Aceite: a ação abre a tela; o selo some só dela.
  - Verificar: `flutter analyze lib/`, `flutter test` e `flutter build apk
    --debug`
  - Arquivos: `lib/screens/home.dart`

- [x] **8. `Utils/expenseSummary.dart`** — 13 testes.
  - **Escorreguei e o teste corrigiu:** somei um `averagePricePerLiter` que a
    spec não pedia e o deixei pela metade — um getter devolvendo `null`. Ao
    implementar de verdade apareceu a decisão que importa: o preço médio é
    **ponderado** (Σvalor ÷ Σlitros), não a média dos preços. Quem enche R$ 300
    a R$ 6,00 e completa R$ 30 a R$ 7,00 pagou R$ 6,08 — a média simples daria
    R$ 6,50, dando a uma completada de trinta reais o mesmo peso de um tanque
    cheio. Tem asserção negativa contra o 6,50.
  - Abastecimento **sem litros fica fora dos dois lados** da divisão: entrar só
    no dividendo inflaria o preço médio. O dinheiro dele continua inteiro em
    `fuel`, que é o que o card mostra.
  - `maintenance` é zero **reservado**, e `hasMaintenance` existe para o card
    mostrar "em breve" em vez de um `R$ 0,00` que pareceria afirmação de que
    ele não gastou com peça.
  - Comparação por **dia**: abastecer às 23h do dia 31 é gasto daquele mês.
  - Aceite: soma dos abastecimentos no período, manutenção reservada em zero,
    período vazio devolve zero.
  - Verificar: `flutter test test/unit/expenseSummary_test.dart`
  - Arquivos: `lib/Utils/expenseSummary.dart`, + teste

- [x] **9. `widget/expenseCard.dart` + `summaryScreen.dart`** — 13 testes.
  - **Um problema de interface que a spec não previa:** o card fica logo abaixo
    de "Lucro R$ 175,60", e ver "Gastos R$ 430,50" ali convida a subtrair de
    cabeça — conta errada, porque o lucro já desconta a provisão. O card traz
    uma linha dizendo isso, e ela aparece **até no período sem gasto nenhum**.
    A spec protegia o código contra a dupla contagem; faltava proteger a
    leitura.
  - Aparência diferente dos cards de empresa de propósito: aqueles são receita,
    este é dinheiro saindo. Mesma tela, naturezas opostas.
  - Stream próprio para o card, e não o das rotas: os cards de empresa
    continuam desenhados enquanto os abastecimentos carregam, e uma falha ao
    ler `supply` só esconde este card.
  - Aceite: card abaixo do último card de empresa, com abastecimento,
    manutenção "em breve", total e o botão "Detalhar"; **o lucro dos cards de
    empresa não muda** — verificado rodando o teste deles depois da mudança.
  - Verificar: `flutter test test/widget/expenseCard_test.dart` e
    `test/widget/companySummaryCard_test.dart`
  - Arquivos: `lib/widget/expenseCard.dart`, `lib/screens/summaryScreen.dart`

- [x] **10. `screens/suppliesScreen.dart`** — feita junto com a 9, porque o
  botão "Detalhar" precisava dela para compilar; um placeholder viveria cinco
  minutos.
  - Recebe a lista **já filtrada** em vez de abrir o próprio stream: é a mesma
    lista que o card somou, então o detalhe nunca discorda do total que levou o
    usuário até ali. Dois streams poderiam divergir por um instante e mostrar
    um valor que não fecha.
  - Aceite: lista do período com data, posto, valor, litros e preço do litro;
    estado vazio.
  - Verificar: `flutter analyze lib/` e `flutter build apk --debug`
  - Arquivos: `lib/screens/suppliesScreen.dart`

- [ ] **11. Verificação no aparelho**
  - Aceite: permitir a localização e ver os postos reais ordenados; registrar;
    conferir `iter/{uid}/supply` e `gastop` no console; negar a permissão e
    confirmar que ainda dá para registrar.
  - Verificar: `flutter run` (**aparelho real** — o emulador não reproduz negar
    permissão de forma confiável)
