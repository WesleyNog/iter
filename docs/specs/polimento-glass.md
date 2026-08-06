# Spec: Polimento do vidro da navegação

Status: **proposta** · Criada em 2026-08-05 · Aguardando aprovação

## Objetivo

Deixar a `GlassNavBar` mais parecida com vidro de verdade — brilho especular na
borda de cima, borda com espessura, indicador que assenta sobre a superfície —
**sem dependência nova**, e de quebra unificar o material de vidro que hoje está
copiado em quatro lugares.

Usuário: o entregador, que olha essa barra em toda tela do app. Sucesso = a
barra parece ter espessura e material, e os quatro elementos de vidro do app
parecem o mesmo material.

### Por que não o `liquid_glass_easy`

Avaliado e descartado, com o registro aqui para ninguém reabrir a discussão do
zero. O pacote é Dart puro (sem código nativo), MIT, compatível com o SDK do
projeto e funciona no Android — o Impeller é padrão em Android 10+. Não é ruim.

Não entra por três razões, em ordem de peso:

1. **O fundo do app é branco.** `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`
   no tema claro. Liquid glass é sobre **refratar o que está atrás**, e não há o
   que refratar. O ganho visual, neste app, é perto de zero.
2. **O custo cai no pior lugar.** A barra flutua sobre listas que rolam, então
   cada frame de scroll invalida o backdrop e redesenha o shader. O público é
   entregador em Android intermediário com o celular ligado o dia inteiro.
3. **O pacote ainda está se achando.** Repositório de 9 meses, 2 contribuidores,
   **três majors** (duas quebras de API), 9 releases em 48 dias, publisher não
   verificado — e uma issue *"touch not working"* aberta em 05/08/2026. Numa
   barra de navegação, toque é a única coisa que não pode falhar.

Se um dia o app ganhar fundo escuro, foto ou gradiente cheio atrás da barra, a
conta muda e vale reavaliar.

## A deriva que esta spec fecha

A superfície de vidro existe **quatro vezes**, e já divergiu:

| widget | opacidade | API de cor |
|---|---|---|
| `GlassNavBar` | 0,55 | `withOpacity` (depreciada) |
| `GlassPill` | 0,60 | `withOpacity` |
| `GlassCircleButton` | 0,55 | `withOpacity` |
| `CreateActionSheet` | 0,75 | `withValues` ✅ |

O sheet foi escrito depois e já usa a API nova; os outros três ficaram para trás.
São **10 usos de `withOpacity` depreciados** só em `glassNavBar.dart`, e três
opacidades diferentes para o que deveria ser um material só.

A opacidade do sheet (0,75) **continua diferente de propósito**: ele carrega
texto, e texto sobre vidro claro precisa de mais fundo para ser legível do que
ícone. Vira parâmetro documentado, não valor solto.

## Layout

```
   ╭───────────────────────────────────────╮
   │▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔│ ← brilho especular no topo
   │   ▄▄▄▄▄                               │
   │  ▐ 📊 ▌   🧾      ◎       👥          │ ← indicador com leve sombra
   │   ▀▀▀▀▀                               │
   ╰───────────────────────────────────────╯
    ▔ borda clara em cima, escura embaixo = espessura
```

Quatro mudanças, todas em Flutter puro:

1. **Brilho especular** — gradiente branco do topo até ~40% da altura,
   `IgnorePointer`, estático. É o que mais dá sensação de vidro, e é o mais
   barato: não repinta no scroll.
2. **Borda com gradiente** — clara em cima, quase transparente embaixo. Hoje é
   uma borda branca uniforme, que lê como contorno e não como espessura.
   `Border.all` só aceita cor sólida, então são dois containers: o de fora com
   o gradiente, o de dentro com o preenchimento, 1px de recuo.
3. **Indicador assentado** — o retângulo azul ganha um gradiente sutil e uma
   sombra curta, para parecer apoiado sobre o vidro em vez de recortado nele.
4. **Ícone selecionado com micro-escala** — `1.0 → 1.06` junto com o deslize do
   indicador, na mesma curva. Toque que responde parece toque que funcionou.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1. **Nenhuma dependência nova** — esse é o ponto.
`BackdropFilter` + `ImageFilter.blur`, como já é hoje.

## Comandos

```bash
flutter analyze lib/ test/                      # as 10 depreciações somem
flutter test test/widget/glassSurface_test.dart
flutter test test/widget/glassNavBar_test.dart
flutter test
flutter run                                     # o julgamento final é o olho
```

## Estrutura

```
lib/widget/glassSurface.dart          → o material de vidro, um só (novo)
lib/widget/glassNavBar.dart           → os três widgets passam a usá-lo
lib/widget/createActionSheet.dart     → idem
test/widget/glassSurface_test.dart    → (novo)
test/widget/glassNavBar_test.dart     → ganha casos de comportamento
```

## Código

Um widget de superfície, e os quatro lugares passam a compô-lo:

```dart
/// O material de vidro do app — um só, para os quatro lugares que o usam não
/// derivarem de novo.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 18,
    this.opacity = 0.55,
    this.borderRadius,
    this.circle = false,
    this.padding,
    this.shadow,
  });

  /// Quanto do fundo aparece. O padrão serve para ícone; superfície com
  /// **texto** sobe para ~0,75, senão o contraste some.
  final double opacity;
  ...
}
```

Arquivos em camelCase, texto de interface em pt-BR, `withValues(alpha:)` em
todo lugar.

## Estratégia de teste

Aparência não se testa em `flutter test` — o julgamento é no simulador. O que dá
para travar é **estrutura e comportamento**, e é o que quebra sem ninguém ver:

`test/widget/glassSurface_test.dart`:

- desenha o filho recebido;
- exatamente **um** `BackdropFilter` por superfície (camada duplicada é blur
  aplicado duas vezes, que fica leitoso e custa o dobro);
- a camada de brilho é `IgnorePointer` — brilho que rouba toque é o defeito mais
  fácil de introduzir aqui;
- `circle: true` recorta em oval, `circle: false` em retângulo arredondado.

`test/widget/glassNavBar_test.dart` (já existe, ganha casos):

- os dois testes atuais de `MediaQuery`/`extendBody` continuam passando;
- N itens desenham N ícones;
- tocar no item *i* chama `onTap(i)` — inclusive no item já selecionado;
- o badge aparece com `pendingCount > 0` no índice certo e some com zero;
- o `trailing` aparece quando informado e não ocupa espaço quando nulo;
- toque no `trailing` **não** dispara `onTap` da barra.

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; `withValues(alpha:)`; nenhuma
  dependência nova; os quatro lugares usando o mesmo `GlassSurface`.
- **Perguntar antes:** mudar cor de marca, altura ou raio da barra; mexer no
  tema de `main.dart`; mudar a assinatura pública de `GlassNavBar`
  (`home.dart` depende dela).
- **Nunca:** adicionar `liquid_glass_easy` ou outro pacote de efeito nesta
  entrega; empilhar um segundo `BackdropFilter` sobre o primeiro; deixar a
  camada de brilho capturar toque.

## Critérios de sucesso

- [ ] As **10 depreciações de `withOpacity`** em `glassNavBar.dart` somem do
      `flutter analyze`.
- [ ] `GlassNavBar`, `GlassPill`, `GlassCircleButton` e `CreateActionSheet`
      compõem o mesmo `GlassSurface`.
- [ ] A barra tem brilho especular no topo e borda mais clara em cima que
      embaixo.
- [ ] O indicador azul tem sombra curta e não parece recortado.
- [ ] O ícone selecionado cresce levemente ao ser escolhido.
- [ ] Tocar em qualquer item continua trocando de aba, inclusive no já
      selecionado.
- [ ] O `+` continua abrindo o menu de criar e **não** troca de aba.
- [ ] Nenhuma dependência nova no `pubspec.yaml`.
- [ ] `flutter analyze lib/` sem error/warning novo.
- [ ] Os 376 testes que já existem continuam passando.

## Decisões

**1. Extrair a superfície, e não só polir a barra.** A cópia já divergiu em três
opacidades e duas APIs de cor. Polir só a barra criaria uma quarta variante e
deixaria as outras três para trás — o mesmo processo que produziu a bagunça.

**2. A opacidade do sheet continua maior.** Texto sobre vidro claro precisa de
mais fundo que ícone. É diferença justificada, então vira parâmetro documentado
em vez de valor solto — e em vez de uniformidade forçada que pioraria a leitura.

**3. Brilho estático, não animado.** Um gradiente fixo não repinta durante o
scroll. Brilho que segue o dedo ou o giroscópio seria bonito e cobraria frames
exatamente onde o app já paga caro com o `BackdropFilter`.

**4. Aparência não vira teste.** Os testes travam estrutura (uma camada de blur,
brilho sem toque) e comportamento (toque, badge, trailing). Se o resultado ficar
feio, quem diz é o simulador — teste de pixel aqui só travaria o design.

## Dívidas e fora de escopo

- **Tema escuro.** O vidro é branco fixo. Um `Colors.white` virando
  `Theme.of(context).colorScheme.surface` é o caminho, mas o app não tem modo
  escuro e adivinhar como ele ficaria seria projetar no vazio.
- **Reavaliar liquid glass** se o app ganhar fundo escuro, foto ou gradiente
  atrás da barra — aí passa a haver o que refratar.
- **`main.dart` ainda semeia o tema com `deepPurple`**, que não é a cor da marca
  (`#1976D2`). Mexer nisso muda a cor de todo controle padrão do app e merece
  decisão própria.
- Rótulos de texto na barra, hoje declarados em `GlassNavItem.label` e **nunca
  desenhados**.

## Perguntas em aberto

Nenhuma bloqueante.

---

# Plano de implementação

```
(1) widget/glassSurface.dart ──→ (2) os quatro consumidores ──→ (3) simulador
     teste primeiro                  + casos de comportamento
```

O risco real está no passo 2: `home.dart` depende da assinatura pública de
`GlassNavBar`, e o `createActionSheet` é aberto pelo botão "+". Nenhum dos dois
pode mudar de comportamento — só de aparência.

## Riscos

| Risco | Mitigação |
|---|---|
| Camada de brilho roubando o toque dos ícones | `IgnorePointer`, com teste dedicado |
| Dois `BackdropFilter` empilhados na composição | Teste conta exatamente um por superfície |
| Blur em cima de blur no `trailing` (botão ao lado da barra) | O `+` é superfície irmã, não filha — verificado no simulador |
| Borda de gradiente comendo 1px do conteúdo | O recuo entra no container externo; o `padding` do filho não muda |
| Mudar sem querer a API que `home.dart` usa | Os testes de comportamento cobrem `onTap`, badge e `trailing` |

---

# Tarefas

- [x] **1. `widget/glassSurface.dart` — o material, teste primeiro** — 8 testes.
  - **A spec superdimensionava o `IgnorePointer`.** Removi-o de propósito para
    ver o teste de toque falhar, e ele **continuou passando**: `DecoratedBox`
    não faz hit test de si mesmo, então aquela camada já não roubaria toque
    sozinha. O `IgnorePointer` fica — a edição que quebraria isto é banal
    (trocar por `Container(color:)` ou `AnimatedContainer` para animar o
    brilho) — mas agora o comentário diz que ele é **defensivo**, e não que
    está segurando a barra de pé. Teste que passa de qualquer jeito não guarda
    nada; pior é o que diz guardar.
  - A sombra fica **fora** do recorte: dentro dele seria cortada junto e a
    pílula deixaria de flutuar.
  - Aceite: `GlassSurface` com blur, opacidade, raio/círculo, padding e sombra;
    brilho especular e borda em gradiente embutidos; os quatro casos da
    "Estratégia de teste" escritos antes da implementação.
  - Verificar: `flutter test test/widget/glassSurface_test.dart`
  - Arquivos: `lib/widget/glassSurface.dart`,
    `test/widget/glassSurface_test.dart`

- [x] **2. Os quatro consumidores + o polimento da barra** — 7 testes novos de
  comportamento; as 10 depreciações de `withOpacity` do arquivo zeraram.
  - **Segundo teste que não guardava nada.** O caso "tocar no vão entre dois
    ícones" tocava logo *acima* do ícone — que ainda é dentro do glifo, porque
    o ícone tem 26px de altura e a pílula 64. Passava com e sem
    `HitTestBehavior.opaque`. Corrigido para tocar 40px à **direita** do ícone,
    ainda dentro do slot de ~180px: agora falha sem o `opaque`
    (`Expected: [0], Actual: []`). Ponto de toque mal escolhido transforma
    teste em enfeite.
  - `GlassCircleButton` passou a usar `Material(color: Colors.transparent)`: a
    cor branca que ele tinha antes taparia o blur que o `GlassSurface` acabou
    de aplicar.
  - Restam 4 `withOpacity` em `lib/widget/notificationPush.dart`, **fora do
    escopo desta spec** — não é superfície de vidro. Ficam para quem tocar
    naquele arquivo.
  - Aceite: `GlassNavBar`, `GlassPill`, `GlassCircleButton` e
    `CreateActionSheet` compondo `GlassSurface`; indicador com sombra; ícone
    selecionado com micro-escala; zero `withOpacity` no arquivo; a assinatura
    pública de `GlassNavBar` intacta.
  - Verificar: `flutter test test/widget/glassNavBar_test.dart` e
    `flutter analyze lib/`
  - Arquivos: `lib/widget/glassNavBar.dart`, `lib/widget/createActionSheet.dart`,
    `test/widget/glassNavBar_test.dart`

- [ ] **3. Verificação no simulador**
  - Aceite: a barra parece ter espessura; o `+` e o sheet do "+" parecem o mesmo
    material; trocar de aba continua funcionando; o scroll das listas não
    engasga.
  - Verificar: `flutter run`
