# Spec: Redesenho da aba Amigos — Ranking primeiro

Status: **implementada, falta o aparelho** · Criada, aprovada e implementada
em 2026-10-11 · As três decisões seguiram a recomendação: **reordenar**,
indicador **líquido nos três trilhos**, cabeça do card **rolando junto** · As
duas animações foram comparadas num protótipo em HTML antes da escolha
(descartado depois dela) · Conferida em quadros renderizados com Roboto a
390 dp; o julgamento no iPhone ainda não foi feito

## Objetivo

Deixar a aba Amigos com cara de produto, a começar pelo Ranking, que hoje é a
sub-tela mais genérica do app: duas barras cinzas idênticas empilhadas, uma
lista solta no fundo da tela, e um seletor que **pisca dois segmentos de uma
vez** a cada toque.

Usuário: o entregador que abre o Ranking para saber onde está entre os amigos
no mês. A pergunta da tela é "onde eu estou, e quem está na minha frente?" — e
a tela de hoje responde, mas não parece um placar.

Sucesso:

- o seletor de critério troca **sem** acender dois segmentos;
- as abas Amigos / Ranking / Feed falam a língua da barra de baixo — vidro, e
  um indicador azul que desliza;
- mês, critério e lista viram **um objeto só**, o placar do mês;
- trocar de critério mostra as mesmas pessoas mudando de lugar, em vez de uma
  lista sendo trocada por outra (ou a animação que a decisão 1 escolher);
- nenhuma regra do ranking muda: `lib/Utils/ranking.dart` não é tocado.

### Este trabalho é visual

A ordem, a amostra mínima, o rodapé "ainda sem amostra", o `null` que nunca
vira zero e a legenda da amostra junto do número continuam exatamente como
`docs/specs/amigos.md` (**O Ranking**) os descreve. Qualquer mudança que altere
quem aparece em que posição está fora desta spec.

## O "pisca dois" — a causa

`SegmentedSelector` desenha a pílula branca **dentro de cada segmento**, cada
um com o próprio `AnimatedContainer` de 150 ms. No toque, o segmento antigo
anima de branco para transparente e o novo de transparente para branco **ao
mesmo tempo** — durante 150 ms existem duas pílulas meio acesas, que é o
"pisca dois" que se vê. Piora com o rótulo: a `Opacity` do texto **não** anima
(pula de 0,45 para 1 no primeiro quadro), então o texto do novo segmento já
está escuro antes de a pílula dele existir.

A barra de baixo nunca teve o defeito porque ela tem **um** indicador que
desliza (`AnimatedPositioned` na `GlassNavBar`). O conserto é o mesmo
desenho: um indicador por trilho, nunca um por segmento.

O modo de múltipla escolha (`SegmentedSelector.multi`, o filtro de empresa da
lista) continua com uma pílula por segmento — lá acender vários é o objetivo, e
o toque só anima o segmento tocado.

## O que se aproveita da imagem do Gemini

Da imagem que inspirou o pedido entram: a lista **dentro de um card**, o traço
que corre ao lado de "AINDA SEM AMOSTRA", a linha do próprio usuário com
destaque forte, e as medalhas um pouco maiores.

Não entram:

- **O verde-petróleo.** O destaque do app é o azul de `ChartPalette.azul`
  (`#0D47A1 → #1976D2`), o mesmo do card de total do Resumo e dos gráficos —
  `companySummaryCard.dart` registra que o app não ganha uma quarta cor de
  destaque.
- **O fundo em gradiente.** Mudaria o tema de `main.dart` para o app inteiro, e
  `polimento-glass.md` já registrou por que o fundo é branco.
- **O desenho dos seletores.** A imagem tem o próprio defeito que este pedido
  quer consertar: "Amigos" e "Ranking" aparecem acesos ao mesmo tempo, e
  "Rotas" está aceso enquanto a dica e os números são os do Ritmo.

## Layout

### Ranking

```
┌──────────────────────────────────────────────┐
│ (W) Olá,                             🚗   ⋮   │  ← AppBar da Home (não muda)
│     Wesley | @wesley-efmg                    │
│                                              │
│ ╭──────────────────────────────────────────╮ │
│ │   Amigos     ▐█ Ranking █▌     Feed      │ │  ← GlassTabs: vidro + o indicador
│ ╰──────────────────────────────────────────╯ │     azul da barra de baixo
│                                              │
│ ╭──────────────────────────────────────────╮ │
│ │▒▒  ‹         OUTUBRO 2026          ›   ▒▒│ │  ← cabeça azul do card
│ │▒▒ ╭──────────────────────────────────╮ ▒▒│ │     (ChartPalette.azul)
│ │▒▒ │  Rotas   ▐█ Ritmo █▌  Insucesso  │ ▒▒│ │  ← trilho branco translúcido,
│ │▒▒ ╰──────────────────────────────────╯ ▒▒│ │     uma pílula branca que desliza
│ │▒▒  Menor tempo por parada              ▒▒│ │
│ │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│ │  ← 2 px de progresso, só ao
│ │                                          │ │     trocar de mês
│ │  🥇 (C) Carla Mendes            4,9      │ │
│ │         401 paradas · 9 rotas min/parada │ │  ← número grande, unidade pequena
│ │ ╭──────────────────────────────────────╮ │ │
│ │ │🥈 (W) Wesley Nogueira (você)   6,1   │ │ │  ← gradiente azul, texto branco
│ │ │       146 paradas · 5 rotas min/parada│ │ │
│ │ ╰──────────────────────────────────────╯ │ │
│ │  🥉 (D) Diego Araújo            8,1      │ │
│ │         143 paradas · 5 rotas min/parada │ │
│ │                                          │ │
│ │  AINDA SEM AMOSTRA ───────────────────── │ │
│ │  —  (J) Jonas Freitas           4,6      │ │  ← número em cinza, sem negrito
│ │         73 paradas · 3 rotas  min/parada │ │
│ │  —  (P) Patrícia Rocha           —       │ │
│ │         0 rotas                          │ │
│ ╰──────────────────────────────────────────╯ │
│                                              │
│  ╭────────────────────────────────╮  ╭────╮  │
│  │  📊    🧾    ◎    ▐█ 👥 █▌      │  │ +  │  │  ← GlassNavBar (não muda o desenho)
│  ╰────────────────────────────────╯  ╰────╯  │
└──────────────────────────────────────────────┘
```

**Um card só, com cabeça e corpo.** Mês e critério ficam na cabeça azul do
mesmo card que contém a lista, porque são os controles **daquela** lista — em
dois blocos separados a relação entre eles volta a ser só proximidade, que é o
que a tela de hoje tem. A cabeça azul também separa os dois níveis de
navegação: hoje as duas barras são idênticas e o olho não sabe qual manda na
outra.

**O número do rodapé perde o negrito.** Ele continua visível (fora da disputa,
não escondido — `amigos.md`), mas hoje o "4,6 min/parada" do rodapé é o número
mais forte da tela e é **melhor** que o do primeiro lugar. Em negrito, ele
parece estar ganhando. Cinza `grey.shade600`, peso 600.

**O número grande, a unidade pequena.** `4,9` em 16 px peso 800 e
`min/parada` em 10,5 px, na mesma linha, com `Text.rich`. As duas partes saem
do **mesmo** `formatPace` de hoje, separadas no primeiro espaço — uma segunda
formatação do ritmo seria a divergência que `Utils/routePace.dart` existe para
impedir. Insucesso (`1,4%`) e Rotas (`17`) não têm unidade a separar.

**A própria linha em gradiente azul**, texto branco, sombra azul curta. O
`blue.shade50` de hoje some numa lista de cinco e numa de vinte some de vez.

**Cada pixel horizontal da linha sai do nome.** Na primeira versão (número em
17 px, recuos de 8 e 12, avatar de 38) o "(você)" de "Wesley Nogueira (você)"
era cortado ao lado de "5,2 min/parada" em 390 dp — o primeiro quadro
renderizado mostrou. Com número em 16, unidade em 10,5, avatar de 36 e recuos
de 6 e 10 o nome inteiro cabe, com a mesma folga de antes do redesenho.

**Os estados moram dentro do card.** A primeira busca desenha três linhas
cinzas no lugar do spinner solto — o card já tem o tamanho do que vem, e a tela
não pula quando os baldes chegam. A falha ganhou **"Tentar de novo"**: antes, a
única saída era trocar de mês e voltar. Os avisos de "sem amigos" e "ninguém
com amostra" são os mesmos textos de antes, dentro do corpo.

### Abas do topo (`GlassTabs`)

O mesmo material da barra de baixo (`GlassSurface`), na opacidade documentada
para superfície **com texto** (0,75), e o mesmo indicador: gradiente azul,
sombra rente, 300 ms `easeOutCubic`. Rótulo aceso em branco; os outros no azul
a 70% que os ícones apagados da barra usam. A cor do rótulo anima **junto** com
o deslize — texto que fica branco antes de o indicador chegar é branco sobre
vidro claro, ilegível por um instante, que é uma versão do mesmo "pisca".

Altura 48, raio 24. As keys `aba-amigos`, `aba-ranking` e `aba-feed` continuam.

### Amigos

```
│ CONVITES (1)                                 │
│ ╭──────────────────────────────────────────╮ │
│ │ (M) Marina Souza                ✓    ✕   │ │
│ │     @marina.s7                           │ │
│ ╰──────────────────────────────────────────╯ │
│                                              │
│ MEUS AMIGOS (4)                              │
│ ╭──────────────────────────────────────────╮ │
│ │ (C) Carla Mendes                      ›  │ │
│ │     @carla.m                             │ │
│ │ ──────────────────────────────────────── │ │
│ │ (D) Diego Araújo                      ›  │ │
│ │     @diego.a3                            │ │
│ ╰──────────────────────────────────────────╯ │
```

Só a superfície muda: cada seção vira um card branco (o mesmo do corpo do
Ranking), com divisória recuada entre as linhas. O `FriendTile`, os toques, o
dialog de perfil, o bloqueio e o estado vazio continuam como estão.

### Feed

Ganha as abas novas em cima e mais nada. Os cards de post têm desenho próprio,
e mexer neles é outra spec.

## Movimento

Regra herdada de `chartCard.dart`: **anima a grandeza, nunca o número.**
Posição, altura e indicador se movem; números, medalhas e rótulos trocam no
primeiro quadro, sem transição — texto em transição é texto que não se lê
justamente quando a pessoa está tentando ler.

| o quê | como | duração |
|---|---|---|
| indicador das abas, do critério e da barra de baixo | desliza (e estica, se a decisão 2 aprovar) | 300 ms por borda, `easeOutCubic`; com o efeito líquido a borda de trás sai 120 ms depois e o gesto leva ~420 ms |
| lista ao trocar de critério | decisão 1 | ~450 ms |
| lista ao trocar de mês | escurece a 50% e mostra o progresso enquanto busca; quando chega, a mesma animação do critério | — |
| altura do card | acompanha a lista, na mesma duração | ~450 ms |
| quem entra (o card montando, amigo aceito) | aparece no lugar, em fade | 200 ms |
| quem sai (amizade desfeita) | some sem animação | — |

**Troca de mês hoje mostra o mês errado.** `_goTo` troca o rótulo do mês na
hora e `_body` só mostra o carregamento quando **não há** balde nenhum — então,
até a rede responder, os números de setembro ficam na tela sob o título
"OUTUBRO 2026". É a regra do `getWeather`: "não sei ainda" não pode ter a
aparência de um dado. A lista passa a esmaecer e a cabeça mostra os 2 px de
progresso até o mês novo chegar.

**As linhas são opacas, e a própria é pintada por cima.** Ao reordenar, as
linhas passam umas sobre as outras; transparentes, os textos se misturavam no
meio do caminho (visto no quadro renderizado a 160 ms). Brancas sobre o corpo
branco, elas não mudam nada parado e se cobrem limpas em movimento. A linha do
usuário vai por último no `Stack` — a ordem dos filhos só decide a pintura —,
então é a dele que fica visível quando duas se cruzam.

**O conteúdo da fatia acompanha as bordas, não o centro.** Rótulo e ícone que
acendem mudam com a borda da frente; os que apagam esperam a borda de trás
começar a sair (`SlidingIndicator.contentCurve`). No mesmo tempo para os dois,
"Rotas" ficava branco com a pílula branca ainda embaixo e sumia por um
instante — o "pisca" de novo, por outro caminho.

**Alturas medidas, nunca fixas.** Se a decisão 1 for reordenar, cada linha é
posicionada em `y` calculado, e a altura dela sai de um `TextPainter` com o
`textScaler` do aparelho — um número fixo cortaria a linha de quem usa a fonte
grande do sistema, que entre entregadores não é raro.

**`MediaQuery.disableAnimationsOf`** zera as durações das animações novas.
Nenhuma tela do app respeita isso hoje; as novas nascem respeitando.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1. **Nenhuma dependência nova** — reordenar e
esticar o indicador são `AnimationController` e `Stack`, como a barra de baixo
já é.

## Comandos

```bash
flutter analyze lib/ test/
flutter test test/widget/slidingIndicator_test.dart
flutter test test/widget/glassTabs_test.dart
flutter test test/widget/segmentedSelector_test.dart
flutter test test/widget/rankingBoard_test.dart
flutter test test/widget/rankTile_test.dart
flutter test                     # hoje: 1447 passam, 1 falha conhecida (widget_test.dart)
flutter run                      # o julgamento final é o olho, no aparelho
```

## Estrutura

```
lib/widget/slidingIndicator.dart   novo — o indicador que desliza, um só para
                                   os três trilhos (abas, critério, barra)
lib/widget/glassTabs.dart          novo — abas de texto no vidro (topo de Amigos)
lib/widget/glassNavBar.dart        passa a usar o SlidingIndicator; desenho igual
lib/widget/segmentedSelector.dart  escolha única com um indicador; tom `onBlue`
lib/widget/rankingBoard.dart       novo — o card do placar: cabeça + corpo +
                                   animação; recebe tudo pronto, não lê nada
lib/widget/rankTile.dart           visual novo da linha
lib/widget/rankingTab.dart         só carrega e compõe; corrige o mês velho
lib/widget/sectionCard.dart        novo — a superfície branca das seções
lib/screens/friendsScreen.dart     GlassTabs no topo; seções em SectionCard
test/widget/slidingIndicator_test.dart   novo
test/widget/glassTabs_test.dart          novo
test/widget/rankingBoard_test.dart       novo
test/widget/segmentedSelector_test.dart  ganha casos
test/widget/rankTile_test.dart           ajusta ao visual novo
docs/specs/amigos.md               a seção Layout aponta para cá
```

**`SlidingIndicator` existe pelo mesmo motivo do `GlassSurface`.** Hoje há um
indicador que desliza (a barra) e um que pisca (o trilho). Esta spec criaria um
terceiro (as abas do topo). Três cópias do mesmo movimento divergem na primeira
vez que alguém ajusta a curva de uma — é a deriva que `polimento-glass.md`
fechou para o material, agora para o movimento.

**`RankingBoard` fora da `RankingTab`**, pelo motivo que tirou o `RankTile` de
lá: a aba abre o Firestore no `initState`, então nada que mora dentro dela é
alcançável por teste de widget. O card recebe as linhas, o critério, os perfis,
o mês e o estado de carregamento — e não lê nada.

## Código

```dart
/// O indicador que desliza entre as fatias de um trilho.
///
/// Um só para as abas do topo, o critério do Ranking e a barra de baixo: o
/// trilho de critério acendia **dois** segmentos por toque porque cada
/// segmento tinha a própria pílula animando ao mesmo tempo que a vizinha.
class SlidingIndicator extends StatefulWidget {
  const SlidingIndicator({
    super.key,
    required this.count,
    required this.index,
    required this.indicator,
    this.inset = 0,
  });

  final int count;
  final int index;

  /// O desenho da pílula — gradiente azul no vidro, branco sobre a cabeça azul.
  final Widget indicator;
  final double inset;
  ...
}
```

Arquivos em camelCase, texto de interface em pt-BR, comentários explicando o
porquê, `withValues(alpha:)`.

## Estratégia de teste

A regra do `CLAUDE.md` vale inteira aqui: teste de widget não diz se o texto
cabe, nem se a animação é bonita. Testa-se **a causa**.

`slidingIndicator_test.dart`

- existe **um** indicador na árvore, inclusive **no meio** da animação (pump de
  100 ms depois do toque) — o defeito era haver dois;
- no meio da animação o indicador está **entre** a fatia velha e a nova, e no
  fim exatamente sobre a nova;
- trocar de alvo no meio do caminho parte de onde o indicador **está**, não da
  fatia de origem (senão ele salta para trás);
- com `disableAnimations`, chega no primeiro quadro.

`segmentedSelector_test.dart` (os casos de hoje continuam)

- escolha única: um `SlidingIndicator`; múltipla: nenhum, uma pílula por
  segmento acesa — o `CompanyFilter` não muda;
- continua um `Opacity` por segmento e nenhum fora deles (o teste do
  `CompanyFilter` conta a árvore inteira).

`glassTabs_test.dart`

- um `BackdropFilter` só;
- keys `aba-*`; tocar avisa o valor, inclusive o já selecionado;
- rótulos com `maxLines: 1` e reticências.

`rankingBoard_test.dart`

- depois de trocar o critério, a ordem vertical das linhas (por key
  `rank-{uid}`) é a de `rankBy` — sem reimplementar a regra no teste;
- no primeiro quadro depois da troca, o **número já é o novo** e a linha ainda
  está no caminho (prova que anima a posição e não o texto);
- o cabeçalho "AINDA SEM AMOSTRA" só existe quando há rodapé — em Rotas não há;
- `loading: true` esmaece o corpo e mostra o progresso; os números do mês
  anterior não aparecem com opacidade cheia;
- com `textScaler` 1,3 nenhuma linha estoura (`takeException` nulo).

`rankTile_test.dart`

- os casos de hoje continuam (amostra do critério, medalha até o 3º, nome não
  espremido);
- a linha própria tem **gradiente**, não só cor;
- o número do rodapé não tem o peso nem a cor do número da disputa;
- a linha própria **no rodapé** continua legível — o cinza do rodapé sobre o
  gradiente azul seria texto sumindo justamente na linha de quem olha;
- `find.text('5,7 min/parada')` continua achando o número inteiro — o
  `Text.rich` não pode quebrar quem procura pelo texto.

`glassNavBar_test.dart` e `companyFilter_test.dart` passam **sem edição**.

## Fronteiras

- **Sempre:** `flutter analyze` limpo; texto em pt-BR; as keys existentes
  (`aba-*`, `criterio-*`, `mes-anterior`, `mes-seguinte`, `rank-{uid}`)
  mantidas; números trocam sem transição; vidro só por `GlassSurface`.
- **Perguntar antes:** mudar o tema ou o fundo do app; mudar tamanho, cor ou
  raio da `GlassNavBar`; qualquer mudança em `lib/Utils/ranking.dart`.
- **Nunca:** pacote novo; dois indicadores acesos ao mesmo tempo num trilho de
  escolha única; animar número; esconder o rodapé "ainda sem amostra".

## Critérios de sucesso

- [x] Tocar em Rotas / Ritmo / Insucesso move **uma** pílula, e em nenhum
      quadro há dois segmentos acesos.
- [x] As abas Amigos / Ranking / Feed são vidro com o indicador azul da barra
      de baixo, e o rótulo aceso nunca fica branco sobre o vidro.
- [x] Mês, critério e dica ficam na cabeça azul do mesmo card da lista.
- [x] Trocar de critério anima como a decisão 1 escolheu, e os números já
      aparecem certos no primeiro quadro.
- [x] Trocar de mês não mostra os números do mês anterior sob o título do mês
      novo.
- [x] A própria linha tem gradiente azul e texto branco; o número do rodapé não
      está em negrito.
- [x] As seções da sub-tela Amigos ficam em cards; nenhum fluxo muda.
- [ ] Com a fonte grande do sistema, nenhuma linha do Ranking é cortada
      (verificado no aparelho).
- [x] Nenhuma dependência nova; `lib/Utils/ranking.dart` sem diff.
- [x] `flutter analyze` sem aviso novo; os 1447 testes de hoje passam, mais os
      novos — 1480 no total, e a única falha é a de sempre (`widget_test.dart`).

## Decisões

As três foram decididas em 2026-10-11, todas pela recomendação.

**1. A animação ao trocar de critério.**

- **A — Reordenar.** As mesmas pessoas deslizam até a posição nova, e quem sai
  da disputa desce para baixo do "AINDA SEM AMOSTRA". O card cresce ou encolhe
  junto. Lê como *o mesmo placar mudando*, que é a verdade da tela: os
  participantes são sempre você e seus amigos, só a régua muda. É também a
  regra que os gráficos já seguem ao trocar de período.
- **B — Fechar e abrir** (a ideia do pedido). O corpo do card fecha (~200 ms),
  troca, e abre de novo com as linhas entrando em cascata (~300 ms). É mais
  dramática, e mais barata de fazer. O custo: por meio segundo a lista some, e
  o olho perde quem subiu e quem desceu — que é justamente a informação.

Recomendação: **A**. ✅ **Decidido: A**, depois de ver as duas lado a lado.

**2. O indicador "líquido".** No meio do deslize, a borda da frente vai na
frente e a de trás alcança depois — a pílula estica como uma gota e volta ao
tamanho. É o que mais aproxima do *liquid glass* sem shader e sem pacote: duas
curvas no mesmo `AnimationController`.

- nos três trilhos (abas, critério e barra de baixo);
- só nas abas do topo — a barra de baixo fica como foi verificada no aparelho,
  mas as duas passam a se mover diferente;
- em nenhum — o deslize seco de hoje da barra de baixo.

Recomendação: **nos três**. Como o `SlidingIndicator` já vai substituir o
`AnimatedPositioned` da barra, ligar o efeito nela é uma linha, e um indicador
que se move de dois jeitos no mesmo app parece defeito. ✅ **Decidido: nos
três.** Por isso o `SlidingIndicator` não tem chave para desligar o efeito:
uma opção que ninguém usa é um segundo movimento esperando para divergir.

**3. A cabeça do card rola junto com a lista.** Com cinco amigos o card cabe na
tela; com vinte, quem rola até o fim perde os controles de mês e critério de
vista. Fixar a cabeça e rolar só o corpo resolve, mas o card passa a ocupar a
altura inteira mesmo com três linhas, ou exige medir o conteúdo para decidir.

Recomendação: **rolar junto** nesta entrega — a maior lista de hoje tem cinco
pessoas — e registrar a cabeça fixa como dívida. ✅ **Decidido: rolar junto.**

## Fora de escopo

- **Pódio dos três primeiros.** Não foi pedido, e brigaria com uma regra da
  tela: o número vai sempre junto da amostra que o formou, e "401 paradas · 9
  rotas" não cabe numa coluna de um terço da largura. Com um ou dois na
  disputa, o pódio ficaria com degraus vazios.
- **Conteúdo rolando por trás das abas do topo**, para o vidro ter o que
  borrar. Exigiria compensar a altura em três sub-telas, o Feed com anúncio
  incluído, para um ganho que o fundo branco quase não mostra — o mesmo
  argumento que tirou o `liquid_glass_easy`.
- **Resumo "você está em 2º de 5"** na cabeça do card. A linha em gradiente já
  responde isso.
- **Avatares coloridos por pessoa**, como na imagem. Cor que não codifica nada
  vira paleta decorativa para manter.
- ~~**O Feed** além das abas.~~ Feito depois, no mesmo dia — ver **O Feed**,
  abaixo.
- **Fade de saída de quem deixa o ranking.** Exigiria guardar a linha que saiu
  até o fim da animação. A sub-tela é desmontada ao trocar de aba, então quem
  desfaz uma amizade na aba Amigos volta para um Ranking montado do zero — só a
  amizade desfeita **pelo outro lado**, com o Ranking aberto, passaria por aqui.
- **A cabeça do card fixa no topo** enquanto a lista rola (decisão 3).

## O Feed — feito depois, em 2026-10-11

Pedido depois do Ranking e das telas de período: o mural continuava com cards
cinza-claros soltos no fundo lilás, um compositor que parecia campo de busca e
uma folha de comentários tingida de lilás.

- **O post é o card branco** do placar e das seções (`SectionCard.decoration`).
  Avatar de 40, nome em 15/700, e a empresa vira um **selo ao lado do
  "quando"** — no canto direito ela flutuava longe do autor e disputava lugar
  com o menu. Foto com cantos de 14, recuada das bordas.
- **Curtir e comentar são pílulas**: ícone e contagem no mesmo botão (antes o
  número ficava fora dele, e tocar no número não fazia nada). Curtido, a pílula
  ganha o vermelho claro do coração, e o coração entra crescendo — só o ícone
  se move, o número troca seco.
- **O compositor** é um card com o seu avatar, a pergunta com o seu primeiro
  nome (`composerPrompt`: "Como foi o dia, Wesley?" — sem vocativo quando só
  há `@apelido`) e uma câmera que abre o `AddPost` já escolhendo a foto
  (`startWithPhoto`).
- **A folha de comentários** é branca (`backgroundColor` explícito: o padrão do
  Material 3 é o lilás claro do tema). Cada comentário vira um balão com o nome
  e o texto, o "quando" embaixo; o seu sai em azul-claro, como a sua linha no
  Ranking. O campo é uma pílula cinza e o enviar um círculo azul.
- **Os três menus "⋯"** (conta, post, comentário) passam por `appMenu.dart`:
  branco de verdade, cantos de 18, ícone num quadrado tingido — cinza para o
  que se desfaz, a cor de erro para apagar e bloquear.
- **A moldura do anúncio mudou junto.** Ela era branca porque o post era
  cinza-claro — cor diferente é uma das exigências da política de "não
  parecer conteúdo". Com o post branco, o teste `não imita o card de post`
  ficou vermelho, como devia; a moldura passou a transparente (borda, cantos de
  6, sem sombra) e o teste ganhou a sombra como quarta diferença. Ver
  `docs/specs/anuncios-no-feed.md`.
- **A tela de publicar** ("Nova publicação") é o post como ele vai sair: um
  card com quem publica e "Aparece no mural para todos" — o mural é global, e
  dizer isso antes é o mínimo —, o texto sem moldura, a foto com cantos de 14 e,
  no rodapé, câmera, galeria e o contador (laranja nos últimos 50). Publicar
  virou uma pílula azul.
- **A empresa é o trilho de logos da Lista**, de escolha única (vidro, pílula
  branca) — tocar na marcada desmarca. **Publicar sem empresa pergunta antes**
  (`askPublishWithoutCompany`), a pedido do dono, para a marcação ser sempre
  lembrada: "Marcar empresa" volta com o trilho contornado de azul e o teclado
  fechado; "Publicar sem empresa" segue. A pergunta nunca bloqueia — o vínculo
  continua opcional.
- `ProfileAvatar` nasceu para os três avatares do Feed. `FriendTile` e
  `RankTile` ainda montam o deles e passam a usá-lo quando forem mexidos.

A folha de comentários não tem teste de widget: ela escuta o Firestore no
`build`. O card, o `composerPrompt`, o estilo de menu e a tela de publicar (até
o aviso de empresa; o envio chama o Firebase) têm.

# Plano de implementação

A ordem vai do movimento para a tela: o indicador primeiro, porque três
trilhos dependem dele, e a `RankingTab` por último, porque ela só compõe o que
as outras tarefas entregam.

1. **`SlidingIndicator`** — `StatefulWidget` com um `AnimationController` de
   420 ms. Guarda as bordas desenhadas no último quadro; uma troca no meio do
   caminho parte delas. Cada borda percorre seu trecho em 300 ms
   `easeOutCubic`, a de trás com 120 ms de atraso. O desenho da pílula vem de
   fora (`child`). `GlassIndicator` (o gradiente azul de hoje da barra) mora em
   `glassSurface.dart`, ao lado do material.
2. **`GlassNavBar`** troca o `AnimatedPositioned` pelo `SlidingIndicator`. Os
   testes de hoje passam sem edição — é a prova de que o comportamento ficou.
3. **`SegmentedSelector`**, escolha única: trilho com `SlidingIndicator` e
   rótulos que animam junto (um `TweenAnimationBuilder` que desenha um
   `Opacity` — continua havendo um por segmento). Ganha `SegmentedTone.onBlue`.
   A múltipla escolha não muda uma linha.
4. **`GlassTabs`** e o topo da `FriendsScreen`.
5. **`RankTile`** novo e `RankTile.heightFor(context)`, que mede com
   `TextPainter` a altura que o próprio tile vai ocupar.
6. **`RankingBoard`**: cabeça (mês, critério, dica, progresso) e corpo. O corpo
   é um `Stack` de `AnimatedPositioned` com key por uid — o Flutter casa as keys
   entre rebuilds, então reordenar a lista **é** animar a posição, sem medir
   nada depois do layout. A altura do corpo anima num `AnimatedContainer`.
7. **`RankingTab`** passa a carregar e compor; `loading` vai para o card mesmo
   com balde na tela, que é o conserto do mês velho.
8. **`SectionCard`** e as seções da sub-tela Amigos.
9. Docs: `amigos.md` aponta para cá; `CLAUDE.md` ganha o parágrafo do
   indicador único.

### Riscos

- **A altura medida errar para menos** corta a linha. Mitigação: o tile mede
  com o mesmo estilo efetivo (`DefaultTextStyle` mesclado) que desenha, e o
  teste com `textScaler` 1,3 cobra `takeException` nulo.
- **O deslize mais longo na barra de baixo** (300 → ~420 ms no gesto inteiro).
  Cada borda continua em 300 ms; o julgamento é no aparelho.

# Tarefas

- [x] **1. Indicador único**
  - Aceite: um indicador por trilho; troca no meio do caminho parte de onde
    ele está; `disableAnimations` chega no primeiro quadro.
  - Verificar: `flutter test test/widget/slidingIndicator_test.dart test/widget/glassNavBar_test.dart`
  - Arquivos: `slidingIndicator.dart`, `glassSurface.dart`, `glassNavBar.dart`, teste novo
- [x] **2. Trilho sem "pisca dois"**
  - Aceite: escolha única com um `SlidingIndicator`; tom `onBlue`; múltipla
    intocada.
  - Verificar: `flutter test test/widget/segmentedSelector_test.dart test/widget/companyFilter_test.dart`
  - Arquivos: `segmentedSelector.dart`, teste
- [x] **3. Abas de vidro**
  - Aceite: um `BackdropFilter`; keys `aba-*`; rótulo de uma linha.
  - Verificar: `flutter test test/widget/glassTabs_test.dart`
  - Arquivos: `glassTabs.dart`, `friendsScreen.dart`, teste novo
- [x] **4. Linha do Ranking**
  - Aceite: gradiente na própria linha; número grande e unidade pequena do
    mesmo `formatPace`; rodapé em cinza; legível no rodapé quando é a própria.
  - Verificar: `flutter test test/widget/rankTile_test.dart`
  - Arquivos: `rankTile.dart`, teste
- [x] **5. O placar**
  - Aceite: ordem vertical = `rankBy`; número novo no primeiro quadro com a
    linha ainda no caminho; cabeçalho do rodapé só com rodapé; `loading`
    esmaece; `textScaler` 1,3 sem estouro.
  - Verificar: `flutter test test/widget/rankingBoard_test.dart`
  - Arquivos: `rankingBoard.dart`, `rankingTab.dart`, teste novo
- [x] **6. Seções em card**
  - Aceite: convites, amigos e bloqueados em `SectionCard`; nenhum fluxo muda.
  - Verificar: `flutter test` inteiro + `flutter analyze`
  - Arquivos: `sectionCard.dart`, `friendsScreen.dart`
- [x] **7. Docs**
  - Arquivos: `amigos.md`, `CLAUDE.md`, esta spec
