# Spec: Postos da região

Status: **implementada e testada pelo Wesley em 2026-10-06** · Evolui o
bloco "Posto" de `docs/specs/abastecimento.md`

## Objetivo

Três queixas do uso real:

1. **Registrar depois não funciona.** O abastecimento é feito com pressa, sem
   registrar na hora, e só é registrado em casa. A lista busca os postos em volta de
   onde o celular **está agora**, ou seja, em volta de casa, e o posto onde o
   abastecimento aconteceu não aparece. Hoje a única saída é "Outro / não listado",
   que grava o nome digitado e **nunca** chega em `gastop` (decisão 7 da spec
   original). Assim, registrar depois também custa o relato de preço.
2. **A data é sempre "agora".** `addSupply` grava `date: now`, sem campo. Quem
   registra no dia seguinte (*"às vezes eu mesmo só adiciono no dia
   seguinte"*) põe o gasto no dia errado, às vezes no mês errado, e muda a ordem
   do consumo medido, que ordena por data.
3. **A lista é pobre.** É um `ListTile` com rádio, nome e distância, e mostra os
   25 a 60 postos *dentro* do formulário, empurrando o botão de salvar para
   baixo de tudo.

Sucesso = no dia seguinte, em casa, dá para pôr a data de ontem, tocar em
"Outra localização", digitar "Maraponga", ver os postos de lá com bandeira e
preço, escolher o certo e salvar. O registro fica com o id do OSM, a data certa, e o
preço chega em `gastop` com a idade verdadeira, sem apagar um preço mais novo.

Referência visual: o print "Postos da região" que veio com o pedido (busca, "Minha
localização / Outra localização", cards com logo, bairro, nome, distância e uma
faixa de preços), **sem os selos "Super Barato / Barato"**.

## As APIs: testadas, não lidas

Medido em 2026-10-06 com o User-Agent do app.

### Overpass já traz o bairro

Na região metropolitana (bbox `-3.95,-38.75,-3.68,-38.40`) são **379 postos**.
A mesma consulta de hoje (`out center tags`) já devolve:

| tag | postos | uso |
|---|---|---|
| `brand` | 209 (55%) | logo |
| `addr:suburb` | 191 (50%) | **bairro** da linha de cima do card |
| `addr:street` sem `addr:suburb` | 18 (5%) | não compensa um campo a mais |

No raio de 3 km do Centro a cobertura do bairro é maior: 45 de 60. **Sem
consulta nova e sem `is_in`**: é só ler uma tag que já vem na resposta e hoje é
descartada.

A Overpass respondeu duas vezes com página HTML de erro (`Dispatcher_Client`)
antes de responder certo. Isso já é tratado como "não deu para saber", com
"Tentar de novo", e continua igual.

### Bandeira → logo: 54% dos postos ganham logo

Valores de `brand` na RMF: Shell 79, BR 72, Ipiranga 31, Ale 10, Petrobras 6,
SP 6, SP Combustíveis 3, Pertobras 1, OM 1. Os outros 170 não têm `brand`.

Simulando a regra da seção "Bandeira" sobre os 379:

| origem | postos | logo |
|---|---|---|
| `brand` reconhecida | 198 | BR, Shell, Ipiranga ou ALE |
| `brand` desconhecida (SP, OM…) | 11 | sem bandeira |
| sem `brand`, nome cita a bandeira | 8 | p.ex. "Posto BR (Bonsucesso)" |
| sem `brand` e sem bandeira no nome | 162 | sem bandeira |

Total com logo: **206 de 379 (54%)**. O resto usa `POSTO-SEMBANDEIRA.png`,
como foi pedido. As imagens são **assets do app**: nenhuma requisição, nenhum
logo baixado da internet (a spec original já recusou o caminho Wikidata/Commons).

### Outra localização: Nominatim, só ao confirmar a busca

```
GET https://nominatim.openstreetmap.org/search
    ?q=Maraponga&format=jsonv2&countrycodes=br&limit=5
    &accept-language=pt-BR&viewbox=<em volta do aparelho>
```

| busca | primeiro resultado |
|---|---|
| `Maraponga, Fortaleza` | Maraponga, Fortaleza (`-3.7934, -38.5690`), bairro |
| `Messejana` (sem cidade) | Messejana, **Fortaleza**: o `viewbox` puxa para perto |
| `Avenida Bezerra de Menezes 1000, Fortaleza` | o número exato, em São Gerardo |
| `Caucaia` | o município |
| `Rua Barão do Rio Branco, Centro, Fortaleza` | 3 trechos da rua, todos no Centro |

É o mesmo ecossistema da Overpass (OSM), sem chave e com a mesma regra de
User-Agent. A política de uso **proíbe autocompletar** e limita a 1 requisição
por segundo. Por isso a busca dispara na confirmação ("Buscar" no teclado),
nunca a cada letra.

O Photon (komoot) também foi testado. Ele aceita prefixo ("Marapon" →
Maraponga) e foi feito para autocompletar, mas é uma instância pública "fair
use" sem garantia, e para o caso real (digitar um bairro inteiro, uma vez) o
Nominatim respondeu igual. Fica registrado como alternativa.

## Layout

### No formulário: a data e um campo de posto

```
│  Data       [ 06/10/2026 (hoje)      📅 ] │  ← padrão hoje; nunca no futuro
│  …                                        │
│  ── Posto ───────────────────────────────  │
│  ┌───────────────────────────────────────┐ │
│  │ (⛽)  Escolher posto                 › │ │  ← nada escolhido
│  └───────────────────────────────────────┘ │
│                                           │
│  ┌───────────────────────────────────────┐ │
│  │ (BR)  Maraponga                       │ │  ← escolhido: o mesmo card
│  │       Posto Maraponga              ›  │ │    da lista, sem preços e
│  └───────────────────────────────────────┘ │    sem distância
```

Tocar abre a tela abaixo, que devolve o posto escolhido. O card do formulário
**não mostra distância**: depois de escolhido, "2,8 km" de onde? De casa não
interessa, e do centro de uma busca já fechada não significa nada.

### `Postos da região`: tela cheia

```
┌── ←  Postos da região ────────────────────┐
│ [ Buscar por nome, bairro ou bandeira 🔍 ]│  ← filtra a lista carregada
│ [ 📍 Minha localização ] [ Maraponga    › ]│  ← o ativo fica destacado; o
│                                           │    segundo mostra o lugar
│ ┌───────────────────────────────────────┐ │    escolhido
│ │ (BR)  Maraponga                       │ │
│ │       Posto Maraponga       📍 2,8 km │ │
│ ├───────────────────────────────────────┤ │
│ │ Gasolina      Etanol       Diesel     │ │
│ │ R$ 6,14       R$ 4,24      —          │ │  ← "—" = ninguém relatou
│ │ há 2d         há 2d                   │ │  ← idade do relato
│ └───────────────────────────────────────┘ │
│ ┌───────────────────────────────────────┐ │
│ │ (🐚)  Serrinha                        │ │
│ │       Posto Via Serrinha    📍 3,3 km │ │
│ ├───────────────────────────────────────┤ │
│ │ Gasolina      Etanol       Diesel     │ │
│ │ —             —            —          │ │
│ └───────────────────────────────────────┘ │
│   …                                       │
│ ┌───────────────────────────────────────┐ │
│ │ ✎  Outro / não listado                │ │  ← continua existindo sempre
│ └───────────────────────────────────────┘ │
└───────────────────────────────────────────┘
```

- **Logo** num círculo de 48 px com fundo branco. BR preenche o círculo
  (`cover`), como no print; Shell, Ipiranga, ALE e sem bandeira cabem inteiros
  (`contain`), porque cortados perdem a forma.
- **Bairro** em cinza, em cima do nome, só quando o OSM o tem. Sem bairro, o
  card fica com uma linha só, e não aparece "Bairro desconhecido".
- **Nome** — *revisto em 2026-10-06, depois do primeiro teste no simulador*:
  o texto é o **nome do posto, nunca a bandeira ao lado do logo dela**. Em
  ordem: o nome de verdade; o endereço (`addr:street` + número) quando não há
  nome **ou o "nome" só repete a bandeira** (`name=Shell`, "Posto BR" — 42
  postos da RMF); "Posto sem nome". Sem logo, o `label` de sempre, que mantém
  "| SP" para quem tem bandeira sem imagem. Na RMF: 232 nomes, 50 endereços,
  97 sem nada. A rua mais próxima por consulta espacial foi testada e
  recusada: 27,5 s por busca (contra poucos segundos), e posto de esquina volta
  com até cinco ruas sem ordem de distância.
- **Distância** a partir do **centro da busca**: o GPS em "Minha localização" e
  o lugar escolhido em "Outra localização".
- **Idade** de cada preço com `relativeWhen` (`Utils/relativeTime.dart`), a
  mesma frase do mural: `há 3h`, `há 2d`, `06/08`.

### `Outra localização`

```
┌── ←  Outra localização ───────────────────┐
│ [ Bairro, rua ou referência     ] [Buscar]│
│                                           │
│  📍 Maraponga                             │
│     Fortaleza, Ceará                      │
│  📍 Maraponga Mart Moda                   │
│     Fortaleza, Ceará                      │
└───────────────────────────────────────────┘
```

Escolher um resultado volta para "Postos da região" com a lista recentrada ali.
O botão passa a mostrar o nome do lugar ("Maraponga"), para ficar claro de onde
as distâncias estão sendo medidas.

## A data do abastecimento

Campo **Data**, padrão hoje, com o `showCupertinoDatePicker` que `addIter` e o
filtro de período já usam, travado em `maximumDate: hoje`. Abastecimento no
futuro não existe.

O que vai para `Supply.date` (ISO), decidido por uma função pura
`expenseDateFor(picked, now: now)` (em `Utils/dated.dart`):

| escolheu | grava | por quê |
|---|---|---|
| hoje | `now` | é o caso de sempre, e a hora real é a melhor que existe |
| outro dia | aquele dia, **12:00** | a hora não é conhecida. Meio-dia é um marcador neutro que não escorrega para o dia vizinho em fuso nenhum |

A hora inventada só pesa em um caso: dois abastecimentos do mesmo veículo no
mesmo dia, um registrado na hora e outro depois. Se o meio-dia cair na ordem
errada, o hodômetro sai fora de ordem e `measuredEconomy` já devolve
`kmNaoAvanca`: **sem número**, nunca um km/l errado. O lado que falha é o que
não lisonjeia.

`createdAt` continua sendo `now`. É a diferença entre os dois campos que diz
"registrado depois", e o modelo já a previa ("pode ser anterior a `createdAt`,
para quem registra depois").

### O relato de preço de outro dia

O relato em `gastop` passa a usar a **data do abastecimento**, não a hora do
registro: `precos.at` e `pricedAt.{combustível}` recebem `supply.date`. Um preço
de ontem carimbado como de hoje seria a idade errada na mesma tela que existe
para mostrá-la.

E um preço velho não pode apagar um novo. Se o abastecimento de segunda é
registrado na quarta, e outra pessoa relatou o preço na terça, o de segunda
não pode virar o "preço atual". Dois caminhos:

| data | como grava | por quê |
|---|---|---|
| **hoje** | `WriteBatch`, como hoje: `prices` + `pricedAt` + relato | funciona **sem sinal**, na bomba. Um batch fica na fila offline e uma transação não |
| **outro dia** | **transação**: lê `pricedAt.{combustível}` e só troca `prices`/`pricedAt` se o relato for mais novo. O relato em `precos` entra sempre | quem registra depois está em casa, com rede |

A regra de comparação é pura (`shouldReplacePrice(stored, reported)`, com
`stored == null` → troca) e testada sem Firestore. Sem rede, a transação falha
e o relato se perde, **mas o abastecimento continua salvo**. É a regra de hoje:
o gasto é de quem abasteceu, `gastop` é conveniência para os outros.

## Os preços

A faixa de cada card lê `gastop/{stationId}.prices`, o último preço relatado
por qualquer usuário, por combustível. **Não há conta nova**: é exibir o que a
coleção já guarda desde a spec do abastecimento.

Três colunas fixas: **Gasolina, Etanol, Diesel**. São os três líquidos de
`SupplyFuel` que saem de uma bomba. Elétrico fica de fora porque não existe em
posto de combustível. O print mostra "G. Comum", "G. Aditivada" e "D. S10", mas
`SupplyFuel` não separa comum de aditivada nem S10 de S500, e separar mudaria o
formulário, o consumo por combustível e o relato. Fica em "Fora de escopo".

Uma leitura por lista e não uma por posto: `where(documentId, whereIn: ids)` em
blocos de 30 (o limite do `in`). Para 60 postos são **duas consultas**, cobradas
pelos documentos que existem, que hoje são poucos.

**Três estados que não podem se confundir**, a mesma regra do `getWeather`:

| situação | a faixa mostra |
|---|---|
| ninguém relatou este combustível neste posto | `—` |
| preços ainda carregando | espaço reservado, **sem** `—` |
| falha ao ler `gastop` | a faixa some, com uma linha "Não foi possível carregar os preços" |

Mostrar `—` enquanto carrega, ou quando a leitura falhou, diria "ninguém
relatou" sobre um posto que pode ter preço. É a mesma mentira do sol desenhado
para "não sei o tempo".

### `pricedAt`: a idade de cada preço

Hoje `gastop` tem um `updatedAt` **por posto**, não por combustível. Relatar
etanol hoje atualiza o `updatedAt` e deixaria a gasolina de três meses atrás com
cara de nova. Para mostrar a idade, a data passa a ser gravada junto de cada
preço:

```
gastop/{stationId}
  prices:   { gasolina: 6.14, etanol: 4.24 }
  pricedAt: { gasolina: '2026-10-04T…', etanol: '2026-10-04T…' }   ← novo
```

Escrito no mesmo `set(merge: true)` de hoje, que funde mapas aninhados. **As
regras não mudam**: `create, update` só exigem `updatedBy == auth.uid`. Os
documentos antigos não têm `pricedAt`, então o preço aparece sem idade e se
corrige sozinho no próximo relato daquele combustível naquele posto.

## Dados

| onde | mudança |
|---|---|
| `FuelStation` | `+ suburb: String?`, lido de `addr:suburb`, e `+ address: String?`, de `addr:street` + `addr:housenumber`; os dois gravados em `toMap` (identificam o posto no card) |
| `Supply.date` | vem do campo Data (`expenseDateFor`), não mais sempre `now` |
| `Supply.lat/lng` | `null` quando a busca foi em **outra localização** (ver suposição 4) |
| `gastop/{id}` | `+ pricedAt.{combustível}`, ISO, a data do abastecimento |
| `gastop/{id}/precos/{r}.at` | a data do abastecimento, não a hora do registro |

A bandeira (`StationFlag`) é **derivada, nunca gravada**, como o
`pricePerLiter`: é uma função de `brand` + `name`, e uma bandeira gravada um dia
discorda da regra que a produziu.

## Bandeira

```dart
/// A bandeira que o app sabe desenhar.
enum StationFlag {
  br('assets/images/POSTO-BR.png'),
  shell('assets/images/POSTO-SHELL.png'),
  ipiranga('assets/images/POSTO-IPIRANGA.png'),
  ale('assets/images/POSTO-ALE.png'),
  semBandeira('assets/images/POSTO-SEMBANDEIRA.png');

  const StationFlag(this.asset);
  final String asset;
}

/// `brand` decide quando existe; o nome só é consultado quando ninguém disse.
StationFlag flagOf(FuelStation station) { … }
```

Regra, em ordem:

1. **`brand` reconhecida** → aquela bandeira. Palavra a palavra, com
   `normalizeKey`: `BR`, `Petrobras`, `Petrobrás` → BR; `Shell`; `Ipiranga`;
   `Ale`, `ALE`, `Alesat` → ALE.
2. **`brand` presente mas desconhecida** (SP, OM) → **sem bandeira**, mesmo que
   o nome cite outra. A tag de bandeira é quem afirma a bandeira, e o nome
   "Posto Shell" num posto com `brand=SP` é dado contraditório. Na dúvida, o
   desenho neutro.
3. **Sem `brand`**: o nome, **palavra inteira**. "Posto BR (Bonsucesso)" → BR,
   mas "Posto **Br**asil" não. É a mesma armadilha que o `_mentions` do `label`
   já evita.
4. Nada disso → sem bandeira.

## Estados

1. **Carregando a localização** — o formulário começa a buscar ao abrir, como
   hoje. Ao tocar em "Escolher posto" a lista costuma já estar pronta. Se não
   estiver, "Procurando postos por perto…".
2. **Sem permissão / GPS desligado** — "Minha localização" mostra o motivo de
   hoje (`locationFailureMessage`) e o atalho para os ajustes quando é
   `deniedForever`. **"Outra localização" continua funcionando**, porque não
   depende do GPS. Hoje quem nega a permissão só pode digitar o nome. Depois
   desta entrega, escolhe da lista pelo bairro e o relato chega em `gastop`.
3. **Overpass fora do ar** — "Não foi possível buscar os postos" + "Tentar de
   novo", nos dois modos.
4. **Nominatim fora do ar** (`null`) — "Não foi possível buscar esse endereço
   agora". É uma frase **diferente** de "Nenhum lugar encontrado para
   'xyz'" (`[]`).
5. **Nenhum posto no raio** — "Nenhum posto encontrado por aqui", com
   "Outra localização" e "Outro / não listado" à mão.
6. **Filtro sem resultado** — "Nenhum posto com 'xyz' por aqui", com o filtro
   para limpar. A lista carregada continua lá.
7. **Preços** — os três estados da tabela acima.
8. **"Outro / não listado"** — em todos os estados, como hoje. O nome digitado
   continua **fora** de `gastop`.
9. **Data de outro dia** — o relato vai pela transação e só troca o preço atual
   se for mais novo. Sem rede, o relato se perde e o abastecimento fica.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1. **Nenhuma dependência nova**: `http` (já usado)
para o Nominatim, `Image.asset` para os logos, `cloud_firestore` para os
preços. Os assets já estão cobertos pela entrada `assets/images/` do
`pubspec.yaml`. `setState`, como sempre.

## Comandos

```bash
flutter pub get
flutter analyze lib/ test/
flutter test test/unit/stationFlag_test.dart
flutter test test/unit/stationFilter_test.dart
flutter test test/unit/geocoding_test.dart
flutter test test/unit/stationPrices_test.dart
flutter test test/unit/overpass_test.dart
flutter test test/unit/supplyController_test.dart
flutter test test/unit/dated_test.dart
flutter test test/widget/stationCard_test.dart
flutter test test/widget/placeSearch_test.dart
flutter test test/widget/stationsScreen_test.dart
flutter test test/widget/addSupply_test.dart
flutter test
flutter build apk --debug
```

Sem `firebase deploy`: as regras não mudam.

## Estrutura

```
lib/Utils/stationFlag.dart            → StationFlag + flagOf (novo, puro)
lib/Utils/stationFilter.dart          → filtro por nome/bairro/bandeira (novo, puro)
lib/Utils/dated.dart                  → + expenseDateFor
lib/services/geocoding.dart           → Nominatim: busca + parse (novo)
lib/services/overpass.dart            → + addr:suburb
lib/model/supply.dart                 → FuelStation.suburb
lib/model/stationPrices.dart          → preço + data por combustível (novo)
lib/controller/stationController.dart → pricesFor(ids); relato com pricedAt,
                                        data do abastecimento e shouldReplacePrice
lib/widget/stationCard.dart           → o card (novo; lista e formulário)
lib/widget/placeSearch.dart           → showPlaceSearch: "Outra localização" (novo)
lib/screens/stationsScreen.dart       → "Postos da região" (novo)
lib/widget/stationField.dart          → o campo "Escolher posto" (substitui stationPicker.dart)
lib/screens/addSupply.dart            → Data + campo de posto; repassa a busca já iniciada
```

`stationsScreen.dart` segue o padrão de `addSupply`: **carregadores
opcionais** (postos, preços, geocodificação) que em produção ficam `null` e no
teste montam a tela inteira sem GPS, sem rede e sem Firestore.

## Estratégia de teste

`test/unit/stationFlag_test.dart`
- `BR`, `Petrobras`, `Petrobrás` → BR; `Shell`; `Ipiranga`; `Ale`/`ALE` → ALE;
- `brand=SP` com nome "Posto Shell" → **sem bandeira** (regra 2);
- sem `brand`, "Posto BR (Bonsucesso)" → BR, e "Posto Brasil" → sem bandeira;
- **todo valor de `StationFlag` aponta para um arquivo que existe** em disco. Um
  asset renomeado só lançaria dentro do `Image.asset`, na tela.

`test/unit/geocoding_test.dart`, sobre JSON real capturado:
- parse de `jsonv2` em `Place(label, detail, lat, lng)`;
- corpo ilegível → `null`; `[]` → lista vazia. São coisas diferentes;
- a requisição leva User-Agent, `countrycodes=br` e `viewbox` quando há posição.

`test/unit/stationPrices_test.dart`
- `prices` + `pricedAt` → preço e data por combustível;
- documento antigo sem `pricedAt` → preço sem data, sem lançar;
- valor não numérico ou chave desconhecida é ignorado sem derrubar o posto;
- os ids são quebrados em blocos de no máximo 30.

`test/unit/supplyController_test.dart` (+), o relato:
- `pricedAt.{combustível}` e `precos.at` recebem a **data do abastecimento**;
- `shouldReplacePrice`: sem preço guardado → troca; relato mais novo → troca;
  relato mais velho ou igual → **não** troca;
- abastecimento de hoje vai pelo batch, de outro dia pela transação.

`test/unit/dated_test.dart` (+)
- `expenseDateFor(hoje, now)` → `now`; outro dia → aquele dia às 12:00;
- a virada de ano e o último dia do mês caem no dia escolhido.

`test/unit/overpass_test.dart` (+)
- `addr:suburb` chega em `FuelStation.suburb`; ausente → `null`.

`test/unit/stationFilter_test.dart`
- sem acento e sem caixa: "maraponga" acha "Maraponga";
- "petrobras" acha posto de bandeira BR; "shell" acha pelo logo derivado;
- consulta vazia devolve tudo, **na mesma ordem** (quem ordena é a Overpass).

`test/widget/stationCard_test.dart`
- bairro só quando existe; nome sem "| BR" quando há logo, `label` quando não;
- preço ausente mostra `—`; carregando **não** mostra `—`; falha esconde a faixa;
- os três preços dividem a linha (`Expanded`) e o nome tem `maxLines: 1`.

`test/widget/stationsScreen_test.dart`
- lista na ordem recebida;
- "Outra localização" → busca → escolhe → recarrega com o centro novo, e o
  botão mostra o nome do lugar;
- sem permissão de GPS, "Outra localização" continua tocável e funciona;
- filtro sem resultado diz o que foi buscado;
- "Outro / não listado" presente em todos os estados;
- tocar num card devolve aquele posto.

`test/widget/addSupply_test.dart` (ajustado)
- Data começa em hoje e não aceita futuro;
- o bloco do posto é um campo, nada vem pré-selecionado;
- escolher um posto de outra localização salva com o id do OSM e
  `Supply.lat/lng` nulos.

`test/widget/stationPicker_test.dart` **sai junto com o widget que testa**. Os
casos que continuam valendo (carregando, erro, ajustes, vazio, "Outro") mudam
para `stationsScreen_test.dart`, e nenhum é apagado sem um equivalente.

Pelo aviso do `CLAUDE.md`, os testes de widget verificam **a causa** e não
"cabe na tela". Quem decide se cabe é o aparelho.

## Fronteiras

- **Sempre:** User-Agent do app no Nominatim e na Overpass; geocodificar só
  na confirmação; `null` para "não deu para saber" e `[]` para "não há";
  regras de bandeira, filtro e data em `Utils/`, fora do `build`; textos em
  pt-BR.
- **Perguntar antes:** qualquer dependência nova (um mapa para escolher o ponto
  no dedo, por exemplo); mudar `firestore.rules`; criar valores novos em
  `SupplyFuel` (aditivada, S10); qualquer mudança em `gastop` além de
  `pricedAt` e da data do relato.
- **Nunca:** pré-selecionar o posto mais próximo (em casa, o mais próximo é
  justamente o errado); mostrar `—` para "não carregou"; mandar posto digitado
  para `gastop`; deixar um relato mais velho apagar um preço mais novo; aceitar
  data futura; baixar logo da internet; autocompletar no Nominatim.

## Critérios de sucesso

- [ ] O formulário tem **Data**, padrão hoje, sem futuro; o gasto de ontem cai
      em ontem no card de gastos.
- [ ] O bloco "Posto" do formulário é um campo só, sem nada pré-selecionado.
- [ ] "Postos da região" lista os postos do mais próximo ao mais distante do
      centro da busca, com logo, bairro (quando o OSM tem) e distância.
- [ ] Shell, BR/Petrobras, Ipiranga e ALE mostram o logo; os demais, o de sem
      bandeira.
- [ ] Cada card mostra Gasolina, Etanol e Diesel com o último preço relatado e
      a idade dele, ou `—` quando ninguém relatou.
- [ ] "Outra localização" encontra um bairro ou endereço e recentra a lista. Os
      postos de lá podem ser escolhidos e o relato de preço chega em `gastop`.
- [ ] Relato de outro dia nunca substitui um preço mais novo.
- [ ] Funciona com a localização negada.
- [ ] A busca filtra por nome, bairro ou bandeira, sem diferenciar acento.
- [ ] "Outro / não listado" continua disponível.
- [ ] Nenhuma dependência nova; `flutter analyze` sem erro ou aviso novo; a
      suíte inteira passa (exceto o `widget_test.dart` de sempre).
- [ ] Verificado pelo Wesley em aparelho: logos nítidos no círculo, a busca por
      outro bairro funcionando de casa e um abastecimento de ontem registrado.

## Decisões

**1. Tela própria, não lista dentro do formulário.** 60 cards com faixa de preço
dentro do `ListView` do formulário dão uns 9.000 px de rolagem até o botão de
salvar. Custa um toque a mais no posto, que é pago pela lista legível.

**2. Nada pré-selecionado.** O cenário que motivou a spec é registrar de casa,
onde o posto "mais próximo" é exatamente o errado e seria salvo em silêncio.

**3. Bandeira derivada e só de asset.** Zero requisição, e a regra fica testável.
`brand` desconhecida vence o nome, porque o desenho neutro é o erro que não
afirma nada.

**4. Bairro da tag, não de consulta espacial.** `addr:suburb` vem de graça em
50% dos postos. Um `is_in` para os outros 50% seria uma consulta mais pesada
num serviço comunitário, para uma linha de texto.

**5. Nominatim só ao confirmar.** A política proíbe autocompletar. Uma busca por
registro é uso doméstico.

**6. Preços em duas consultas `whereIn`, não uma por posto.** Usa o `list` que
`gastop` já libera. Ver a dívida sobre `get` × `read` abaixo.

**7. Campo de data — decidido pelo Wesley em 2026-10-06** (*"às vezes eu mesmo
só adiciono no dia seguinte"*). Só a data, sem hora: hoje grava `now`, outro dia
grava meio-dia. O relato usa a data do abastecimento, e o de outro dia passa por
uma transação que não deixa preço velho apagar preço novo.

**8. Idade do preço, por combustível — decidido pelo Wesley em 2026-10-06**
(opção b). Recusadas: sem data, como no print, porque um preço de três meses
pareceria de hoje; e esconder preço antigo atrás de `—`, porque misturaria
"ninguém relatou" com "relatado faz tempo".

**9. Sem selos "Super Barato / Barato" — decidido pelo Wesley em 2026-10-06.**
"Barato" exige comparação, e com poucos relatos o único posto com preço viraria
"super barato" por falta de concorrente. Volta junto com a mediana, se voltar.

## Fora de escopo e dívidas

- **Gasolina aditivada e diesel S10** como colunas próprias. Exige separar
  `SupplyFuel`, o que muda formulário, consumo medido e relato.
- **Hora do abastecimento.** Só a data. A hora inventada de outro dia é coberta
  pela guarda do hodômetro (ver "A data do abastecimento").
- **Escolher o ponto num mapa.** É o mais preciso, mas exige `flutter_map` +
  tiles. Dependência nova, perguntar antes.
- **Mediana em vez do último preço.** Com esta tela o preço relatado passa a ser
  **visto por todos**, então o risco de envenenamento registrado na spec
  original deixa de ser teórico no dia em que houver muitos usuários. Com o
  teste fechado entre conhecidos, aceito. A defesa continua sendo a mediana de
  `precos`.
- **`gastop` com `allow read`.** A regra da casa é `get`, nunca `read`, em coleção
  legível por todos, e `gastop` é anterior a ela: `list` entrega `updatedBy`
  (uid) de toda a coleção. Esta spec passa a **usar** o `list` (o `whereIn`).
  Fechar depois exige trocar por `get` por id, que custa uma leitura por posto
  mesmo quando ele não existe.
- **Relato de hoje registrado tarde.** O caminho de hoje continua sendo batch,
  sem comparar, para funcionar sem sinal. Abastecimento das 8h registrado às 20h,
  com alguém tendo relatado às 15h: o das 8h ganha. É raro, mesmo dia, e o preço
  dificilmente mudou.
- **Logo na lista de abastecimentos** (`suppliesScreen`). Seria barato com
  `flagOf` pronto, mas não foi pedido.
- **`POSTO-IPIRANGA.png` tem 190×144 px** e já veio desfocado. A 48 px num
  iPhone (3×) ele é esticado, então se houver uma versão maior, vale trocar.
- **Raio de 5 km quando o de 3 km vem vazio**, previsto na spec original e nunca
  implementado. Continua de fora.

## Suposições

1. As colunas são Gasolina / Etanol / Diesel, sem comum × aditivada.
2. O filtro de texto age **só sobre a lista carregada** (o raio em volta do
   centro atual). Para achar um posto em outro bairro, "Outra localização".
3. Sem GPS, o `viewbox` do Nominatim cai na região de Fortaleza, o mesmo escopo
   do `bairros.dart`. Os resultados mostram a cidade, para "Centro" de outro
   lugar não passar despercebido.
4. **Em "Outra localização", `Supply.lat/lng` ficam nulos.** O campo diz "onde o
   usuário estava", e em casa isso é o endereço de quem registra, não o do abastecimento. O
   posto escolhido já carrega as próprias coordenadas.

## Perguntas em aberto

Nenhuma. As três da primeira versão viraram as decisões 7, 8 e 9.

---

# Plano de implementação

```
 (1) suburb ─┬─→ (3) filtro ─────────────────────┐
 (2) bandeira┘                                   │
 (4) Nominatim ──────────────────────────┐       │
 (5) preços (leitura) ─┐                 │       │
 (6) relato com data ──┤                 │       │
                       ▼                 ▼       ▼
               (8) stationCard ──→ (9) placeSearch ──→ (10) stationsScreen
                                                         │
 (7) campo Data no formulário ───────────────────→ (11) formulário usa a tela
                                                         │
                                                  (12) docs ──→ (13) aparelho
```

As tarefas 1 a 7 não mexem em tela nenhuma da lista de postos: são funções
puras, serviço e controller, todas testáveis sem simulador. **O app continua
funcionando igual depois de cada uma**, inclusive se a entrega parar no meio. A
7 é a exceção visível, e ela sozinha já resolve "registro no dia seguinte".

As 8 a 10 constroem a tela nova **ao lado** da antiga. Só a 11 troca o
formulário para usá-la e apaga o `StationPicker`. Até ali, nada que o usuário
vê depende de código pela metade.

## Pontos de verificação

| depois de | o que tem de estar verde |
|---|---|
| 7 | `flutter analyze lib/ test/` + `flutter test` inteiro. O app é o de hoje com o campo Data |
| 11 | o mesmo + `flutter build apk --debug` |
| 13 | o Wesley, no aparelho |

## Riscos

| Risco | Mitigação |
|---|---|
| Nominatim recusar cliente sem User-Agent, como a Overpass faz com `406` | Header fixo no serviço, com teste de que é enviado |
| Autocompletar por descuido (um `onChanged` disparando busca) e violar a política | A busca só existe em `onSubmitted`/botão; o teste de widget conta zero chamadas ao digitar |
| `—` aparecendo enquanto os preços carregam | Três estados explícitos no card, com teste para cada |
| `whereIn` com mais de 30 ids lançar | Quebra em blocos, com teste de 61 ids → 3 consultas |
| Relato de outro dia apagar preço mais novo | `shouldReplacePrice` puro e testado; transação só nesse caminho |
| Asset renomeado derrubar a lista | Teste que confere cada `StationFlag.asset` em disco |
| Os 17 testes do `StationPicker` sumirem sem substituto | Tarefa 11 só apaga o arquivo depois de os casos equivalentes estarem em `stationsScreen_test.dart` |
| Testes de widget "passarem" com texto quebrando no aparelho | Testar a causa (`Expanded`, `maxLines`), e a palavra final é a tarefa 13 |
| Disco encher no build iOS | `df -h /System/Volumes/Data` antes, e limpar antes em vez de depois |

---

# Tarefas

- [x] **1. Bairro do posto** (`FuelStation.suburb`) — 5 testes novos.
  - A fixture do bairro é um elemento **real** capturado em 06/10/2026 (Posto
    Aliança, Joaquim Távora). `addr:suburb` só com espaço vira `null`, não
    texto vazio: o card decide pela ausência se desenha a linha.
  - Verificar: `flutter test test/unit/overpass_test.dart test/unit/supply_test.dart`
  - Arquivos: `lib/model/supply.dart`, `lib/services/overpass.dart`, os dois testes

- [x] **2. Bandeira** (`Utils/stationFlag.dart`) — 13 testes.
  - Os apelidos de cada bandeira (`{'br', 'petrobras'}`) moram no enum e servem
    também ao filtro: quem busca "petrobras" acha o posto com logo da BR.
  - Verificar: `flutter test test/unit/stationFlag_test.dart`

- [x] **3. Filtro** (`Utils/stationFilter.dart`) — 8 testes.
  - Cada palavra da consulta tem de bater em algum campo: "shell serrinha"
    acha o Shell da Serrinha, não todo Shell mais todo posto da Serrinha.
  - Verificar: `flutter test test/unit/stationFilter_test.dart`

- [x] **4. Nominatim** (`services/geocoding.dart`) — 14 testes.
  - `addressdetails=1` em vez de picotar o `display_name`: a Maraponga voltou
    **sem `city`**, só com `municipality`, e o endereço da Bezerra de Menezes
    voltou **sem `name`**. A fixture tem os dois casos e os dois "Centro"
    (Fortaleza e Caucaia) — a busca real devolveu cinco cidades.
  - Verificado também **fora do teste**: a URL exata que o Dart monta, enviada
    ao Nominatim real, devolve HTTP 200 nos dois casos (com e sem posição).
  - Verificar: `flutter test test/unit/geocoding_test.dart`

- [x] **5. Leitura dos preços** (`model/stationPrices.dart` + `pricesFor`) — 11 testes.
  - **Pego pelo teste:** `readDouble` faz `as num?` e **lança** com texto. Um
    `"seis reais"` escrito por qualquer usuário em `gastop` derrubaria o posto
    inteiro; a leitura usa `is num` e ignora o valor ruim, um a um.
  - Verificar: `flutter test test/unit/stationPrices_test.dart`

- [x] **6. Relato com a data do abastecimento** — 13 testes novos.
  - `canReport` ganhou uma terceira condição: **data legível**. Sem ela,
    `pricedAt` e `precos.at` seriam uma idade inventada.
  - As partes puras (`stationFields`, `priceReport`, `shouldReplacePrice`,
    `reportsPastDay`) são testadas sem Firestore; o `report` só as compõe.
  - Verificar: `flutter test test/unit/supplyController_test.dart`

- [x] **7. Campo Data no formulário** — 9 testes novos.
  - `expenseDateFor` foi para `Utils/dated.dart`, e não para `expenseRules`
    como o plano dizia: aquele arquivo responde "vale perguntar ao veículo?", e
    este é o lugar comum de abastecimento **e manutenção** — que também grava
    sempre "agora" e poderá usar a mesma regra.
  - `AddSupply` ganhou um `saver` injetável, no padrão de `AddIter`, para o
    teste ver o que seria gravado.
  - **Ponto de verificação 1:** 0 erro e 0 aviso no analyze; 1276 testes
    passando, só o `widget_test.dart` de sempre falhando.

- [x] **8. O card** (`widget/stationCard.dart`) — 19 testes.
  - `formatDistance` e os testes dele vieram do `stationPicker.dart`.

- [x] **9. "Outra localização"** (`widget/placeSearch.dart`) — 9 testes.
  - Um teste digita letra a letra e conta **zero** chamadas ao buscador; outro
    toca duas vezes em "Buscar" durante a busca e conta **uma**.

- [x] **10. "Postos da região"** (`screens/stationsScreen.dart`) — 28 testes.
  - **Uma correção de comportamento que estava escondida:** o formulário
    mapeava Overpass fora do ar para `LocationFailure.failed`, e a tela dizia
    "Não foi possível obter sua localização" a quem tinha GPS funcionando.
    Agora `StationsSnapshot` volta com `failure: null, stations: null` nesse
    caso, e a frase é "Não foi possível buscar os postos agora". Tem teste.
  - Resposta atrasada de uma busca anterior (a lista de casa chegando depois
    da troca para a Maraponga) é descartada por um número de
    geração. Tem teste.

- [x] **11. O formulário usa a tela nova**
  - O teste do formulário injeta uma escolha pronta (`stationPicker`) em vez de
    navegar pela tela, que tem os testes dela. Um teste só abre a tela de
    verdade, para provar que a busca do GPS iniciada no formulário é a mesma
    que a tela usa (uma chamada, não duas).
  - `stationPicker.dart` e o teste dele saíram depois de os 15 casos terem
    equivalente: o único que faltava ("com Outro marcado, nenhum posto fica
    marcado") foi escrito antes de apagar.
  - **Ponto de verificação 2:** 0 erro e 0 aviso no analyze; 1321 testes
    passando, só o `widget_test.dart` de sempre falhando; `flutter build apk
    --debug` ✅.

- [x] **12b. O título é o nome, não a bandeira** — pedido depois do primeiro
  teste no simulador, que mostrava "Shell", "Shell", "Chevron" ao lado dos
  logos. `FuelStation.address` novo; `stationTitle` cai para o endereço e
  depois para "Posto sem nome"; o filtro acha pela rua. O simulador estava na
  localização padrão (Cupertino), onde quase nenhum posto tem nome no OSM.

- [x] **12. Documentação** — seção "Postos da região" no `CLAUDE.md`;
  `abastecimento.md` aponta para esta spec.

- [x] **13. Verificação** — feita pelo Wesley em 2026-10-06: o abastecimento
  do dia anterior foi registrado com a data de ontem pela tela nova. O
  primeiro teste, no simulador, gerou a tarefa 12b.
  - Aceite: logos nítidos no círculo; em casa, "Outra localização" →
    "Maraponga" → escolher → salvar → conferir `iter/{uid}/supply` (com a data
    de ontem) e `gastop/{id}.pricedAt` no console; com a localização negada,
    escolher posto por outra localização.
  - Antes do build iOS: `df -h /System/Volumes/Data`.
