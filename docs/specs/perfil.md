# Spec: Dialog de Perfil

Status: **implementada** · Criada em 2026-08-01 · Falta verificar no simulador

## Objetivo

Tocar no avatar da `AppBar` abre um dialog quase em tela cheia com o perfil do
usuário: banner colorido com a foto sobreposta, nome e apelido, três métricas
grandes de carreira, três menores de desempenho, e um botão de compartilhar
ainda sem ação.

Hoje o avatar não faz nada. As métricas existem espalhadas nos documentos das
rotas e nunca foram somadas em lugar nenhum — o entregador não tem onde ver
"quanto eu já rodei desde que comecei".

Usuário: o entregador. Sucesso = ele abre, bate o olho e vê o tamanho do que já
fez, sem precisar de nenhuma tela de gráfico.

## Layout

```
┌──────────────────────────────────────────┐
│ ▓▓▓▓▓▓▓▓ banner azul ▓▓▓▓▓▓▓▓▓▓▓▓▓▓  [X] │  ← fechar no canto
│ ▓▓▓▓▓▓▓▓▓▓▓ ╭────────╮ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
│─────────────│ foto   │──────────────────│  ← foto cavalga a borda
│             ╰────────╯                   │
│              Wesley Nogueira              │
│               @wesley-efmg                │
│                                           │
│     128          3 412          2 890     │  ← métricas grandes
│    Rotas        Pacotes        Paradas    │
│                                           │
│  ──────────────────────────────────────  │
│   Insucesso 1,4% · Shopee 62% · 6h30     │  ← métricas menores
│                                           │
│         ┌──────────────────────┐          │
│         │     COMPARTILHAR     │          │
│         └──────────────────────┘          │
└──────────────────────────────────────────┘
```

A foto "interpolada" da referência é um `Stack`: o banner tem altura fixa e o
`CircleAvatar` fica com metade dele para fora, sobre o fundo branco.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1 · cloud_firestore 6.7.1 · firebase_auth 6.5.6.
**Nenhuma dependência nova.** `StreamBuilder` + `setState`, como no resto do app.

Banner no azul do app — o mesmo gradiente dos cards de gráfico
(`0xFF0D47A1 → 0xFF1976D2 → 0xFF42A5F5`), e não o roxo da referência, para o app
não ganhar uma terceira cor de marca.

## Comandos

```bash
flutter pub get
flutter run
flutter analyze lib/                     # sem error/warning novo
flutter test test/unit/profileStats_test.dart
flutter test test/widget/profileDialog_test.dart
flutter test                             # widget_test.dart segue quebrado (template)
```

## Estrutura

```
lib/Utils/profileStats.dart        → as métricas de carreira, puras (novo)
lib/widget/profileDialog.dart      → o dialog (novo)
lib/screens/home.dart              → avatar vira botão que abre o dialog
test/unit/profileStats_test.dart   → as contas (novo)
test/widget/profileDialog_test.dart → o dialog montado à mão (novo)
```

`profileStats.dart` e não mais funções em `routeStats.dart`: aquele arquivo é
sobre **um período**, e todas as suas funções recebem uma lista já filtrada. As
métricas daqui são de carreira inteira e agregam coisas que os gráficos não
usam (paradas, duração média). Misturar os dois deixaria `routeStats` com duas
noções de recorte no mesmo lugar.

O que já existe é reaproveitado em vez de recopiado: `realized`, `failuresOf` e
`countPerCompany` saem de `routeStats.dart`; `RouteTime.formatDuration`
formata a duração.

## Dados

Origem: `iter/{uid}/routes` via `RouteController.watchAll(uid)` — **sem filtro de
período**, e `user/{uid}` via `UserController.watch(uid)` para o apelido.

| campo | uso |
|---|---|
| `status` | recorte "realizadas" (`concluido` + `pago`) |
| `packages` | pacotes carregados |
| `insucessoQnt` / `isInsucesso` | descontados dos pacotes e base da taxa |
| `stops` | paradas |
| `company` | empresa mais rodada |
| `startAt` / `endAt` | duração média |

Nada é escrito. O dialog é somente leitura.

## Como cada métrica é calculada

Todas sobre as rotas **realizadas** (`concluido` + `pago`), de qualquer data. O
mesmo motivo de sempre: rota agendada ainda não entregou pacote nenhum.

**Rotas** — contagem.

**Pacotes entregues** — `Σ packages − Σ insucessos`. Só rotas com `packages`
preenchido entram; o insucesso de uma rota sem pacotes informados não tem de
onde ser descontado e é ignorado nos dois lados.

**Paradas** — `Σ stops`, das rotas que informaram.

**Taxa de insucesso** — `Σ insucessos ÷ Σ packages × 100`, mesma conta do card
"Índice de insucesso" da tela de gráficos. `null` quando ninguém informou
pacotes, e aí a métrica mostra `—` em vez de `0%`.

**Empresa mais rodada** — a de maior número de rotas, com sua participação:
`Shopee · 62%`. Empate resolve pelo nome, para o rótulo não dançar entre dois
rebuilds.

**Tempo médio** — média de `endAt − startAt`, **só das rotas que têm `endAt`**.
Rota sem hora de fim é ignorada em vez de contar como zero, o que puxaria a
média para baixo. `null` quando nenhuma tem, e a métrica mostra `—`.

Durações não positivas são descartadas: `RouteTime.resolveEnd` já rola a virada
do dia na gravação, então uma duração negativa é dado corrompido, não rota de
madrugada.

## Estilo de código

Uma classe de resultado e uma função que a monta numa passada, como
`PeriodSummary`/`summarize`:

```dart
/// Números de carreira do perfil. Tudo `null` que aqui aparece significa
/// "não dá para calcular", nunca zero.
class ProfileStats {
  const ProfileStats({
    required this.routes,
    required this.deliveredPackages,
    required this.stops,
    this.failureRate,
    this.topCompany,
    this.averageDuration,
  });

  final int routes;
  ...
}

ProfileStats profileStats(List<NewRouteModal> routes) { ... }
```

Função pura sobre `List<NewRouteModal>`, sem Firestore e sem `BuildContext` —
testável sem mock nenhum. Texto de interface em pt-BR. Arquivos em camelCase.

## Reuso para outros perfis

O dialog **recebe** o que mostra em vez de ler o usuário logado:

```dart
showProfileDialog(
  context,
  name: ...,
  nickName: ...,
  photoUrl: ...,
  stats: ...,
);
```

Custo zero agora e a aba Friends só precisa passar outro `uid`. Por isso o botão
de ação é um parâmetro (`actionLabel` + `onAction`): hoje entra como
"Compartilhar / em desenvolvimento", amanhã a Friends passa "Seguir" sem tocar
no widget.

Quem busca os dados é um wrapper na `home.dart`, não o widget.

## Estados

1. **Carregando** — o dialog abre na hora com o nome e a foto (que a `AppBar`
   já tem) e um shimmer discreto no lugar dos números. Segurar o dialog fechado
   esperando o Firestore faria o toque parecer que não funcionou.
2. **Erro ao ler as rotas** — nome e foto continuam; no lugar das métricas, uma
   linha "Não foi possível carregar suas métricas." Sempre `debugPrint`.
3. **Sem rota nenhuma** — zeros nas três grandes e `—` nas três menores, com uma
   linha "Cadastre sua primeira rota para ver seus números."
4. **Sem foto** — a inicial do nome, como a `AppBar` já faz.
5. **Métrica incalculável** — `—`, nunca `0%` nem `0h`.

## Estratégia de teste

`test/unit/profileStats_test.dart` (sem Firebase, sem widget):

- só `concluido` e `pago` entram; agendada e em andamento ficam fora;
- pacotes entregues descontam os insucessos;
- rota com insucesso e sem `packages` não entra em nenhum dos dois lados;
- paradas somam só as informadas; `null` não vira zero à toa;
- taxa de insucesso é `null` sem pacotes informados (sem divisão por zero);
- empresa mais rodada devolve rótulo e participação; empate resolve pelo nome;
- tempo médio ignora rota sem `endAt` em vez de contá-la como zero;
- duração não positiva é descartada;
- lista vazia devolve zeros e `null`s, sem lançar.

`test/widget/profileDialog_test.dart`: monta o dialog com `ProfileStats` à mão e
verifica nome, apelido, os seis números, o `—` das métricas nulas, o botão de
fechar e o aviso "em desenvolvimento" ao tocar no botão de ação. Não toca em
rede.

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; texto em pt-BR; dados recebidos por
  parâmetro; conta em `Utils/profileStats.dart`, nunca dentro do `build`;
  `withValues(alpha:)` no lugar de `withOpacity`.
- **Perguntar antes:** qualquer dependência nova; mudar `NewRouteModal`, `Users`
  ou o formato gravado; mexer em `addIter.dart`; mudar `firestore.rules`.
- **Nunca:** escrever, alterar ou apagar documento (o dialog é read-only);
  implementar o compartilhamento de verdade nesta entrega.

## Critérios de sucesso

- [ ] Tocar no avatar da `AppBar` abre o dialog; o `X` e o toque fora fecham.
- [ ] Banner azul com a foto sobreposta na borda, nome e `@apelido`.
- [ ] Três métricas grandes: rotas, pacotes entregues (já sem os insucessos) e
      paradas.
- [ ] Três menores: taxa de insucesso, empresa mais rodada com a participação, e
      tempo médio de conclusão.
- [ ] Métrica sem como ser calculada mostra `—`, não `0`.
- [ ] Botão "Compartilhar" avisa que está em desenvolvimento e não faz mais nada.
- [ ] Usuário sem rota nenhuma vê zeros e a dica de cadastrar a primeira, sem
      tela quebrada.
- [ ] O dialog não lê o usuário logado por dentro — recebe tudo por parâmetro.
- [ ] `flutter analyze lib/` sem error/warning novo.
- [ ] Os dois testes novos passam e os 99 que já existem continuam passando.

## Decisões

**1. Métricas de carreira, sem filtro de período.** O avatar vive na `AppBar`,
acima das abas, fora de qualquer filtro de data. E perfil é identidade: número
que só cresce serve de motivação, enquanto "últimos 30 dias" zeraria o perfil
depois de um mês parado.

**2. `profileStats.dart` separado de `routeStats.dart`.** O segundo é sobre um
período e recebe listas já filtradas; este é sobre a carreira inteira e agrega
paradas e duração, que os gráficos não usam. O que dá para reusar é importado,
não copiado.

**3. O dialog recebe os dados, não os busca.** Deixa o widget testável sem
Firebase e serve a aba Friends depois só passando outro `uid`. O botão de ação
é parâmetro pelo mesmo motivo: "Compartilhar" hoje, "Seguir" amanhã, sem tocar
no widget.

**4. `null` é diferente de zero.** "Taxa de insucesso 0%" e "não dá para
calcular a taxa porque ninguém preencheu pacotes" são coisas diferentes, e a
segunda vira `—`. Foi a mesma decisão do card de índice na tela de gráficos.

**5. Abrir na hora, preencher depois.** Nome e foto já estão na `AppBar`, então
o dialog abre com eles imediatamente e só os números esperam o Firestore. Um
toque que não responde por meio segundo parece um toque que não funcionou.

## Dívidas e fora de escopo

- **Compartilhamento de verdade** — o botão é um `showNotification` de "em
  desenvolvimento". Fazer valer exige decidir *o que* se compartilha (imagem?
  link? texto?) e provavelmente uma dependência (`share_plus`).
- **Coleção inteira baixada** — mesma dívida da lista e dos gráficos. O dialog
  reusa o mesmo stream, então não é uma leitura nova, mas também não resolve.
- **Editar o perfil** (foto, nome, apelido) fica fora: o apelido inclusive não
  tem UI de troca de propósito, ver `CLAUDE.md`.
- Seguir/seguidores, conquistas, comparação com outros entregadores e histórico
  por período dentro do perfil.

## Perguntas em aberto

Nenhuma bloqueante. Cor do banner, escopo das métricas e reuso para outros
perfis foram confirmados antes desta spec.

---

# Plano de implementação

```
 (1) Utils/profileStats.dart ──→ (2) widget/profileDialog.dart ──→ (3) home.dart
      teste primeiro                  teste de widget                 fiação
```

Só três passos, e o primeiro carrega o risco todo: é onde mora divisão por zero,
`null` virando zero e média afundada por rota sem hora de fim.

**Leitura das rotas: `fetchAll`, não `watchAll`.** A `ListIterScreen` e a
`GraficsScreen` já mantêm um listener cada na mesma coleção; abrir um terceiro
permanente na `HomeScreen` para um dialog que quase nunca é aberto é listener
parado consumindo à toa. `fetchAll` é uma leitura só, no toque, e o Firestore
serve do cache local que os outros dois já preencheram.

## Riscos

| Risco | Mitigação |
|---|---|
| Foto sobreposta cortada pelo `clipBehavior` do `Dialog` | O `Stack` reserva a altura do banner **mais** o raio que vaza; nada depende de `Clip.none` atravessar a borda do card. |
| Dialog maior que a tela em aparelho pequeno | Conteúdo dentro de `SingleChildScrollView`; teste de widget roda numa tela baixa. |
| `showNotification` sobre um `Dialog` | O widget não conhece o toast: recebe `onAction` e a `home.dart` decide o que fazer. O teste verifica que o callback disparou. |
| Métricas nulas mostrando `0` | Coberto por teste na tarefa 1, antes de existir tela. |
| Pacotes entregues negativo (insucessos > pacotes em dado corrompido) | `clamp` em zero, com teste. |

Checkpoint depois de cada tarefa: `flutter analyze lib/` sem nada novo, mais o
teste da tarefa.

---

# Tarefas

- [x] **1. `profileStats.dart` — as contas, com teste primeiro**
  - Aceite: `ProfileStats` + `profileStats(List<NewRouteModal>)` cobrindo os
    seis números e devolvendo `null` no que não dá para calcular. Todos os casos
    da "Estratégia de teste" escritos **antes** da implementação.
  - Verificar: `flutter test test/unit/profileStats_test.dart`
  - Arquivos: `lib/Utils/profileStats.dart`, `test/unit/profileStats_test.dart`

- [x] **2. `profileDialog.dart` + teste de widget**
  - Aceite: banner, foto sobreposta, fechar, nome/apelido, três métricas
    grandes, três menores, botão de ação por parâmetro; estados de carregando,
    erro e sem rota.
  - Verificar: `flutter test test/widget/profileDialog_test.dart`
  - Arquivos: `lib/widget/profileDialog.dart`,
    `test/widget/profileDialog_test.dart`

- [x] **3. Ligar no avatar da `HomeScreen`** — a AppBar passou a ter **um**
  `StreamBuilder` na linha inteira, em vez de um só no nome: o avatar precisa do
  mesmo apelido para levá-lo ao dialog, e duas assinaturas do mesmo stream
  seriam duas escutas do mesmo documento.
  - Aceite: tocar no avatar abre o dialog com nome, apelido e foto que a
    `AppBar` já tem, e as métricas de `RouteController.fetchAll`. O botão avisa
    "em desenvolvimento".
  - Verificar: `flutter analyze lib/` e `flutter test`
  - Arquivos: `lib/screens/home.dart`

- [ ] **4. Verificação no simulador**
  - Aceite: abrir, conferir os seis números, fechar pelo `X` e pelo toque fora.
  - Verificar: `flutter run`
