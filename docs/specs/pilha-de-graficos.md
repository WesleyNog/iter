# Spec: Pilha de gráficos ao rolar

Status: **implementada** · Criada e aprovada em 2026-08-24 · Falta rolar no
aparelho (T5) · Plano e tarefas no fim do arquivo

## Objetivo

Trocar a rolagem da tela de Gráficos: em vez de os carrosséis passarem e
sumirem, cada um **encaixa no topo** ao chegar lá e o seguinte desliza por
cima, deixando uma faixa fina de cada card anterior aparecendo. No fim da
rolagem o topo é uma pilha de bordas coloridas — dinheiro, empresas, bairros,
tempo — com o card ativo por baixo delas.

É mudança **só de apresentação**: nenhum dado, nenhuma conta, nenhuma navegação.
Nada em `Utils/routeStats.dart` é tocado.

Usuário: o entregador. Sucesso = ele rola a tela inteira sem perder a noção de
onde está, e as faixas coloridas no topo dizem quantos blocos ele já passou sem
ocupar espaço de conteúdo.

**A viabilidade já foi verificada**, não assumida: um protótipo descartável
— que virou `test/widget/stackedScroll_test.dart` — provou o encaixe no topo, a
pilha crescendo 12px por card, a faixa colorida aparecendo e a ordem de pintura.
Ele achou um erro na primeira versão da fórmula — ver Regra 1.

## Tech Stack

Flutter 3.41.4 / Dart `^3.11.1`. **Nenhuma dependência nova**:
`SingleChildScrollView`, `Stack`, `Transform.translate` e `AnimatedBuilder` são
do SDK. Nada de `sliver_tools` nem de pacote de scroll.

Sem gerência de estado: `setState` e um `ScrollController` próprio.

## Comandos

```bash
flutter analyze lib/ test/                       # sem error/warning novo
flutter test test/widget/stackedScroll_test.dart
flutter test test/widget/chartCard_test.dart
flutter test                                     # widget_test.dart segue quebrado
flutter run -d <simulador>                       # é aqui que o efeito se julga
```

## Estrutura

```
lib/widget/stackedScroll.dart      → a rolagem que empilha (novo)
lib/widget/chartCard.dart          → + eyebrow (a linha de recorte)
lib/widget/chartCarousel.dart      → + totalHeight
lib/screens/graficsScreen.dart     → monta a pilha em vez da Column
test/widget/stackedScroll_test.dart → as posições de encaixe (novo)
test/widget/chartCard_test.dart     → o eyebrow (novo)
docs/specs/graficos.md             → seção Layout atualizada
```

`StackedScroll` é widget próprio, e não código dentro da tela, por dois motivos:
a matemática do encaixe é a única parte **testável** disto, e a tela de Gráficos
precisa de Firebase para existir. Separado, o teste pergunta direto onde cada
card parou.

## Regras

### 1. O encaixe é relativo ao conteúdo, não à tela

```dart
final top = math.max(offset + index * peek, naturalTop[index]);
```

`offset +` é o detalhe que a primeira versão errou e o protótipo pegou: o
conteúdo do `SingleChildScrollView` **já vem deslocado** por `-offset`. Escrito
como `max(index * peek, natural - offset)` o card "encaixa" e continua subindo
junto com a rolagem — nos testes de posição relativa isso passa, e só a posição
absoluta denuncia.

`naturalTop[i]` é a soma das alturas com o espaçamento, acumulada. Enquanto o
card está longe do topo o `natural` vence e ele rola normal; quando a rolagem o
alcança, o encaixe vence e ele para.

### 2. Quem vem depois é desenhado por cima

A ordem dos filhos do `Stack` é a ordem de pintura. O card seguinte cobre o
encaixado, em vez de sumir atrás dele — é isso, e só isso, que produz o efeito.
Inverter a ordem inverteria o visual inteiro, então tem teste.

### 3. Só a posição é reconstruída a cada quadro

O card vai como `child` do `AnimatedBuilder`, não dentro do `builder`. Assim o
`PageView` e os gráficos dentro dele **não** são reconstruídos a cada pixel de
rolagem — só o `Transform`. Sem isso, rolar a tela reconstruiria quatro
carrosséis de gráfico por quadro.

`Positioned.fill` + `Transform.translate` + `Align`, e não `Positioned(top:)`:
`Positioned` é `ParentDataWidget` e precisa ser filho **direto** do `Stack`, com
um `AnimatedBuilder` no meio o `top` não chega.

### 4. O último card não encaixa, e está certo

Para o quinto card chegar à sua posição de encaixe seria preciso ~170px de
espaço morto no fim da tela (viewport − altura do card − espaçamento − pilha).
Ele não encaixa: rola até o fim e fica inteiro na tela, que é onde o leitor
queria chegar. Empurrar a tela com espaço vazio para completar uma animação é
pagar conteúdo por enfeite.

### 5. O card sabe a própria altura

`ChartCarousel.totalHeight` = `height` mais o bloco de bolinhas (`10 + 11`)
quando há mais de uma página. A pilha precisa desse número antes de desenhar, e
recalculá-lo na tela seria copiar o layout interno do carrossel para fora dele —
a cópia que diverge no primeiro ajuste de espaçamento.

O carrossel de bairros tem **uma** página e portanto não tem bolinhas: é o caso
que uma constante fixa de 21px erraria.

### 6. O rótulo de seção entra no card

Hoje "Análise das rotas concluídas e pagas" e "Insucessos das rotas concluídas e
pagas" moram **entre** os carrosséis. Numa pilha eles seriam cobertos — e eles
carregam a ressalva de que aqueles números excluem rota agendada, que é
exatamente o que o leitor precisa saber ao olhar o card.

`ChartCard` ganha `eyebrow`: uma linha miúda acima do título, dentro do
gradiente. Cada página dos carrosséis de análise e de insucesso recebe
`'Rotas concluídas e pagas'`; as do carrossel de dinheiro recebem
`'Todos os status do período'`.

O card de dinheiro ganhar eyebrow **não** é simetria: o TOTAL dele difere do dos
outros de propósito, e hoje quem diz qual recorte está valendo é o rótulo que
some. Sem a linha, os dois números ficam contradizendo-se sem explicação.

Repetir a mesma linha em sete páginas é o preço, e é o certo: cada card passa a
se descrever sozinho, que é o que a pilha exige — o card encaixado no meio da
tela não tem mais um rótulo acima dele.

### 7. A faixa mostra o topo do card

A faixa de 12px que sobra é o **topo** do card seguinte: o gradiente e o canto
arredondado. É o que dá o visual de bordas empilhadas.

As bolinhas ficam no rodapé do carrossel e são cobertas quando ele encaixa.

**A primeira versão desta regra estava errada**, e a revisão provou: a faixa é o
topo do card, e o topo do card é o topo do `PageView` — nenhum card posterior a
cobre, então ela continuava recebendo toque. Arrastar de lado na faixa trocava a
página de um carrossel **invisível**, e o usuário só descobria ao rolar de volta
e encontrar outro gráfico ali.

O que corrige é um `IgnorePointer` quando sobrou só a faixa, e a régua é o que
**ainda aparece**, não se há sobreposição: durante a transição o card seguinte
já invade alguns pixels do de cima, e um card 96% visível tem de continuar
aceitando o arrasto das suas páginas. O primeiro rascunho desligava o toque
nessa invasão inicial — e foi o teste que mostrou o exagero.

Com o ponteiro ignorado, o arrasto **vertical** na faixa passa direto para a
rolagem, que é o único gesto que ela deve aceitar.

### 8. Sem sombra — ela nunca seria desenhada

A versão aprovada desta regra mandava dar ao `ChartCard` "a mesma sombra do card
da lista de rotas". Duas coisas estavam erradas nela.

A primeira: **o `RouteCard` não tem sombra**. Ele é `Card(elevation: 0)` separado
por uma `BorderSide` cinza — e borda cinza sobre gradiente colorido não desenha
nada. A instrução apontava para uma fonte que não existe.

A segunda, e a que fecha o assunto: **todo `ChartCard` é página de um `PageView`,
que instala um `ClipRect` do tamanho exato da página**. Sombra só pinta *fora* do
retângulo do widget, então ela seria recortada inteira. Medido contando as
camadas de clip: o retângulo do clip tem as mesmas medidas do card, inclusive no
carrossel de uma página só.

Fica sem sombra, com o motivo escrito no arquivo e um teste que prova o clip —
para ninguém "consertar" a falta sem antes descobrir por que ela não aparecia.

Se no aparelho a pilha ler como um bloco só, a separação tem de ser desenhada
**dentro** do card (uma linha clara no topo, por exemplo). Nunca com sombra.

### 9. O eyebrow custa altura, e a altura foi devolvida

O eyebrow ocupa ~22px, tirados do `Expanded` do gráfico. Medido com a fonte real
do aparelho e a largura real da tela: o card de dinheiro aguentava a escala de
texto do sistema até 1.2 e passou a estourar já em **1.1**. O carrossel de
dinheiro subiu de 290 para **312** — exatamente o custo — e voltou a aguentar
1.2, a mesma folga de antes. Os de 340 têm sobra e não mudaram.

As guardas de "cabe na altura do carrossel" passaram a montar o card **com**
eyebrow: sem isso elas mediam uma folga que a tela não tem mais.

### 10. A chave vai no filho direto do `Stack`

`StackedCard` carrega a `Key`, e o `StackedScroll` a aplica no `Positioned.fill`
— não no widget de dentro. Medido: com a chave um nível abaixo, reordenar a
lista faz cada carrossel perder a página em que estava, exatamente como se não
houvesse chave nenhuma. O comentário da primeira versão afirmava o contrário.

### 11. O controller primário continua sendo o primário

A rolagem antiga não declarava `controller` e por isso **herdava** o primário —
é dele que depende o gesto de tocar na barra de status para voltar ao topo.
Criar um controller próprio e parar aí levaria esse gesto embora sem nada na
tela denunciando; medido, o app tem um primário na árvore.

A pilha precisa escutar a rolagem para posicionar os cards, então ela declara um
controller — mas declara **o mesmo que herdaria**, caindo num próprio só quando
não houver primário.

## Dados

Nenhum. A tela continua lendo `RouteController.watchAll(uid)` e chamando as
mesmas funções de `routeStats.dart`. Nada é escrito.

## Estilo de código

O widget recebe altura e conteúdo, e não sabe o que há dentro:

```dart
/// Um card da pilha: a altura que ele ocupa e o que desenhar.
///
/// A altura vem de fora porque quem sabe medi-la é o card — ver
/// `ChartCarousel.totalHeight`. Medir aqui exigiria layout em duas passadas.
class StackedCard {
  const StackedCard({required this.height, required this.child});
  final double height;
  final Widget child;
}
```

Texto de interface em pt-BR. Arquivos em camelCase, como o projeto.

## Estratégia de teste

O protótipo já escrito vira o teste de `StackedScroll` — ele nasceu provando
exatamente o que precisa continuar valendo:

- parado no topo, cada card na posição natural;
- rolado um passo, o primeiro **para** no topo e o segundo chega 12px abaixo;
- rolado dois passos, três faixas de 12px empilhadas;
- a diferença entre topos consecutivos encaixados é exatamente `peek`;
- a ordem de pintura é a ordem da lista (Regra 2);
- alturas **diferentes** entre cards não desalinham o encaixe — os carrosséis
  reais têm 290, 340, 340, 340 e 330, e o protótipo usou todos iguais;
- rolagem além do fim (overscroll do iOS, `offset` negativo) não empurra o
  primeiro card para dentro da tela.

Para `ChartCard`: que o eyebrow aparece quando recebido e **não** ocupa linha
quando ausente — a causa, não a aparência.

Fora de teste automatizado, por decisão: se o efeito **fica bom** é chamada do
aparelho. Teste de widget mede posição, não fluidez, e a pergunta aqui é de
fluidez. Rolar no simulador é critério de aceite, não conferência opcional.

## Fronteiras

- **Sempre:** `flutter analyze lib/ test/` limpo; texto em pt-BR; rodar no
  aparelho antes de dar por pronto — é uma mudança de rolagem, e teste de widget
  não responde por fluidez; `ScrollController` criado uma vez e descartado no
  `dispose`.
- **Perguntar antes:** adicionar dependência (nenhuma é necessária); mudar
  altura de carrossel; mexer em `Utils/routeStats.dart` ou em qualquer conta;
  estender o efeito para a aba Resumo, cujos cards têm altura variável.
- **Nunca:** reconstruir o conteúdo do card dentro do `builder` do
  `AnimatedBuilder` (Regra 3); acrescentar espaço morto no fim da tela só para o
  último card completar a animação (Regra 4); duplicar na tela a conta de altura
  que mora no carrossel (Regra 5).

## Critérios de sucesso

- [ ] Rolando a tela, cada carrossel para ao chegar no topo em vez de sair.
- [ ] Cada card encaixa 12px abaixo do anterior, formando faixas coloridas.
- [ ] O card que desce cobre os encaixados, nunca o contrário.
- [ ] No fim da rolagem há **três** faixas de 12px (cards 0, 1 e 2), o quarto
      card aparece parcialmente e o quinto inteiro. O critério original dizia
      "cinco encaixados, 48px": era impossível, e contradizia a própria Regra 4
      — o quinto card nunca encaixa, logo o quarto nunca é coberto.
- [ ] O último carrossel rola até o fim e aparece inteiro, sem espaço morto.
- [ ] Cada card diz o próprio recorte no eyebrow; nenhum rótulo fica órfão.
- [ ] O carrossel reduzido à faixa **não** aceita arrasto horizontal, e volta a
      aceitar assim que reaparece.
- [ ] Arrastar a faixa para cima e para baixo rola a tela normalmente.
- [ ] Tocar na barra de status ainda volta ao topo (iOS).
- [ ] Trocar o período redesenha a pilha sem a rolagem pular de posição.
- [ ] Rolar é fluido no simulador — sem tranco ao encaixar.
- [ ] `flutter analyze lib/ test/` sem error/warning novo.
- [ ] `flutter test` passa (menos `widget_test.dart`, que já estava quebrado).

## Plano

Três blocos, nesta ordem, cada um entregável sozinho:

1. **`StackedScroll` + testes.** É onde mora todo o risco de lógica e a única
   parte provável sem aparelho. O protótipo já existe; virar widget de verdade é
   dar nome, extrair para `lib/widget/` e cobrir os casos que ele ainda não tem
   (alturas diferentes, overscroll).
2. **`eyebrow` no `ChartCard` e a sombra.** Independente do bloco 1 e visível
   sozinho — dá para conferir no aparelho antes de mexer na rolagem.
3. **A tela.** `ChartCarousel.totalHeight`, a `Column` do `_dashboard` vira uma
   lista de `StackedCard`, e os dois `_sectionLabel` viram eyebrow nas páginas.

Risco maior: o **tranco no encaixe**. Se a transição entre rolar e encaixar
ficar dura no aparelho, a saída é amortecer os últimos pixels — e isso só se
decide rolando. Não vou projetar amortecimento antes de ver se precisa.

Segundo risco: **o `State` dos carrosséis**. Dentro de um `Stack` eles são
casados por tipo e posição; a lista tem tamanho fixo, então deve preservar a
página atual de cada um. Cada card leva `ValueKey` mesmo assim, e o critério
"trocar o período não faz a rolagem pular" é o que verifica isso.

Verificação entre blocos: `flutter analyze` limpo e `flutter test` verde. No fim
do bloco 2 e do 3, rodar no aparelho.

## Tarefas

- [x] **T1** `lib/widget/stackedScroll.dart` — `StackedCard` e `StackedScroll`.
  - Aceite: encaixe correto com alturas diferentes; conteúdo não reconstruído.
  - Verificar: `flutter test test/widget/stackedScroll_test.dart`.
  - Arquivos: o widget e o teste.

- [x] **T2** `ChartCard` ganha `eyebrow` e sombra.
  - Aceite: sem eyebrow, o card fica idêntico ao de hoje.
  - Verificar: `flutter test test/widget/chartCard_test.dart` + os testes de
    `barRankChart`, `summaryCards` e `failureRateCard` seguem verdes sem edição.
  - Arquivos: `widget/chartCard.dart`, o teste novo.

- [x] **T3** `ChartCarousel.totalHeight`.
  - Aceite: carrossel de uma página não soma o bloco de bolinhas.
  - Verificar: `flutter test test/widget/chartCarousel_test.dart`.
  - Arquivos: `widget/chartCarousel.dart`, o teste.

- [x] **T4** `graficsScreen` monta a pilha; os `_sectionLabel` viram eyebrow.
  - Aceite: nenhum `_sectionLabel` sobra; as sete páginas de análise e as quatro
    de insucesso carregam o recorte.
  - Verificar: `flutter analyze` + aparelho.
  - Arquivos: `screens/graficsScreen.dart`.

- [ ] **T5** Rolar no aparelho e julgar o efeito. Ajustar `peek` e o
      espaçamento se preciso.
  - Aceite: sem tranco no encaixe; a pilha lê como pilha.
  - Verificar: `flutter run`.

- [x] **T6** Atualizar `docs/specs/graficos.md` e este arquivo. Feito: a seção
      Layout de `graficos.md` desenha a pilha, e a frase sobre o rótulo entre os
      blocos virou a do eyebrow. Falta só registrar o que a rolagem no aparelho
      (T5) decidir sobre `peek` e espaçamento.

## Fora de escopo

A aba Resumo (cards de altura variável — exigiria medir em tempo de layout); a
lista de rotas; animação de escala ou de opacidade nos cards encaixados; tocar
numa faixa da pilha para voltar àquele card; e qualquer mudança de conta,
recorte ou dado.

## Perguntas resolvidas

**1. O texto do eyebrow.** Resolvida: `'Rotas concluídas e pagas'` nos cards de
análise e de insucesso, `'Todos os status do período'` nos de dinheiro. É o que
ficou implementado nas 15 páginas.

**2. `peek` de 12px.** É o que o protótipo usou e o que os quadros de referência
aparentam. No fim da rolagem isso dá três faixas visíveis — ver o critério
corrigido. Ajustável em T5, com o efeito rodando.
