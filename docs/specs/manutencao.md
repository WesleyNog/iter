# Spec: Registro de Manutenção

Status: **concluída** · Criada, aprovada e implementada em 2026-08-06 ·
Verificada em aparelho em 2026-08-06

## Objetivo

Ligar a "Manutenção" do menu "+", hoje marcada *Em breve*, a uma tela de
registro manual: o que passou pela manutenção, se foi reparo ou substituição,
quanto custou, em qual oficina e uma descrição.

É a última peça do lado das despesas. O card de gastos do Resumo já reserva a
linha "Manutenção — em breve" e `ExpenseSummary.maintenance` já existe zerado,
**de propósito**, desde `abastecimento.md`. Nada precisa ser redesenhado.

Usuário: o entregador. Sucesso = o pneu de R$ 2.400 deixa de ser invisível no
app, e o preço que ele pagou de verdade pode corrigir o chute que está no
cadastro do veículo.

Diferente do abastecimento: **sem API e sem coleção global**. Entrada manual, só
do usuário. Parceria com oficina é ideia de futuro, não desta entrega.

## ⚠️ Gasto é extrato, não dedução — de novo

Vale aqui exatamente como valeu para o combustível. A provisão de rota **já
cobra peças** (`km × Σ taxas`). Somar ou subtrair o gasto real do lucro contaria
a peça duas vezes.

O card de gastos continua sendo extrato, com a linha que já avisa disso.
**Nenhuma mudança no lucro dos cards de empresa.**

## Modelo

`iter/{uid}/maintenance/{id}` — subcoleção irmã de `routes`, `vehicles` e
`supply`, com a mesma regra: só o dono lê e escreve.

| campo | tipo | |
|---|---|---|
| `id` | String | `Uuid().v4()` |
| `vehicleId` | String? | padrão: o veículo em uso |
| `item` | String | um dos 13 do enum |
| `action` | String | `reparo` \| `substituicao` |
| `value` | double | **obrigatório**, > 0 |
| `workshop` | String? | oficina, texto livre |
| `description` | String? | texto livre |
| `odometer` | double? | KM do painel |
| `date` / `createdAt` | String | ISO 8601 |

### Os 13 itens

Pneu · Motor · Óleo do motor · Óleo de freio · Pastilha de freio · Bateria ·
Amortecedor · Embreagem · Correia · Filtros · Revisão · Funilaria · Outros

Os sete que o Wesley listou, mais seis somados na conversa. **Bateria** era a
ausência que mais importava: é uma das cinco peças que ele já provisiona no
veículo, e sem ela na lista trocar a bateria cairia em "Outros" — perdendo a
correção de preço.

`MaintenanceItem.vehiclePartName` mapeia para a peça do cadastro:

| item | peça no veículo |
|---|---|
| Pneu | `Pneu` |
| Óleo do motor | `Óleo` |
| Pastilha de freio | `Freio` |
| Bateria | `Bateria` |
| os outros nove | — (sem correspondência) |

## Corrigir o preço da peça

`lib/Utils/expenseRules.dart` (o `supplyRules.dart` renomeado — é a mesma ideia,
"este gasto deve corrigir o cadastro do veículo?").

**Só em Substituição.** Consertar um pneu por R$ 80 não é o preço de um pneu
novo, e é exatamente para essa distinção que o toggle existe.

Não oferece quando: não há veículo; a ação é Reparo; o item não tem peça
correspondente; o veículo não tem peça com aquele nome (comparação normalizada,
porque a lista de peças é editável e ele pode ter renomeado); ou o preço já é
praticamente o mesmo.

O diálogo mostra a divisão **explícita**:

```
Substituição de Pneu — R$ 2.400,00
R$ 2.400,00 ÷ 4 pneus = R$ 600,00 cada
O Fit está com R$ 500,00. Atualizar?
Isso muda o custo por km das próximas rotas.
[ Agora não ]  [ Atualizar ]
```

Trocar só dois dos quatro pneus daria um valor errado — mitigado por mostrar a
conta e **nunca** atualizar sozinho. Registrado em Dívidas.

## O extrato passa a ser misto

O "Detalhar" listava só abastecimentos; passa a listar **os dois, por data**. A
junção é função pura, fora do widget:

```dart
enum ExpenseKind { abastecimento, manutencao }

typedef ExpenseRow = ({
  String date, String title, String subtitle, double value, ExpenseKind kind,
});

List<ExpenseRow> expenseRows(List<Supply> s, List<Maintenance> m);
```

## O card muda de comportamento

A linha "Manutenção" para de dizer **"em breve"** e passa a mostrar o valor,
**inclusive `R$ 0,00`**. A partir daqui zero é **afirmação** ("não gastei com
peça no período"), não ausência de informação. `hasMaintenance` deixa de existir
e o teste dele muda de sentido.

A linha de contexto ganha a contagem:
`2 abastecimentos · 1 manutenção · 72,5 L`.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1. **Nenhuma dependência nova.**

Reusa: `CurrencyFormatterHelper` e `parseKm` (`Utils/currencyFormat.dart`),
`VehicleController.fetchActive`, o padrão de carregador injetável de
`AddSupply`, `readEnum`/`readDouble` (`Utils/mapRead.dart`).

## Comandos

```bash
flutter analyze lib/ test/
flutter test
flutter build apk --debug
firebase deploy --only firestore:rules
flutter run
```

## Estrutura

```
lib/model/maintenance.dart                 → modelo + os dois enums (novo)
lib/controller/maintenanceController.dart  → CRUD (novo)
lib/screens/addMaintenance.dart            → o formulário (novo)
lib/Utils/supplyRules.dart                 → vira expenseRules.dart
lib/Utils/expenseSummary.dart              → manutenções + expenseRows
lib/widget/expenseCard.dart                → linha real + contagem
lib/screens/suppliesScreen.dart            → vira expensesScreen.dart
lib/screens/summaryScreen.dart             → segundo stream
lib/screens/home.dart                      → 'Manutenção' ganha onTap
firestore.rules                            → + maintenance
```

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; texto em pt-BR; contas em `Utils/`;
  `null` para "não dá para calcular".
- **Perguntar antes:** qualquer dependência nova; mexer no cálculo da provisão.
- **Nunca:** subtrair gastos do lucro dos cards de empresa; atualizar o preço da
  peça sem o usuário mandar; oferecer correção em **Reparo**.

## Critérios de sucesso

- [ ] "Manutenção" perde o selo *Em breve* e abre a tela.
- [ ] Dropdown com os 13 itens, toggle Reparo/Substituição, valor obrigatório,
      oficina, descrição e hodômetro opcionais.
- [ ] Salvar grava em `iter/{uid}/maintenance/{id}`.
- [ ] Substituição de peça mapeada **pergunta** se corrige o preço, mostrando a
      divisão pela quantidade.
- [ ] Reparo **nunca** oferece a correção.
- [ ] O card de gastos soma combustível + manutenção e mostra a contagem.
- [ ] O "Detalhar" lista os dois tipos intercalados por data.
- [ ] O lucro dos cards de empresa **não muda**.
- [ ] `flutter analyze lib/` sem error/warning novo; os 504 testes atuais
      continuam passando.

## Dívidas e fora de escopo

- **Parceria com oficina / monetização** — nada global nesta entrega.
- **Lembrete por KM** — o hodômetro passa a ser gravado; a conta "faltam
  2.300 km" é a spec seguinte, junto com o consumo real.
- **Vários itens num registro** — decidido: um por registro.
- **Substituição parcial do jogo** (2 dos 4 pneus) — o diálogo mostra a conta.
- **Editar e excluir manutenção** — só cadastro e listagem.
- **Anexar nota fiscal** — traria a discussão de base64 x Storage de novo.

---

# Tarefas

- [x] **1. `model/maintenance.dart`** — 14 testes.
  - **Ação desconhecida cai em `reparo`**, não em `substituicao`: é o padrão
    conservador, porque reparo nunca dispara a oferta de corrigir o preço da
    peça. Um documento estranho não consegue mexer no cadastro do veículo.
  - Um teste percorre `Vehicle.defaultParts` e confere que **todo**
    `vehiclePartName` mapeado existe lá. Renomear uma peça padrão sem atualizar
    o mapa faria a oferta de correção sumir **em silêncio** — o teste denuncia
    antes.
- [x] **2. `Utils/expenseRules.dart`** — renomear + `shouldOfferPartUpdate` —
  18 testes; os de `shouldOfferPriceUpdate` seguem passando após o rename.
  - O mapa de acentos ia virar a **terceira** cópia no projeto. Extraí
    `normalizeKey` para `Utils/text.dart` e refiz o `_slug` do `carImage.dart`
    em cima dele. `nicknameController` mantém a cópia própria de propósito — o
    regex dele está espelhado no `firestore.rules` e não tem teste.
  - `matchingPart` compara **normalizado**, então "OLEO" acha "Óleo". Mas peça
    **renomeada** (`Freio` → `Pastilha`) quebra o vínculo de propósito: são
    nomes diferentes, e adivinhar seria pior que não oferecer nada. Tem teste
    afirmando esse `null`.
  - Dois testes cercam o Reparo — barato e caro — porque é ali que aceitar o
    valor destruiria a provisão: R$ 80 de conserto viraria o preço de um pneu.
- [x] **3. `controller/maintenanceController.dart` + `firestore.rules`** — 6
  testes novos. **Regras publicadas** no `iter-mn`.
  - O `sortByDate` seria a **terceira** cópia da mesma ordenação. Virou
    `Utils/dated.dart`: uma interface `Dated { id, date }` que `Supply` e
    `Maintenance` implementam, e um `sortByDateDesc<T extends Dated>`
    compartilhado. `SupplyController.sortByDate` passou a delegar, e seus 17
    testes seguem passando.
  - Isso também prepara a tarefa 4: o extrato misto precisa tratar os dois
    tipos igual, e agora o tipo diz que dá.
  - **Sem coleção global**, ao contrário do abastecimento: oficina é texto
    livre e nada sai do documento do usuário. Está escrito na regra, para
    ninguém procurar a contraparte que não existe.
- [x] **4. `Utils/expenseSummary.dart`** — manutenções e `expenseRows` — 29
  testes (13 novos de `expenseRows`, 16 no `expenseSummary` revisado).
  - `suppliesInPeriod` virou `inPeriodByDate<T extends Dated>` em
    `Utils/dated.dart`: o filtro de período era idêntico para os dois tipos,
    como a ordenação já era.
  - `expenseRows` junta e **intercala** — tem teste provando que não é
    concatenação disfarçada (novo · manutenção do meio · velho).
  - Rótulos com cuidado nas ausências: abastecimento sem posto vira "Posto não
    informado"; manutenção sem oficina não deixa um `·` solto no fim.
  - A tela e o card quebraram com a mudança de assinatura, como esperado —
    consertei o mínimo para a árvore compilar e deixei um `TODO` apontando a
    tarefa 7. As tarefas 6 e 7 fazem o trabalho de verdade.
- [x] **5. `screens/addMaintenance.dart`** — 17 testes.
  - **Três testes de largura**, e não confiança: o toggle e o valor lado a lado
    é exatamente o arranjo que estourou no formulário de rota num Android de
    360 px. Os testes montam a tela em **360, 320 e 320 com o seletor de
    veículo** e falham se houver `RenderFlex overflowed`. Os dois em `Expanded`,
    o `SegmentedButton` com densidade compacta e sem ícone de seleção.
  - `isExpanded: true` nos dois dropdowns desde o começo — foi o defeito que a
    tela de rota teve.
  - `VehiclesSnapshot` saiu de `addSupply.dart` para `vehicleController.dart`:
    as duas telas de gasto precisam do mesmo par, e uma importar a outra seria
    acoplamento entre telas.
  - `withPartPrice` devolve o **mesmo objeto** quando não há peça
    correspondente, então nenhum caminho futuro consegue gravar preço na peça
    errada. Vida útil e quantidade não mudam: a manutenção sabe quanto custou,
    não quanto vai durar.
- [x] **6. `widget/expenseCard.dart`** — 17 testes (5 novos).
  - O teste do "em breve" **virou o contrário**: agora afirma
    `R$ 0,00` **e** que "em breve" não aparece em lugar nenhum. É a mesma
    distinção de sempre, só que desta vez ela vira de lado — o app passou a
    saber, então zero deixou de ser ausência e virou afirmação.
  - Contagem zerada **não entra** na linha de contexto: "0 manutenções" seria
    ruído, e a linha do valor logo acima já disse que foi zero. Vale nos dois
    sentidos — período só com manutenção não mostra "0 abastecimentos".
  - O aviso de rodapé passou a dizer "provisão de combustível **e peças**": a
    provisão sempre cobriu as duas frentes, mas só agora o card soma as duas, e
    a frase precisava acompanhar para continuar impedindo a subtração de
    cabeça.
- [x] **7. `expensesScreen.dart` + `summaryScreen.dart` + `home.dart`**
  - `suppliesScreen` virou `expensesScreen`: lista os dois tipos com ícone por
    natureza (bomba laranja, chave cinza), para distinguir de relance sem ler a
    linha de baixo.
  - **Se qualquer um dos dois streams falhar, o card de gastos some inteiro.**
    Mostrar só a metade que carregou deixaria o total menor do que é, com cara
    de número certo — e um total de gastos subestimado é justamente o erro que
    passa despercebido. Os cards de empresa acima continuam de pé.
  - A tela de detalhe recebe as **mesmas listas** que o card somou, então o
    extrato não tem como discordar do total que levou o usuário até lá.
  - `Manutenção` perdeu o selo pelo mesmo mecanismo do abastecimento: ganhar
    `onTap` apaga o `comingSoon`. As três ações do menu "+" agora funcionam.
- [x] **8. Verificação no aparelho** — feita pelo Wesley em 06/08/2026.
  Confirmado: **Reparo não oferece** corrigir preço, **Substituição oferece**,
  as duas manutenções gravaram, o extrato listou os dois tipos e o card somou.
