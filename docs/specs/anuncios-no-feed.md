# Spec: Anúncios entre os posts do feed

Status: **etapa 1 aprovada em 24/08/2026** · Criada em 2026-08-24 · A etapa 2
(AdMob de verdade) segue bloqueada pela publicação em loja

## Objetivo

Colocar anúncios entre os posts do mural, com cadência **irregular** — depois de
3 posts, depois de 5, depois de 4 —, para que o app tenha uma receita que
acompanhe o custo do Firebase quando escalar.

Usuário: o entregador que rola o feed. Sucesso = ele vê anúncio sem sentir que o
feed virou um mural de anúncios, e sem nunca tocar num por engano.

Dono: sucesso = a receita do feed cobre o que o feed custa em leitura de
Firestore. **Isso é medível, e a seção "A conta" abaixo mede.**

### O que esta spec entrega, e o que ela deixa para depois

Decisão do dono, tomada antes desta spec: **reservar o slot agora e ligar o
AdMob depois.** Então são duas etapas, e só a primeira está especificada para
implementação:

| | Etapa 1 — agora | Etapa 2 — quando publicar |
|---|---|---|
| cadência irregular | ✅ função pura + teste | — |
| slot na lista, com keys | ✅ placeholder visível | vira o `AdWidget` |
| dependência nova | ❌ nenhuma | `google_mobile_ads` |
| manifesto / plist / ATT / UMP | ❌ | ✅ |
| conta AdMob | ❌ | ✅ |

A etapa 1 é validável nos dois iPhones do dono hoje. A etapa 2 **não pode ser
concluída hoje**, e não por falta de trabalho: ver "O que impede a etapa 2".

## A conta — isto vale a pena?

Esta seção existe porque o objetivo declarado é financeiro, e objetivo
financeiro sem aritmética é torcida.

**Banner é o formato que menos rende, por ordem de grandeza.** No Brasil/Android:
banner ~US$ 0,19 de eCPM, intersticial ~US$ 1,22 (6,4×), premiado ~US$ 2,00
(10×). A diferença não é de leilão, é de formato — o banner ocupa 50dp e é
ignorável.

**O feed se paga com folga; o app inteiro fica no limite.** Uma abertura do feed
custa ~92 leituras de Firestore (US$ 0,0000552) e gera ~3 impressões. A eCPM
US$ 0,15, o banner cobre 8,2× o custo do feed. Mas uma abertura do **app**
inteiro são ~492 leituras (Resumo, Gráficos, lista, perfis), e aí a mesma eCPM
cobre 1,41×. Por usuário/mês, o empate é em **eCPM US$ 0,124** — perto do piso
da faixa realista.

**O AdMob só paga a partir de US$ 100 acumulados.** Com 3 impressões/usuário/dia
e eCPM US$ 0,15: 100 usuários = US$ 1,35/mês = **74 meses até o primeiro
depósito**. 1.000 usuários = 7,4 meses. 10.000 = primeiro mês.

**Conclusão honesta:** o anúncio não é receita antes da escala; é o que impede a
escala de sair do bolso do dono. E, no ponto em que ele começa a pagar, a maior
parte do custo é das telas que **não** têm anúncio.

> **Alternativa registrada e não escolhida:** um intersticial por sessão renderia
> mais que todos os banners do feed juntos, e o app tem uma transição natural
> para ele (voltar do `AddIter` depois de salvar uma rota). É mais invasivo e o
> dono pediu banner. Fica registrado porque a conta acima torna a pergunta
> legítima, não porque a spec recomende trocar.

## Tech Stack

Etapa 1: nada novo. Dart puro em `lib/Utils/`, `flutter_test`.

Etapa 2: `google_mobile_ads` (o plugin 9.1.0 traz o GMA iOS 13.7.0). Piso de
iOS 13.0 no plugin, e o Podfile já declara 15.0. **O piso real é o Xcode**: o
GMA iOS 13.4.0 exige Xcode 26.2 ou maior; a máquina do dono tem 26.6.

## Commands

```bash
flutter pub get
flutter analyze lib/
flutter test test/unit/feedAds_test.dart
flutter test
flutter run -d <device-id>          # a validação que importa é no aparelho
```

## Estrutura

```
lib/Utils/feedAds.dart          a cadência: função pura, sem Flutter dentro
lib/widget/feedAdSlot.dart      o slot desenhado — placeholder na etapa 1
lib/widget/feedTab.dart         passa a montar a lista de slots
test/unit/feedAds_test.dart     a cadência, sem Firestore
test/widget/feedAdSlot_test.dart o slot não imita o card de post
docs/specs/anuncios-no-feed.md  esta spec
```

## O desenho da cadência

### O problema: "aleatório" e "estável" ao mesmo tempo

O feed reconstrói a lista **dezenas de vezes** por página carregada: há
`setState` em 11 pontos do `_FeedTabState` (curtida, contadores, URL de foto,
denúncia, bloqueio, volta da folha de comentários) e o pai reconstrói o filho a
cada perfil que chega do prefetch. Uma posição sorteada dentro do `itemBuilder`
seria re-sorteada em todas elas: **o anúncio trocaria de lugar debaixo do dedo
de quem rola**, e a posição da rolagem pularia junto.

Pior: três filtros encolhem `_posts` **depois** de carregada — post apagado,
autor bloqueado, post denunciado. Uma cadência posicional ("anúncio nos índices
3, 8, 12") escorrega para outros lugares sem ninguém recarregar nada.

`Post.id` é a **única** âncora estável: é o id do documento e a chave de todos os
mapas laterais do feed. `createdAt` não serve — ele volta `DateTime.now()`
enquanto o `serverTimestamp()` não confirma, então a data de um post recém-
publicado muda entre o snapshot local e o do servidor.

### Três desenhos, e por que o terceiro

**A — âncora local:** `hash(post.id) % 4 == 0` põe anúncio depois *daquele*
post. Estabilidade perfeita: cada anúncio é do seu post, e apagar um post não
move nenhum outro. **Rejeitado pela distribuição**: simulado sobre 200 ids UUID,
deu 55 anúncios com gap mínimo **1** — 15 pares de anúncios colados um no outro
— e gap máximo 13. A distribuição é geométrica; "3, depois 5, depois 4" não
existe nela.

**B — sortear uma vez por página e guardar no State:** funcionaria, e cria
estado novo que precisaria ser invalidado nos quatro lugares onde `_posts` muda
(`_load`, `_refresh`, `_forget`, `didUpdateWidget`). Trocar de aba destrói o
`State` — a sequência recomeçaria do 3 a cada ida ao Ranking e volta.

**C — caminhada por prefixo, gap escolhido pelo hash do post que abre o bloco
(recomendado).** Percorre a lista do começo guardando quanto falta para o
próximo anúncio; ao abrir cada bloco, `gap = cadence[hash(id) % cadence.length]`
com `cadence = [3, 5, 4, 3]`, e o anúncio entra **depois** do último post do
bloco.

| | A | B | C |
|---|---|---|---|
| estável entre rebuilds | ✅ | ✅ | ✅ |
| estável ao paginar | ✅ | ✅ | ✅ (o prefixo não muda com `addAll`) |
| igual em duas aberturas | ✅ | ❌ | ✅ |
| testável sem Firestore | ✅ | difícil | ✅ |
| entrega a cadência pedida | ❌ | ✅ | ✅ |
| estado novo no `State` | 0 | 4 pontos de invalidação | 0 |

Medido com `cadence = [3,5,4]` sobre 200 ids: 54 anúncios, gaps **sempre** em
{3,4,5}, sequência `3,3,5,4,3,5,3,4,3,3…`. É o que o dono descreveu.

### Duas decisões dentro do desenho C

**O hash é nosso, não `String.hashCode`.** O SDK diz que os hashes de
`Object.hash`/`hashAll` "não são garantidos estáveis entre execuções… o
algoritmo exato pode diferir entre plataformas ou entre versões das
bibliotecas", e `String.hashCode` só promete compatibilidade com `==`. Hoje é
estável na prática — e é exatamente esse tipo de estabilidade não contratada que
quebra num `flutter upgrade`, silenciosamente, mudando o layout do feed de todo
mundo. Um FNV-1a de seis linhas resolve, e com ele o teste pode afirmar o layout
**exato** (`['p1','p2','p3','anúncio','p4'…]`).

**Sem cache, e é o determinismo que dispensa a invalidação.** `feedWithAds` é
O(n) sobre dezenas a poucas centenas de itens e devolve sempre o mesmo
resultado. Chamá-la uma vez em `_body()` custa menos que o `ListView.builder`
que vem depois, e não cria o campo de State do desenho B. *(Quando o AdMob
entrar, o que precisa de cache é outra coisa: os objetos `BannerAd`, por id
âncora — ver "A pegadinha do AdWidget".)*

### A assinatura

```dart
/// Um item da lista do feed: ou um post, ou um anúncio.
sealed class FeedSlot { }
class PostSlot extends FeedSlot { final Post post; }
class AdSlot  extends FeedSlot { final String anchorId; }  // id do post que o abre

/// A lista inteira, com os anúncios já no lugar.
///
/// Determinística: os mesmos posts devolvem os mesmos slots, sempre.
List<FeedSlot> feedWithAds(List<Post> posts, {List<int> cadence = kFeedCadence});
```

`AdSlot.anchorId` não é decoração: é a chave do cache de `BannerAd` na etapa 2,
e é o que permite o teste afirmar *qual* anúncio é qual.

## Onde o anúncio entra na tela — e isto é política, não estética

Esta seção é a de maior risco da spec. **Suspensão de conta AdMob não é
apelável** ("Suspensions are non-appealable"), e a mesma decisão de
posicionamento é julgada também pela política de Anúncios Enganosos ou
Disruptivos do Google Play — a Google já removeu mais de 600 apps do Play
banindo simultaneamente as contas AdMob. Errar aqui não custa a receita do slot:
custa o app e a conta juntos.

**1. O formato é *inline adaptive banner*, não banner fixo.** A página de
implementações recomendadas do AdMob só recomenda banner "at top" ou "at bottom"
do app. O formato que a Google desenhou para ficar dentro da rolagem é outro:
o inline adaptive — "they are intended to be placed in scrolling content". A
altura não é 50/100 fixa: sai de `MediaQuery.width`, e precisa ser conhecida
**antes** de o anúncio carregar, senão a lista salta quando ele chega.

**2. O anúncio não pode encostar no coração e no balão de comentário.** A regra
é escrita: banner não deve ficar "next to interactive buttons", porque "close
proximity of banner ads to other elements within an app is one of the biggest
causes of accidental clicks". O `PostCard` fecha com dois `IconButton` (curtir,
comentar) e tem `margin: bottom 12` — um anúncio inserido depois do card nasce
**12 px lógicos abaixo do botão de comentar**. O slot precisa de folga vertical
própria, bem maior que 12 px, e de um separador não clicável.

**3. O anúncio não pode parecer um post.** É violação escrita nos dois sentidos:
"format ads so that they become indistinguishable from other content" e "format
site content so that it is difficult to distinguish it from ads". O desenho mais
tentador — embrulhar o banner no mesmo `Container` do `PostCard`
(`grey.shade50` + `BorderRadius.circular(14)`) "para combinar com o feed" — é
exatamente o que a regra proíbe. **O slot tem de ler como outro objeto**, com
rótulo "Publicidade" visível.

**4. Banner ancorado no rodapé está descartado.** É desencorajado "ads
sandwiched between app content and navigation menus", e a Home é
`body: screens[current]` seguido de `bottomNavigationBar` — um banner fixo ali
ficaria literalmente entre o feed e a barra. A intuição do dono (entre os posts)
é de fato a mais segura das duas.

**5. Densidade: a regra escrita é "mais anúncio que conteúdo", medida na tela
visível** — não há limite numérico de anúncios por tela em app. Os "30%" que
circulam em fórum são do Better Ads Standards de **mobile web**; o padrão de
Mobile App não tem limiar de densidade, só reprova intersticial interruptivo. A
cadência mínima de 3 posts já garante que dois slots não caibam no mesmo
viewport. O risco que sobra: um post só de texto curto (o app permite post sem
foto) ao lado de um anúncio alto pode deixar o viewport majoritariamente
anúncio.

## O que impede a etapa 2 hoje

Não é falta de trabalho — são três portas fechadas, e vale saber antes de
investir:

**O app não está em loja nenhuma, e sem isso não há anúncio de verdade.** O
AdMob faz um *app readiness review* que só começa quando o app está vinculado a
uma loja suportada; "apps listed exclusively in unsupported stores can't be
reviewed and will receive limited ad serving". E publicar na Play esbarra no
`release` do Android ainda assinando com a **chave de debug**.

**100% do tráfego de anúncio hoje seria o próprio dono.** Dois iPhones, duas ou
três contas dele. "Publishers may not click their own ads"; "testing your own ads
by clicking them is not allowed"; e a suspensão "may refund all account
earnings". Isso não é risco marginal — é o perfil de tráfego que o antifraude
foi feito para pegar. **Requisito, não observação:** unidade demo em debug,
unidade real só em release, e os dois iPhones registrados como test device
**antes** da primeira requisição a uma unidade real.

**`app-ads.txt` exige um domínio que o projeto não tem.** O crawler usa o site
declarado na ficha da loja. A Google diz "to prevent a significant loss in ad
revenue, you'll need to implement an app-ads.txt file" — o efeito confirmado é
receita menor, não bloqueio. *(A versão "obrigatório desde jan/2025" vem de blog,
não de página do Google: tratada aqui como não verificada.)*

## O contorno de build que o plugin exige (iOS)

**`google_mobile_ads` 9.1.0 não compila neste projeto sem uma flag de
compilador**, e isso foi descoberto montando o protótipo — antes de qualquer
linha da etapa 2. Se ela acontecer, este contorno é **pré-requisito**: sem ele,
o próximo `flutter clean` seguido de `pod install` derruba o build outra vez,
sem ninguém lembrar o motivo.

O erro:

```
Include of non-modular header inside framework module
'google_mobile_ads.FLTAd_Internal':
  …/GoogleMobileAds.framework/PrivateHeaders/GoogleMobileAds_Beta.h
```

`FLTAd_Internal.h:22` e `FLTAdPreloader.h:17` importam
`<GoogleMobileAds/GoogleMobileAds_Beta.h>`, e esse header mora em
**PrivateHeaders** do framework, fora do module map. **Não é skew de versão** —
verificado: o plugin pede `Google-Mobile-Ads-SDK ~> 13.7`, o 13.7.0 foi
instalado, e o header está em `PrivateHeaders/` nas duas fatias do xcframework.
O plugin importa um header privado da própria dependência dele, e 9.1.0 é a
última versão publicada.

A correção é `CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES` em
`ios/Flutter/Debug.xcconfig` e `Release.xcconfig` (o Podfile mapeia
`Profile => :release`).

**E o lugar importa.** A primeira tentativa foi no `post_install` do Podfile,
escopada ao alvo `google_mobile_ads` — e falhou **igual**. A flag chegou ao
`pbxproj` do plugin, em três configurações, e o build quebrou do mesmo jeito: a
validação do módulo acontece no contexto de **quem o importa**, e quem importa é
o `GeneratedPluginRegistrant` do `Runner`. Por isso a flag mora no xcconfig do
app, e não no pod.

Sai daqui quando o plugin corrigir. É o tipo de linha que fica para sempre se o
comentário não disser por que ela entrou.

## A pegadinha do AdWidget, e a maior incerteza desta spec

**Um `AdWidget` nunca pode reusar um objeto `Ad`.** O erro é literal: *"This
AdWidget is already in the Widget tree. If you placed this AdWidget in a list,
make sure you create a new instance in the builder function with a unique ad
object."* Isso colide de frente com `ListView.builder`, que chama o
`itemBuilder` de novo para o mesmo índice ao rolar. Daí o cache de `BannerAd`
**por `anchorId`** (não por índice de item) e o `dispose()` de cada um no
`dispose()` da aba — sem isso, cada rolagem dispara requisição nova, e
requisição sem impressão é o que derruba a taxa de preenchimento.

**E aqui está a incerteza que a spec não resolve:** o codelab oficial do Google
carrega **um** anúncio, não N (`static final _kAdIndex = 4;`, um único `_ad`).
Não existe guia oficial para vários banners simultâneos numa lista, nem número
recomendado. Cada banner é uma platform view nativa com WebView dentro, e há
uma issue de travamento de rolagem no iOS fechada como *not planned*, sem
solução.

### O protótipo rodou, e o banner passou

**Medido em 24/08/2026, iPhone de Wesley (iOS 26.6), `--profile`, 60 posts com
16 slots de anúncio e seis banners vivos simultâneos:**

| | UI | Raster |
|---|---|---|
| pior quadro | 3,1 ms | 3,7 ms |
| média | 0,5 ms | 1,0 ms |

Orçamento a 60 Hz: 16,67 ms. O pior quadro usou 22% dele, e nenhum quadro foi
perdido — as faixas do medidor são retas. **O formato banner está aprovado; o
anúncio nativo sai do caminho crítico** e fica como alternativa registrada, não
como plano.

Ressalva honesta: seis banners vivos, não os dezesseis. O `ListView.builder` só
constrói o que está perto do viewport, então o pedido é preguiçoso por
construção — e nenhum anúncio é descartado ao sair da tela, então os seis
acumularam. É o comportamento que a etapa 2 quer, e a margem de 78% do
orçamento é larga o bastante para não exigir nova medição a cada anúncio a mais.

**Duas regras que o protótipo produziu, e que a etapa 2 herda:**

1. **O pedido não sai do `build`.** No protótipo ele saía — funcionava, e
   produziu um contador incoerente na tela ("6 carregados · 3 pedidos"), porque
   a `AppBar` é construída antes dos itens e lia o campo antes de os itens o
   incrementarem. Mutar estado durante a construção é o defeito, e o número
   errado foi só o sintoma visível. Na etapa 2 o pedido sai de um
   `addPostFrameCallback` ou do momento em que a página chega.
2. **Nenhum `BannerAd` é descartado ao sair do viewport.** Foi assim que se
   mediu, e foi o pior caso de propósito. Se um dia a lista crescer a ponto de
   incomodar, descartar por distância do viewport é a saída — mas medir antes,
   porque descartar e repedir gasta requisição sem impressão, que é o que
   derruba a taxa de preenchimento.

> **O portão que isto fechou:** antes de a etapa 2 virar código, um **protótipo
> medido em aparelho** — 5 banners vivos numa lista rolável, olhando fluidez e memória.
> Se não sustentar, os caminhos são carregar anúncio só para os slots próximos
> do viewport, ou trocar banner por **anúncio nativo**, que é o que a própria
> Google recomenda para feed ("the small template is ideal for ListViews… for
> instance for in-feed ads") e que também resolve melhor a exigência de o
> anúncio não parecer um post.

## Três consertos que vêm junto

**A key do `PostCard`.** O `itemBuilder` devolve `PostCard(post: …)` **sem
key** — a `ValueKey('post-${post.id}')` existe, mas dentro do build do card, um
nível abaixo da raiz. O `ListView` casa elementos por posição. Hoje funciona por
sorte (tudo é `StatelessWidget`); um banner **tem estado**, e casar
posicionalmente um banner com um card depois de apagar um post do meio é o caso
exato em que a falta de key aparece. **Reservar o slot agora é a hora certa de
acertar isso**, enquanto o erro ainda é invisível.

**As três aritméticas de índice.** `itemCount: _posts.length + 2`, `index == 0`,
`index == _posts.length + 1`, `_posts[index - 1]` — três constantes literais em
três linhas do mesmo builder. Qualquer item extra quebra as três de uma vez. A
lista de slots as substitui por uma indexação só.

**Dois comentários que prometem a coisa errada.** `feedTab.dart:447` diz "o
espaço onde o anúncio entra, quando entrar: um a cada N posts" — e está no
**rodapé**, disputando índice com o spinner, não entre os posts. `amigos.md:906`
e `:1557` repetem "um a cada N posts". As três passagens descrevem a cadência
regular que esta spec descarta.

## Estilo de código

O do projeto, e em particular: função pura em `Utils/`, comentário que explica o
**porquê** e nomeia o defeito que a linha evita.

```dart
/// A cadência: quantos posts entre um anúncio e o próximo.
///
/// Irregular de propósito. Com um número só, o olho aprende o ritmo em duas
/// rolagens e o anúncio vira parte do cenário — que é o oposto do que ele
/// precisa ser para valer alguma coisa.
const List<int> kFeedCadence = [3, 5, 4, 3];

/// FNV-1a, escrito aqui em vez de `String.hashCode`.
///
/// O `hashCode` do SDK só promete ser compatível com `==` — nada sobre ser o
/// mesmo número amanhã. Hoje ele é estável na prática, e é justamente essa
/// estabilidade não contratada que quebraria num `flutter upgrade`: o layout do
/// feed de todo mundo mudaria de uma vez, sem uma linha de diff para explicar.
int _fnv1a(String value) { … }
```

## Estratégia de teste

**`test/unit/feedAds_test.dart`** — a cadência, sem Firestore e sem Flutter:

- o layout **exato** de uma lista de ids conhecidos (`['p1','p2','p3','ad','p4'…]`);
- **determinismo**: a mesma entrada devolve a mesma saída em duas chamadas;
- **estabilidade ao paginar**: `feedWithAds(primeiros20)` é prefixo de
  `feedWithAds(primeiros20 + próximos20)` — a garantia de que a página nova não
  remexe o que já está na tela;
- todos os gaps caem em `kFeedCadence` — nunca dois anúncios colados, que é o
  defeito que reprovou o desenho A;
- lista com menos posts que o primeiro gap não recebe anúncio nenhum;
- lista vazia devolve lista vazia (o feed vazio tem outro caminho de desenho, que
  nunca passa pelo builder);
- apagar um post do meio **não move** os anúncios acima dele.

**`test/widget/feedAdSlot_test.dart`** — o placeholder da etapa 1: que ele não
imita o card de post (fundo e raio diferentes), que carrega o rótulo
"Publicidade" e que tem folga vertical maior que a margem de 12 px do card.

**O que não dá para testar, e por isso vira verificação em aparelho:** não
existe hoje nenhum teste de `FeedTab` nem de `PostController` — a aba abre o
Firestore no `initState`. A aritmética do builder, a paginação e os filtros
client-side estão sem rede de proteção, e esta entrega não muda isso: ela extrai
a parte testável (a cadência) e deixa a tela como está. Fluidez de rolagem e
altura do slot são do aparelho.

## Fronteiras

- **Sempre:** a cadência é função pura e determinística; anúncio visualmente
  distinto do post, com rótulo; folga entre o slot e a fileira de curtir/
  comentar; unidade **demo** em debug.
- **Perguntar antes:** `google_mobile_ads` (dependência nova); qualquer anúncio
  fora do feed; trocar banner por intersticial ou nativo; mexer no
  `AndroidManifest.xml` ou no `Info.plist`.
- **Nunca:** anúncio embrulhado igual a um post; anúncio colado no botão de
  curtir; unidade real num build de debug; tocar no próprio anúncio ao vivo;
  anúncio numa tela de comunicação privada (a política "Ads in private
  communications" proíbe, e vale registrar antes de existir DM).

## Critérios de sucesso

- [ ] Rolar o feed inteiro com o placeholder e **nunca** ver o anúncio mudar de
      lugar — nem ao curtir, nem quando a foto carrega, nem ao paginar.
- [ ] Os intervalos observados são 3, 4 ou 5 posts, sem repetir o mesmo número
      sempre e sem dois anúncios visíveis na mesma tela.
- [ ] Apagar um post do meio da lista não move nenhum anúncio acima dele.
- [ ] `feedWithAds` do lote 1 é prefixo do resultado do lote 1+2.
- [ ] Nos dois iPhones, nenhum slot nasce a menos de 24 px do botão de comentar.
- [ ] Duas aberturas do app, mesmos posts, mesmo padrão de anúncios.
- [ ] `flutter test` e `flutter analyze lib/` limpos.

## Decisões

**1. Feed curto não recebe anúncio.** Com menos posts que o primeiro gap, a
lista sai sem nenhum. Aprovado pelo dono em 24/08/2026. Não é só estética: dois
posts com um banner no meio é o caso literal de "mais anúncio que conteúdo", que
é a única regra de densidade que a política de fato escreve.

**2. A folga é 24 px, acima e abaixo.** Contra os 12 px de margem do `PostCard`.
Custa tela e compra distância do botão de comentar — que é onde a política
enxerga clique acidental. Aprovado em 24/08/2026.

**3. O rótulo é "Publicidade".** Aprovado em 24/08/2026. Fica no slot, visível,
e é metade do que impede o anúncio de ser confundido com post; a outra metade é
o slot não imitar o `Container` do card.

## Os identificadores

Não são segredo — vão dentro do APK e qualquer um os extrai de lá. O que os
protege é a política, não o sigilo. Ficam aqui porque some-se com eles no
console mais rápido do que se imagina.

| | iOS | Android |
|---|---|---|
| **App ID** (til) | `ca-app-pub-8153139669866970~5951899863` | `ca-app-pub-8153139669866970~8362440786` |
| **Bloco banner do feed** (barra) | `ca-app-pub-8153139669866970/7820399787` | `ca-app-pub-8153139669866970/9628305478` |

O App ID vai em `ios/Runner/Info.plist` como `GADApplicationIdentifier` e em
`android/app/src/main/AndroidManifest.xml` como
`com.google.android.gms.ads.APPLICATION_ID` — **etapa 2**, nenhum dos dois é
tocado agora.

### E as unidades demo, que são as que o código vai usar em debug

Estas não pertencem a conta nenhuma: *"the Google-provided demo ad units are not
associated with your AdMob account, so there's no risk of your account
generating invalid traffic when using these ad units"*.

| | iOS | Android |
|---|---|---|
| banner adaptativo | `ca-app-pub-3940256099942544/2435281174` | `ca-app-pub-3940256099942544/9214589741` |
| banner fixo | `ca-app-pub-3940256099942544/2934735716` | `ca-app-pub-3940256099942544/6300978111` |

**A regra que decorre disso é a mais importante da etapa 2:** o ad unit id sai de
uma constante que é a **demo em debug** e a real em release — nunca a real num
build de desenvolvimento. É a mesma forma que a chave do OpenWeather já tem no
`.env`, e é a única defesa grátis contra o risco dominante deste app hoje, que é
100% do tráfego de anúncio ser o próprio dono.

**4. O anúncio nunca é o último item da lista.** Fechando o bloco no último post
carregado, ele ficaria encostado na barra de navegação num feed já todo
carregado — o arranjo que o AdMob desencoraja ("ads sandwiched between app
content and navigation menus"), e também a tela em que o anúncio tem menos
conteúdo em volta. Conferido que **não quebra a propriedade de prefixo**: o
anúncio passa a ser acrescentado quando a página seguinte chega, e o que já
estava na tela não se move. Tem teste dos dois lados.

**5. O protótipo é portão da etapa 2.** Aprovado em 24/08/2026. Antes de a
etapa 2 virar código, um protótipo com vários banners vivos numa lista rolável,
medido em aparelho. Ele pode reprovar o formato banner em favor do **anúncio
nativo** — que é o que a própria Google recomenda para feed e que também resolve
melhor a exigência de o anúncio não parecer um post.

O protótipo roda por um `main` próprio (`flutter run -t lib/main_prototipo.dart
--profile`), **não** por uma rota dentro do app: assim ele não encosta no
`AuthGate`, não precisa de Firebase e não tem como sobrar num build de verdade.
E usa o **App ID de exemplo do Google** — `ca-app-pub-3940256099942544~3347511713`
no Android, `~1458002511` no iOS —, de modo que os identificadores reais do dono
nem entram no binário.

## Questões em aberto

Nenhuma. As quatro decisões estão tomadas.

## Nota sobre as fontes

Os fatos de política, configuração e preço desta spec vieram de páginas oficiais
do Google (support.google.com/admob, developers.google.com/admob/flutter) e
foram levantados em 24/08/2026. A etapa de verificação independente **não
concluiu** — parou num limite de sessão —, então os números de eCPM de mercado
e os prazos de aprovação devem ser tratados como ordem de grandeza, não como
contrato. As regras citadas entre aspas são texto literal das páginas.
