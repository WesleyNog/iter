# Spec: Notificações push

Status: **em implementação** · Escrita em 24/08/2026, aprovada em 25/08/2026 ·
Etapa A: A2 e A3 feitas e verificadas em APK; A1 pendente no console do dono ·
Etapas B e C não começaram

## Objetivo

Avisar o entregador no celular quando algo social acontece com ele — **mesmo
com o app fechado** — e levá-lo, no toque, à tela onde aquilo está.

Usuário: o entregador. Sucesso = o Cleyton manda um convite às 21h, o celular do
Wesley acende com "Cleyton enviou um convite de amizade pra você" sem o app
estar rodando, e um toque abre a aba Amigos já com o convite na tela.

Cinco eventos nesta primeira leva:

| # | Quando | Quem recebe | Título / corpo | O toque abre |
|---|---|---|---|---|
| 1 | Convite de amizade enviado | quem recebeu | «Cleyton» / «enviou um convite de amizade pra você» | Amigos → Amigos |
| 2 | Convite aceito | quem convidou | «Wesley» / «aceitou seu convite de amizade» | Amigos → Amigos |
| 3 | Um amigo te ultrapassa no ranking | quem foi ultrapassado | «Cleyton» / «passou você em Rotas» | Amigos → Ranking, no critério citado |
| 4 | Curtida: a 1ª, depois 10, 20, 30… | o dono do post | «10 curtidas» / «Seu post chegou a 10 curtidas.» | Amigos → Feed, no post |
| 5 | Comentário: o 1º, depois 5, 10, 15… | o dono do post | «Cleyton» / «comentou no seu post» | Amigos → Feed, thread aberta |

## O que eu assumi

Corrija agora, ou sigo com isto:

1. **"App fechado" é o app deslizado das recentes, não force-stop.** No Android,
   quem dá force stop pelas Configurações do sistema — e vários OEMs brasileiros
   tratam o "limpar tudo" assim — para de receber até reabrir o app na mão. Isso
   é do sistema operacional e nenhum desenho contorna.
2. **Notificação é aviso, não caixa de entrada.** Não existe tela de
   "notificações" dentro do app, nem badge de não-lidas, nem histórico. O que se
   perdeu, perdeu-se; o estado mora nas telas (a aba Amigos, o Ranking, o Feed).
3. **Todo push nasce no servidor.** O cliente nunca escolhe destinatário nem
   texto — ver "Nenhum push sai do cliente", abaixo.
4. **Só português.** Sem i18n, como o resto do app.
5. **Um aparelho pode ter vários donos ao longo do tempo, e um dono vários
   aparelhos.** Os dois casos são tratados; o segundo é o pedido literal
   ("o(s) celular(es)").
6. **Notificação de ranking é do mês corrente.** Uma ultrapassagem em junho,
   anunciada em agosto, é um evento sobre o qual ninguém pode agir.

## A afirmação que carrega a feature: isto exige um servidor

O app não tem como se notificar com ele fechado. Quem desenha a notificação na
bandeja é o sistema operacional, a partir de uma mensagem que **precisa nascer
em ambiente confiável** — só quem tem a credencial de administrador do projeto
pode mandar FCM. Não há caminho pelo cliente, e não é questão de estilo.

Logo: **esta é a primeira Cloud Function do projeto.** O `CLAUDE.md` já
antecipou o momento e deixou a ordem escrita — *"Before the first Function, set
a billing budget and alert"*. Isso deixa de ser conselho e vira pré-requisito,
por uma razão nova: até hoje, escrita alheia custava quota; a partir daqui,
escrita alheia custa **dinheiro do dono do projeto**. Cada curtida de qualquer
pessoa em qualquer post passa a acordar uma função que ele paga.

O segundo item que sai da gaveta é o **App Check**, que `amigos.md` já marca como
"faça antes do app sair do seu celular". Push piora o caso que aquela spec
descreve: sem App Check, um script de dez linhas escrevendo em `posts` deixa de
ser spam na cota e vira **spam na tela de bloqueio de todo mundo**.

E há uma decisão que também é do `CLAUDE.md` e vale literalmente aqui: *"the
runaway risk is a trigger that writes the document that fires it"*. Nenhum
contador, marcador ou estado de controle desta feature mora no documento que
dispara a função. Nenhum.

### Nenhum push sai do cliente

Não existe função *callable* de envio. Todos os cinco eventos são gatilhos de
Firestore: a função lê um documento que **as regras já validaram** e decide
sozinha o texto e o destinatário.

A justificativa honesta não é "callable é inseguro" — um callable bem escrito
confere `request.auth` como qualquer outra coisa. É que um callable de envio
teria de **reconferir, em código, tudo o que a regra já garante no documento**:
que o convite é de quem diz ser, que o post existe e não é lápide, que não há
bloqueio entre as partes. Duas implementações do mesmo invariante, e a que
ficasse para trás mandaria push que a regra teria negado. O gatilho herda a
validação de graça.

O preço dessa escolha aparece no evento 2 e no evento 3, e está registrado
onde dói, em cada um.

## Pré-requisitos que não são código deste repositório

Nenhum deles tem teste que acuse a ausência. Em ordem:

1. **Orçamento e alerta de faturamento no Google Cloud.** Antes da primeira
   Function, como o `CLAUDE.md` manda.
2. **App Check**, e ele são **duas etapas**, não um interruptor:
   **(2a)** SDK no app com a imposição **desligada**, instalado nos dois
   aparelhos, métricas observadas alguns dias; **(2b)** imposição de Cloud
   Firestore e Cloud Storage — nunca Authentication. Ver "App Check: 90%
   console". A metade "DeviceCheck/App Attest" cai: sem conta paga da Apple não
   há como gerar a chave, é a mesma seção Keys que a A4 já registra como
   inacessível.
3. **Chave de autenticação APNs (`.p8`) enviada ao console do Firebase**, em
   Cloud Messaging → Apple app configuration. **Exige conta paga da Apple, que o
   dono não tem** (25/08/2026) — a seção Keys do portal só existe para membros
   pagantes. Sem ela o iOS não recebe nada, em silêncio.

   Consequência assumida: **a primeira publicação é só Android.** O iOS fica
   preparado e desligado — ver "iOS: o caminho pronto".
4. **Capability de Push Notifications no target Runner.** Também depende da conta
   paga: perfil de provisionamento gratuito **não** carrega esse entitlement.
5. **APIs do Cloud Functions habilitadas no `iter-mn`.** Hoje
   `firebase functions:list --project iter-mn` falha, o que é o sintoma de que
   nem foram ligadas. O primeiro `deploy` liga.
6. **Firestore do `iter-mn` está em `southamerica-east1`** (verificado com
   `firebase firestore:databases:get "(default)"`). As funções vão para a mesma
   região; gatilho de Firestore exige compatibilidade de região com o banco.

## O desenho

### 1. O token: `fcmTokens/{sha256(token)}`, e o uid é o corpo

```
fcmTokens/{sha256(token)}  ->  { token, uid, platform, updatedAt }
```

A chave é o **aparelho**, não o dono. Isso é o oposto do que a intuição pede
(`user/{uid}/tokens/{token}`) e é o ponto inteiro do desenho: o token do FCM
identifica a *instalação do app*, não a pessoa. Com o uid no prefixo do caminho,
`user/A/tokens/T` e `user/B/tokens/T` são dois documentos diferentes, e o
Firestore fica **estruturalmente incapaz** de impedir que o mesmo aparelho
apareça sob dois donos ao mesmo tempo — que é exatamente o bug do celular
emprestado: A sai, B entra, e A continua recebendo os convites dele no aparelho
do B.

Com o token como id, os dois caminhos viram um documento só e a colisão
desaparece **por forma**. É o mesmo raciocínio de `nicknames/{apelido}`, com uma
diferença deliberada: ali o `update` é negado, aqui é **permitido**, sob
`request.resource.data.uid == request.auth.uid`. A reivindicação legítima é de
quem está fisicamente com o aparelho e autenticado agora, e é isso que faz o
**login** — o único momento confiável do ciclo — restabelecer o invariante
sozinho, mesmo quando o logout nunca rodou.

O id é o **sha256 do token em hex**, não o token cru. O Google trata o token
como string opaca e não promete alfabeto nenhum; um token que um dia venha com
`/` seria um id inválido, e a falha seria silenciosa e permanente naquele
aparelho. 64 caracteres de `[0-9a-f]` custam zero e o wildcard da regra fica
trivial de prender.

**Quem grava, e quando.** Na abertura do app, em `HomeScreen.initState`, junto
com `ProfileController.publish` — e **não** no login. É a mesma lição que
`user/{uid}` ensinou e que `amigos.md` registrou: `signInWithGoogle()` só roda
quando a `LoginScreen` o chama, e quem tem sessão restaurada cai direto na Home.
Pendurar no login é a receita para todo usuário existente nunca registrar token
e nunca receber notificação nenhuma — o mesmo congelamento, de novo. Mais o
`onTokenRefresh`, que o FCM emite quando rota o token.

**Quem apaga.** `GoogleSignInService.signOut()`, e **antes** de
`_auth.signOut()`: depois dele `request.auth` é nulo e a regra de dono nega a
escrita, deixando o token vivo para sempre. Melhor esforço — um delete que falhou
não pode impedir a saída da conta —, e é por isso que a sobrescrita no login do
próximo dono é a rede de segurança de verdade, não o logout.

Apagar o documento **não invalida o token no aparelho**. O que ele faz é parar
de mandar. Isso basta.

### 2. O envio: sempre `notification` **e** `data`

Toda mensagem carrega as duas metades. O `notification` é o que o sistema
operacional desenha com o app fechado; o `data` é o que diz para onde ir no
toque. Uma mensagem só-`data` não acorda app morto no iOS por construção e, no
Android, é entregue com prioridade baixa e pode ser adiada — a metade `data`
sozinha entrega a feature no emulador e falha no aparelho do dono.

O `data` tem todos os valores em **string**, que é a única coisa que o FCM aceita:

```
{ tipo: 'convite' | 'aceite' | 'ranking' | 'curtidas' | 'comentarios',
  de: '<uid>',            // quem causou, quando há um
  postId: '<id>',         // eventos 4 e 5
  criterio: 'rotas' | 'ritmo' | 'insucesso',   // evento 3
  mes: '2026-08' }        // evento 3
```

E **`android: { priority: 'high' }` em toda mensagem**. O padrão do FCM é
`normal`, e mensagem normal no Android é entregue nas janelas de manutenção do
Doze — o convite das 21h chega quando o motorista pega o telefone, minutos ou
horas depois. Passa em teste de mesa, com a tela ligada, e falha exatamente o
critério de aceite nº 1. Para os aparelhos anteriores ao Android 8, que o
`minSdk 24` ainda admite, vai junto
`android.notification.notification_priority: 'PRIORITY_HIGH'`.

**O corpo da notificação é a primeira coisa deste app que sai do perímetro das
regras.** Ele é entregue sem checagem de autenticação no instante da entrega e
aparece na tela de bloqueio, para quem estiver com o celular na mão. Duas
consequências que estão escritas nos eventos: nunca vai texto de terceiro no
corpo, e nunca vai dinheiro, CPF, endereço ou qualquer coisa de `user/{uid}`.

### 3. Com o app aberto: o toast que já existe — e a armadilha do iOS

Com o app em primeiro plano, **nem Android nem iOS desenham a notificação
sozinhos**. Quem desenha somos nós, e o app já tem a peça: `showNotification`
(`lib/widget/notificationPush.dart`), que inclusive já aceita um link "Ver" com
`onTap` — o gancho do deep link em foreground sai de graça.

Isso é o que dispensa `flutter_local_notifications`. A recusa é a regra de escopo
do projeto aplicada: a dependência existiria para desenhar em foreground o que o
app já sabe desenhar.

**E aqui está a armadilha que quase custou o iPhone do dono.** Este projeto já
migrou para o ciclo de vida `UIScene` — `ios/Runner/SceneDelegate.swift` existe,
`AppDelegate` é `FlutterAppDelegate` + `FlutterImplicitEngineDelegate`. Nesse
arranjo o delegate do centro de notificações fica nulo e **`onMessage` nunca
dispara no iOS**. O README do `firebase_messaging` 16.6.0 traz um exemplo
dedicado a apps com UIScene: chamar
`[FLTFirebaseMessagingPlugin configureNotificationCenterDelegate]` dentro de
`didFinishLaunchingWithOptions`. Ou seja, a decisão "sem dependência nova" custa
**Swift nativo no `AppDelegate.swift`** — e sem essa linha o recurso sobe verde
em teste de Android e mudo no iPhone.

Não está verificado se o mesmo delegate nulo derruba também
`getInitialMessage`/`onMessageOpenedApp` no iOS. Por isso o critério de aceite
exige os **três** estados (aberto, background, morto) testados em iPhone real,
antes de qualquer evento ser dado como pronto.

### 4. O marcador é a trava — e onde a analogia com `nicknames` para

A entrega de gatilho é **ao-menos-uma-vez e sem ordem garantida**. Sem trava,
uma reentrega repete o push, e push não tem como ser desenviado.

A trava é um documento cujo **id é o fato**: `create()` falha se ele já existe,
sem leitura, sem transação, sem contador para conciliar. É a técnica de
`nicknames/{apelido}`.

**Onde a analogia para, e a spec precisa dizer:** em `nicknames`, o documento *é*
o fato reivindicado, e a colisão aparece na cara de quem tenta. Aqui ele é uma
*afirmação derivada* sobre estado que mora noutro lugar, e a colisão é invisível
para os dois lados — o destinatário nunca soube que havia algo para receber. É
por isso que a coleção de marcadores é `read, write: if false` para todo mundo,
como `norouterule`: se um cliente pudesse criar marcador, pré-criar o do vizinho
o emudeceria pelo dia inteiro, sem rastro. É a **segunda** coleção de
infraestrutura do projeto, e a segunda em que o cliente não tem nada a fazer.

Duas decisões dentro disso:

- **`create()` antes do `send()`.** Se a trava passa e o envio falha, perde-se um
  push. Na ordem inversa, uma falha ao gravar a trava faz a função repetir e
  **reenviar**. Perder um aviso incomoda menos do que receber o mesmo três vezes.
- **`{uid}_{data}`, nunca `{data}_{uid}`.** Data no prefixo joga todas as
  escritas do dia numa faixa contígua de chaves, que é o anti-padrão de hotspot
  documentado pelo Google. Neste app a escala não chega perto do limite; a ordem
  correta custa zero e sobrevive ao dia em que chegar.
- **O dia é o de Fortaleza, nunca `toISOString()`.** O relógio da função é UTC,
  Fortaleza é UTC−3, e o "dia" do teto viraria às 21h locais. Num projeto que já
  trata fronteira de tempo local como assunto sério — `RouteTime.resolveEnd`, a
  aritmética de semana pelo construtor de `DateTime` — deixar essa passar seria
  incoerência.

## Gatilho por gatilho

### Evento 1 — Convite enviado

`onDocumentCreated('friendRequests/{userId}/incoming/{otherId}')` → notifica
`userId` que `otherId` o convidou.

O mais simples dos cinco, e não por acaso: **o caminho já carrega os dois lados**
(é a técnica que `friendController.dart` documenta — "corpo é dado, caminho é
fato"), e a regra de `incoming` já garantiu tudo o que importa antes de o
documento existir: que quem convida é quem diz ser, que os dois perfis existem,
e que **não há bloqueio entre eles**. A função não reconfere nada disso.

Fura uma vez só: o convite escreve `incoming` e `outgoing` no mesmo batch, mas o
gatilho está pendurado só no `incoming`.

**Dívida que este evento agrava, e não resolve:** quem é recusado pode reconvidar
sem limite. Hoje isso acende um badge; a partir daqui, toca o celular. As regras
não têm limite de taxa e o remédio continua sendo o bloqueio, que a tela já
oferece. Registrado aqui porque o incômodo muda de categoria.

### Evento 2 — Convite aceito: o gatilho não é a amizade, é o marcador que morre

O caminho óbvio não funciona, e vale escrever por quê. `FriendController.accept`
grava as **duas** arestas no mesmo batch (`friendController.dart:88-97`), com o
corpo idêntico — só `{at}`, e o `serverTimestamp` resolve para o mesmo valor nos
dois. Um gatilho em `friends/{userId}/list/{friendId}` dispara **duas vezes** e
nenhuma das duas diz quem aceitou. Os quatro marcadores de convite, que diriam,
são apagados no mesmo commit.

**O gatilho é o apagar do marcador:**

```
onDocumentDeleted('friendRequests/{userId}/outgoing/{otherId}')
  → só notifica se friends/{userId}/list/{otherId} existir depois do commit
  → o texto é "{otherId} aceitou seu convite", e o destinatário é userId
```

O caminho do documento apagado nomeia os dois lados — `userId` convidou,
`otherId` aceitou — e num aceite normal existe exatamente **um** `outgoing`, então
dispara uma vez só. A leitura da aresta é o que separa aceite de recusa, de
retirada e de bloqueio: no aceite ela está lá (o batch é atômico); na recusa
nunca existiu; no bloqueio e no desfazer, `severTies` apagou aresta e marcador no
mesmo commit. Uma leitura por evento.

Isso não muda regra nenhuma, não muda o cliente e não quebra quem já tem o app
instalado.

Duas alternativas foram consideradas e perderam, e ficam registradas para
ninguém as redescobrir:

- **Campo `by` na aresta** (uid de quem aceitou), com a regra passando a
  `hasOnly(['at','by'])`. Perde por três motivos: `hasOnly` é teto e não piso,
  então a aresta só com `{at}` continua passando e a função precisaria de um ramo
  silencioso para ela; `_stamp()` é o mesmo helper de `invite()` e de `accept()`,
  então mexer nele respinga onde não devia; e gasta uma mudança na regra mais
  crítica do app para resolver 1 dos 5 eventos.
- **`onDocumentCreatedWithAuthContext` e o `event.authId`**, que entregaria o uid
  de quem escreveu de graça. É a solução mais limpa das três **se funcionar**: o
  campo é opcional no evento, o comportamento não está documentado e há relato de
  divergência no emulador local (que é justamente onde a disciplina de teste
  deste projeto mora). Vale um **spike de 30 minutos**: publicar a função, aceitar
  um convite pelo app real, ler o log. Se vier o uid, o evento 2 encolhe para
  três linhas. Se não vier, o gatilho no marcador já é a resposta.

**Aresta conhecida:** no convite mútuo — os dois se convidaram antes de qualquer
aceite — existem dois `outgoing`, os dois são apagados, e os **dois** recebem
"fulano aceitou seu convite". As duas frases são verdadeiras; quem aceitou
recebe uma notificação sobre algo que acabou de fazer. Aceito.

### Evento 3 — Um amigo te passou no ranking

O mais caro dos cinco, e o único que pode ficar de fora sem quebrar a coerência
dos outros quatro.

**O problema:** não existe nenhuma escrita no Firestore que signifique "A
ultrapassou B". A classificação é calculada **no cliente**
(`rankingTab.dart` busca os baldes, `Utils/ranking.dart` ordena). Um detector no
servidor precisa derivá-la — e derivar é reimplementar, que é precisamente a
armadilha que o `CLAUDE.md` documenta em `VehicleController.activeFrom()` e em
`RouteOrder.pertoDeHoje`: duas implementações da mesma ordenação, e a que ficar
para trás faz o push discordar da tela.

**O que salva o desenho:** ultrapassagem é **paridade**, não classificação.
`_compare` não olha nenhum terceiro participante — não há percentil, nem
normalização, nem média do grupo. A função precisa duplicar o comparador de dois
e o predicado `ranked`, **não** o `rankBy` inteiro. E detectar troca de par é
melhor do que detectar mudança de posição: aceitar ou remover um amigo muda a
posição de todo mundo sem ninguém ter ultrapassado ninguém.

**O contrato entre o Dart e o JS são sete inteiros**, os que `MonthStats.toMap()`
grava:

```
routes  packages  failures  packagedRoutes  pacedRoutes  pacedMinutes  pacedStops
```

`minutesPerStop` e `failureRate` são **derivados e nunca gravados** — a função
recalcula os dois. `packagedRoutes` ausente cai em `routes`, não em zero (é
documento velho, e cair em zero jogaria gente para o rodapé). **Renomear
qualquer um dos sete quebra a função em silêncio**, e por isso os sete ficam
registrados aqui como contrato público, `MonthStats.toMap()` ganha um comentário
apontando para `functions/`, e a suíte JS espelha os casos de
`test/unit/ranking_test.dart` com os mesmos números — o mesmo tratamento que o
regex de apelido tem hoje ("mude os dois juntos").

**A ordem dos portões, e o primeiro é o que torna o custo aceitável:**

```
onDocumentWritten('profiles/{uid}/stats/{bucket}')
  1. os sete campos mudaram?  não → sai
  2. bucket é o mês corrente? não → sai
  3. para cada amigo, com o balde DELE congelado nos dois lados:
       antes = compara(uid.before, amigo)
       agora = compara(uid.after,  amigo)
       se antes > 0 e agora < 0 → uid passou o amigo → avisa o amigo
```

O balde do amigo entra **igual nos dois lados**. É o que isola o movimento de
quem gravou: comparar o "antes" de X contra o "antes" do amigo contaria de novo
um movimento do amigo que já disparou o gatilho dele.

O guarda `antes > 0 && agora < 0` sai de graça com três propriedades: quem estava
no rodapé e continua no rodapé dá 0 dos dois lados e não notifica; **quem apenas
cruza a amostra mínima e entra na disputa não notifica ninguém** — entrar não é
ultrapassar, e é o caso mais comum no começo do mês; e quem entra e passa alguém
classificado notifica.

**Quem grava é quem causa.** Se eu edito uma rota minha e meus números pioram, um
amigo passa a estar na minha frente sem ter feito nada. Ninguém é notificado —
nem eu, nem ele. A leitura alternativa (qualquer inversão notifica quem ficou
atrás) produz frases falsas: a Ana receberia "você passou o Wesley" sem ter
tocado no app. Sob a leitura de evento, **toda notificação tem exatamente um
autor e o texto é verdadeiro sobre ele** — a mesma disciplina de `getWeather` e
de `fetchCareer`, onde "não sei" e "zero" são frases diferentes.

O custo dessa escolha é real e fica registrado para ninguém "consertar" depois:
**existe um estado em que um amigo está legitimamente na minha frente e eu nunca
fui avisado.** Aceito, porque push é feed de eventos e o estado mora na aba
Ranking.

**O teto:** no máximo um aviso por `(passado, passador, critério, mês, dia)`,
travado pelo marcador. Direcional, nunca por par — Ana passar Bia e Bia repassar
Ana são destinatários diferentes, e colapsar silenciaria um evento verdadeiro
para quem ainda não recebeu nada. O critério `rotas` é o que mais pinga: não tem
amostra mínima e anda de 1 em 1, então dois amigos empatados trocam de lugar a
cada rota gravada.

Três furos do teto, todos aceitos e escritos:

1. Não impede o **primeiro** aviso de uma ultrapassagem que se desfaz em um
   minuto (gravar e apagar a rota por engano). Só um *debounce* resolveria, e
   debounce quer Cloud Tasks — mais máquina do que esta etapa comporta.
2. Um dia é grosso: uma ultrapassagem legítima às 19h, depois de já ter havido
   uma ao meio-dia, é silenciada.
3. Uma escrita só pode passar quatro amigos em três critérios e mandar doze
   pushes. Precisa de um segundo limite **por escrita**: um push por amigo
   passado, citando o critério mais forte.

**Dois consertos que entram junto, porque são a causa do ruído:**

- **Tirar `updatedAt` das 13 escritas de `profiles/{uid}/stats/*`.** Hoje
  `ProfileController.publish` grava 14 documentos a cada abertura do app, e
  carimba `updatedAt` novo em todos — o que faz `before != after` mesmo quando
  nenhum número mudou. Uma escrita cujo conteúdo não muda é *no-op* e **não
  dispara gatilho**; o `updatedAt` é o que desliga essa otimização sozinho. E ele
  não tem leitor nenhum: a regra de `stats/{bucket}` não o exige (só prende o
  formato do id), `MonthStats.fromMap` não o lê, e `profileStats.dart:76` diz com
  todas as letras que ele não entra no modelo. Tirar dali — e **só dali**; a
  projeção `profiles/{uid}` continua precisando dele por `hasAll` — faz onze dos
  doze baldes voltarem a ser no-op na maioria das aberturas.
- **Republicar as estatísticas ao excluir uma rota.** Hoje
  `listIterScreen.dart:354` chama `RouteController.delete` e não republica balde
  nenhum — a mudança só chega ao Firestore na próxima abertura do app, horas
  depois da causa. É bug de uma linha que **já existe**, independente de
  notificação; sem consertar, a primeira notificação estranha do sistema vai ser
  debitada da Function.

### Eventos 4 e 5 — Marcos de curtida e de comentário

**A régua é derivada, não testada por igualdade.** `contagem == 1 || contagem %
10 == 0` está errado, e o modo de falha é o silêncio: com a contagem em 9, duas
curtidas simultâneas fazem as duas invocações lerem **11**, e ninguém é
notificado. Marcador impede repetir; nunca inventa o que faltou.

```
marcoDe(n) = o maior marco ≤ n     // curtidas: 1, 10, 20, 30…
                                   // comentários: 1, 5, 10, 15…
notifica se o marcador daquele marco ainda não existir
```

Com a derivação, os dois leem 11, os dois derivam 10, um só ganha o `create()`, e
sai uma notificação. A corrida vira o caso normal. E o sistema fica
**auto-curativo**: um marco perdido por falha da função é recuperado pela próxima
curtida — o que torna seguro não repetir a invocação, porque só a última curtida
da vida de um post perde o marco de vez.

Regra de parada: se o marcador do marco derivado já existe, **não desce** para o
marco anterior. Com 15 curtidas e o marcador de 10 posto, ninguém recebe
"primeira curtida" atrasada.

**A ordem das operações é a spec, não detalhe de implementação:**

```
count()  →  derivar o marco  →  marcador já existe? sai        (1 leitura)
         →  ler o post (dono, lápide, trecho do texto)
         →  o autor É o dono? sai SEM CRIAR o marcador
         →  post com lápide? sai
         →  create() do marcador
         →  enviar
```

Duas linhas dessa sequência são as que quebraram o primeiro desenho:

- **Pular-por-ser-o-dono não pode criar o marcador.** Todo mundo curte o próprio
  post; se essa saída marcasse, a primeira curtida de verdade nunca seria
  anunciada. Com a derivação e sem a marca, a segunda curtida (do outro) deriva
  o marco 1 e notifica.
- **Reler o post antes de enviar.** A regra impede curtir e comentar em lápide,
  mas nada impede o dono apagar o post **entre** o gatilho e o envio — e ele
  costuma apagar justamente quando o post está atraindo atenção que não queria.
  Receber "seu post chegou a 10 curtidas" depois de apagá-lo é da mesma família
  do "gesto que torna a ofensa permanente" que a lápide existe para evitar. A
  releitura é de graça: a função já precisa do dono e do trecho do texto.

**`count()` e não contador.** A posição do `CLAUDE.md` — *"recomputado, nunca
incrementado"* — vale aqui sem adaptação, e a deriva seria pior do que um número
feio na tela: um contador 2 acima do real dispara o marco de 10 com 8 curtidas, e
**o marcador congela essa mentira para sempre**. `count()` custa 1 leitura por
lote de mil entradas de índice, ou seja 1 leitura para qualquer post deste app.
Há um argumento legítimo do outro lado — um contador no corpo do post resolveria
de quebra a limitação que `postController.dart` documenta (a agregação não
funciona com listener nem offline, e o mural paga uma por post por página) —, e
ele fica **fora desta spec de propósito**: é otimização de leitura do feed, e
misturar as duas faz a feature de notificação passar a ser dona de um número que
o feed desenha.

**Ninguém é nomeado num marco.** Na décima curtida, nomear a última pessoa credita
a pessoa errada. E há uma razão mais forte, que decide também a **primeira**
curtida: **a regra de `likes` não chama `bloqueioEntre`** — quem foi bloqueado
ainda pode curtir. Nomear quem curtiu entregaria o nome do bloqueado na tela de
bloqueio da vítima, furando por push o bloqueio que a regra do comentário existe
para sustentar.

Com **comentário é diferente**, e a assimetria é deliberada: a regra de `comments`
*chama* `bloqueioEntre` nos dois sentidos, então quem comentou não é bloqueado de
ninguém. O primeiro comentário pode nomear quem comentou — mas **nunca reproduz o
texto do comentário**, que é conteúdo de terceiro na tela de bloqueio.

Os textos, e o verbo é load-bearing:

```
1ª curtida      «Primeira curtida»   / «Seu post recebeu a primeira curtida.»
marco curtidas  «10 curtidas»        / «Seu post chegou a 10 curtidas.»
1º comentário   «Cleyton»            / «comentou no seu post»
marco comentar  «5 comentários»      / «Seu post chegou a 5 comentários.»
```

**"chegou a"** continua verdadeiro com 11 e continua verdadeiro se caiu para 9;
"tem 10 curtidas" é falso nos dois casos — e a corrida garante que o número do
envio quase nunca é o número do marco. Ao corpo se anexa ~50 caracteres do texto
do **próprio post** (`… "Rodei 180 km hoje…"`), que a função já releu, para o dono
saber de qual post se fala.

Três coisas que ficam registradas porque vão virar bug reportado se não ficarem:

- **Curtir, descurtir, curtir de novo não renotifica.** A semântica do marcador é
  *"este post já passou por esta marca"*, nunca *"este post tem N curtidas
  agora"*. Sem isso, uma pessoa sozinha com a contagem em 10 toca o coração em
  looping e cada travessia manda um push — assédio de graça, com um dedo.
- **O preço disso:** A curte (push), A descurte, B curte — o dono não é avisado da
  curtida que ficou de pé, e não será até a décima. É o preço da regra anterior,
  aceito de propósito.
- **O número anunciado não é o número da tela.** O `count()` do servidor inclui
  os comentários de quem o dono bloqueou depois (a folha os esconde), e inclui os
  comentários do próprio dono. Não há conserto barato — a agregação não filtra, e
  enumerar os autores é ler a thread inteira a cada marco. O texto neutro
  sobrevive ao caso; a divergência fica escrita.

E o que **não** fazer, com todas as letras: **não guardar contagem nem marcas
dentro de `posts/{postId}`.** O documento de post é pequeno de propósito — o
próprio `post.dart` abre dizendo que "o feed é a única coisa do app que cresce
sem teto" — e o mural baixa 20 por página. Peso ali é peso em toda abertura de
feed, para servir uma função que roda uma vez a cada dez curtidas. Os marcadores
vão para `posts/{postId}/marcos/{id}`, que é subcoleção sem `match` e portanto
negada a todo cliente por omissão — mais o bloco explícito `read, write: if
false`, porque o Admin SDK ignora regras e é justamente por isso que a ausência
de regra passaria despercebida.

## O toque leva à tela certa

Três estados, três portas: `getInitialMessage()` (app estava morto — **consome** a
mensagem, chame uma vez só e antes de qualquer navegação), `onMessageOpenedApp`
(estava em background) e o `onTap` do toast (estava aberto).

O destino não pode ser navegado na hora: com o app morto, o toque chega **antes
de existir qualquer `Navigator`**, e a `HomeScreen` só monta depois de o
`authStateChanges` resolver. A intenção fica guardada num `ValueNotifier` do
serviço e é **consumida** quando a Home monta. Notificação que chega para uma
sessão deslogada não tem para onde ir e é descartada.

**A descoberta que decide o desenho:** `home.dart` guarda as telas em campos
`late final`, o que faz a instância da widget ser *idêntica* entre rebuilds — e o
Flutter, ao ver a mesma instância, devolve o elemento sem chamar `update()`. Logo
**`didUpdateWidget` nunca roda**, e um parâmetro que muda jamais chegaria na aba.
Tirar o `late final` não é só seguro (mesmo tipo, mesma posição, sem key: o
`State` é preservado): é **obrigatório** para o deep link passar parâmetro por
construtor.

Dois efeitos colaterais que vêm junto: a `FriendsScreen` passa a reconstruir a
cada rebuild da Home — que acontece a cada snapshot de `user/{uid}` e da caixa de
convites —, e ela chama `_prefetch` dentro do `build`. Por isso a intenção precisa
ser **consumível uma vez** (um objeto com identidade, descartado ao ser lido);
um parâmetro grudento reforçaria a aba a cada rebuild e congelaria a escolha
manual do usuário.

O que precisa nascer:

- `HomeScreen`: um caminho para receber a intenção de fora e trocar `_currentIndex`.
- `FriendsScreen`: `initialTab` (ou o objeto de intenção), e **encaminhar** o
  critério para a `RankingTab`.
- `RankingTab`: `initialCriterion`. Atenção ao `_current`, que é `late final`
  derivado de `_month` e trava a navegação para a frente — se um dia entrar
  `initialMonth`, `_current` tem de continuar sendo o mês corrente de verdade,
  senão o botão de avançar morre.
- `PostController.fetch(String id)` — **não existe**, e é o que falta para os
  eventos 4 e 5 terem destino. Devolve `Post?`, com `null` para inexistente **e
  para lápide**: hoje quem filtra o tombstone é o `parse()` de lista, e uma
  thread aberta por link pularia esse filtro. Disciplina do `getWeather`: `null`
  é "não deu para saber".
- Para abrir a thread, `showCommentsSheet` já recebe um `Post` pronto; `profiles`
  pode entrar vazio (a folha busca o que falta) e `onCount` pode ser no-op. **Não
  forje um `Post` mínimo**: a folha usa `post.uid` para decidir quem vê o botão de
  apagar, e um uid chutado desenha o botão para quem a regra vai negar.

## Regras do Firestore que mudam

Três blocos novos, nenhuma regra existente alterada:

```
match /fcmTokens/{tokenId} {
  allow get, list: if false;               // ninguém lê token, nem o dono
  allow create, update: if request.auth != null
                        && tokenId.matches('^[0-9a-f]{64}$')
                        && request.resource.data.keys().hasOnly(
                             ['token','uid','platform','updatedAt'])
                        && request.resource.data.uid == request.auth.uid
                        && request.resource.data.platform in ['android','ios']
                        && request.resource.data.token is string
                        && request.resource.data.token.size() <= 4096
                        && request.resource.data.updatedAt == request.time
                        && tokenId == hashing.sha256(request.resource.data.token)
                                        .toHexString().lower();
  allow delete: if request.auth != null
                && resource.data.uid == request.auth.uid;
}

match /posts/{postId}/marcos/{marcoId}   { allow read, write: if false; }
match /avisosRanking/{avisoId}           { allow read, write: if false; }
```

O wildcard preso por `matches` não é capricho: `profiles/{uid}/stats/{bucket}`
já prende o dele com o comentário "sem ele, a subcoleção é depósito livre na cota
do projeto", e o projeto está no Blaze. `updatedAt == request.time` também não é:
é o **único** campo que a varredura de token velho vai ler, e deixar o cliente
escolher o que é "fresco" é deixá-lo escolher se expira.

**A regra confere que o id é o hash do token** — `hashing.sha256(...)
.toHexString().lower()`. Sem essa linha, "a colisão some por forma" seria promessa
do app e não invariante: bastaria um cliente gravar o mesmo token sob dois ids
para dois donos receberem no mesmo aparelho, que é o caso inteiro que a chave
invertida existe para fechar. O `.lower()` não é detalhe — o Firestore devolve o
hexa em maiúsculo e o `crypto` do Dart gera minúsculo; sem ele **toda** gravação
seria negada, em silêncio.

O que a regra **não** consegue garantir, e fica escrito: ela não amarra um token a
um aparelho. Quem soubesse o token do celular de outra pessoa poderia reivindicá-lo
e desviar as próprias notificações para lá. Tokens não são públicos e não há
caminho no app que os exponha; sem servidor de atestação não há defesa melhor.

## Tech stack

- **App:** `firebase_messaging` (16.6.0 hoje; exige `firebase_core ^4.14.0`, e o
  projeto está resolvido em 4.13.0 — cabe no `^4.12.1` do pubspec, mas o
  `pub upgrade` mexe em **todos** os plugins Firebase de uma vez, então vem com
  teste de fumaça de login, feed e foto no aparelho).
- **Servidor:** `functions/`, Node 22, ESM, **JavaScript puro** — sem passo de
  build. É o que `firestore-tests/rules.test.mjs` já faz, é o único precedente
  Node do repositório, e TypeScript aqui custaria um `tsc` para um dono que
  trabalha em Dart. Se a pasta passar de uns poucos arquivos, TS é o upgrade.
- `firebase-admin` com **versão fixada** — o formato do erro de `create()` em
  documento existente depende dela, e é sobre esse erro que toda a dedupe se
  apoia.
- Região **`southamerica-east1`**, a mesma do Firestore.

## Commands

```bash
flutter pub add firebase_messaging
flutter pub get
flutter analyze
flutter test

cd functions && npm install
npm test                                   # node --test, módulos puros, sem emulador

cd firestore-tests && npm test             # as regras, contra o emulador (Java 21+)

firebase deploy --only functions --project iter-mn
firebase deploy --only firestore:rules --project iter-mn
```

**`--project iter-mn` sempre.** Não existe `.firebaserc` na raiz e o
`firebase.json` não tem bloco de projeto; sem a flag, o destino é o que o
`firebase use` global apontar por último — e o sintoma é a regra continuar negada
em `iter-mn`, indistinguível de regra não escrita. É a mesma armadilha que
`sem-rota.md` já registrou.

O `firebase.json` ganha um bloco `functions` apontando para a pasta.

## Estrutura

```
functions/
  package.json          "type":"module", engines.node 22, firebase-admin fixado
  index.js              só registra os cinco gatilhos e a região
  push.js               tokens do destinatário, envio, limpeza de token morto
  texto.js              as frases e o payload de destino, num lugar só
  marcos.js             marcoDe(n) — função pura
  rank.js               o comparador e o predicado ranked — espelho de Utils/ranking.dart
  test/
    marcos.test.mjs
    rank.test.mjs
    texto.test.mjs

lib/
  services/pushMessaging.dart      registro do token, permissão, os três ganchos
  Utils/pushTarget.dart            NotificationTarget.fromData(Map<String, dynamic>)
test/unit/pushTarget_test.dart
```

**Nome:** `lib/widget/notificationPush.dart` **não** é push — é o toast interno
`showNotification`, usado em meia dúzia de telas. Por isso o serviço novo se
chama `pushMessaging.dart`: quem abrir o arquivo errado perde meia hora.

## Estilo de código

O JS segue o Dart do projeto no que importa — decisão comentada onde ela é
contraintuitiva, nome em português quando o domínio é português:

```js
/// O maior marco ≤ n, ou null se n ainda não alcançou nenhum.
///
/// Derivar e não testar igualdade (`n % 10 === 0`) é o que sobrevive à corrida:
/// com a contagem em 9, duas curtidas simultâneas podem fazer as duas invocações
/// lerem 11, e o teste de igualdade não notifica ninguém. Marcador impede
/// repetir; nunca inventa o que faltou.
export function marcoDe(n, passo) {
  if (n < 1) return null;
  return n < passo ? 1 : Math.floor(n / passo) * passo;
}
```

## App Check: 90% console, 10% Dart

O SDK é a parte barata, e escrever o Dart primeiro faz depurar a coisa errada.

### O que já está no app (28/08/2026)

`firebase_app_check: ^0.4.7` e `lib/services/appCheck.dart`, ligado no `main()`
com `await` e **try/catch próprio** — uma exceção ali roda antes do `runApp` e
não daria erro na tela, daria **tela preta**. `firebase_core` subiu de `^4.12.1`
para `^4.14.0`, porque o piso declarado mentia desde que o messaging entrou.

Três armadilhas de API, todas verificadas no código do pacote:

**`providerAndroid`/`providerApple`, não `androidProvider`/`appleProvider`.** Os
dois antigos estão `@Deprecated`, e toda a documentação e todo tutorial ainda
mostram a forma velha. **Passar um antigo junto com um novo instala em silêncio o
provedor de depuração** — que, num release com o token registrado no console,
contorna o App Check inteiro, que é a única coisa que ele existe para impedir.

**`!kReleaseMode`, e não `kDebugMode`.** `kDebugMode` é **falso em profile**,
então `flutter run --profile` cairia no Play Integrity e falharia a atestação sem
sintoma. Perfil e depuração são os dois modos na mão do desenvolvedor.

**A defesa não é o Gradle.** `firebase-appcheck-debug:19.4.1` está no APK de
release de qualquer jeito — verificado na árvore de dependências, junto com
`com.google.android.play:integrity:1.4.0`. O que impede o app de usar o provedor
de depuração é aquela linha em Dart, e só ela.

### A descoberta que muda o plano

**Na configuração padrão, o App Check negaria este app.** O Play Integrity
funciona fora da Play — a doc de 25/08/2026 é explícita —, mas por padrão o App
Check exige o selo `PLAY_RECOGNIZED`, que só apps distribuídos pela Play recebem.
Ligar a imposição sem mexer nisso derruba os dois celulares.

O SDK já resolve o lado do código sozinho: o provedor manda o número do projeto
via `setCloudProjectNumber()`, lido do `google-services.json`. **Não há uma linha
de Dart a escrever para o caso "fora da loja"** — é tudo console.

E o SafetyNet, que seria o plano B, **morreu em 31/01/2025**. O parâmetro ainda
existe no plugin por compatibilidade e não atesta mais nada.

### Os passos de console, na ordem

1. **Cloud Console → APIs e serviços → Ativar → "Play Integrity API"** no projeto
   `iter-mn`. Não exige conta do Play Console; o vínculo com o Play só serve para
   cota maior e configuração avançada, e a cota padrão sobra para dois aparelhos.
2. **Firebase → App Check → Apps → registrar o app Android com Play Integrity**,
   informando o **SHA-256** do certificado. Hoje só o **SHA-1** está registrado no
   projeto (é o que o Google Sign-In usa); o SHA-256 é entrada separada. Como o
   `release` assina com a chave de debug, é o SHA-256 **dela**:
   `keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android`
3. **Configurações avançadas do app, e é o passo que quase ninguém faz.**
   Ficam em **App Check → aba Apps → menu `⋮` do app registrado**, e não nas
   configurações do projeto. A linha da tabela oficial para "distribuído
   exclusivamente fora da Google Play" é: `PLAY_RECOGNIZED` → **não exigido**;
   `LICENSED` → **não exigido**; nível de integridade → **não verificar
   explicitamente**. Sem isto, nada do resto vale.

   Na dúvida entre dois valores de integridade, escolha o **mais permissivo**:
   apertar depois, com a métrica verde, é seguro; afrouxar depois de já ter
   imposto é o que deixa os aparelhos de fora.

   **Onde elas ficam, exatamente:** clicando no **nome do provedor**
   ("Play Integrity") na aba Apps — que abre o formulário de edição com o
   SHA-256, a vida útil do token e o bloco "Configurações avançadas". **Não** no
   menu `⋮` do app, que só oferece "Ocultar detalhes" e "Gerenciar tokens de
   depuração", e **não** exige vincular conta do Play Console. Uma versão
   anterior desta seção registrou como provável que o vínculo fosse necessário;
   era suposição minha e estava errada.

   Os três campos e os valores para este app:
   - `PLAY_RECOGNIZED` — vem **marcado por padrão** e é o que precisa mudar.
     Desmarque: o selo só é concedido a apps instalados a partir da Play.
   - `LICENSED` — já vem desmarcado. Deixe.
   - nível de integridade — já vem em "não verificar explicitamente". Deixe.

4. **Instalar o APK novo nos dois aparelhos** e usar o app normalmente.
5. **Só então** olhar App Check → APIs, e esperar a métrica mostrar requisições
   **verificadas**. Alguns dias, não algumas horas.
6. **Impor, um produto por vez: Cloud Firestore primeiro, Cloud Storage depois.**
   A imposição leva até 15 minutos para valer e o token tem TTL de 1 hora.

**Nunca impor Authentication.** O risco é assimétrico: se a atestação falhar por
qualquer motivo — Play Integrity fora do ar, cota, aparelho novo, chave de
assinatura trocada — a imposição de Auth **tranca o dono para fora da própria
conta**, num app instalado por APK, sem canal de suporte. E ela não protege nada
que Firestore e Storage já não protejam: as coleções abertas são todas Firestore.

### Os modos de falha, do mais silencioso ao mais barulhento

**`activate()` não dá sinal nenhum de sucesso.** Ele instala a fábrica e devolve;
a atestação só acontece na primeira requisição, preguiçosamente. "O app subiu e
não deu erro" não é evidência de nada — dá para passar meses achando que está
pronto para impor. É por isso que o serviço tem a `_sonda()`, que em debug chama
`getToken()` e diz no log se a atestação funcionou de verdade.

**`fcmTokens` negado mata o push em silêncio, e o log mente.** A gravação do
token é silenciosa por desenho (try/catch próprio), então o app sobe perfeito e
nenhum aparelho recebe nada — com `aparelhos: 0` no Cloud Logging, **a assinatura
idêntica ao incidente de 26/08**, cuja causa era outra (regra não publicada). Se
esse sintoma voltar depois da imposição, olhe App Check antes de olhar regra.

**O cache local do Firestore mascara metade.** O app abre, mostra os dados de
ontem, e o dono só descobre quando tenta escrever.

**Salvar rota é o único barulhento, e a mensagem mente:** "Não foi possível salvar
a rota. Tente novamente." Sob imposição, tentar de novo devolve o mesmo, para
sempre.

**Em debug, o erro aponta para o lugar errado.** Sem o token de depuração
registrado, a negativa chega como erro de permissão do Firestore — e a próxima
pessoa passa meia hora em `firestore.rules`. O token aparece no logcat na
primeira execução; registre em App Check → Apps → gerenciar tokens de depuração.
A partir de 0.4.6 dá para fixá-lo por código com
`AndroidDebugProvider(debugToken: '...')`, o que evita reinstalar e ganhar um
segredo novo.

### O que não muda

**Zero alteração em `functions/`.** App Check só se impõe em função *callable*, e
a decisão de "nenhum callable, todo push nasce de gatilho" — tomada por outro
motivo — pagou dividendo aqui.

## Os passos de plataforma, que nenhum teste acusa

Tudo aqui é configuração fora do Dart. Um app com o código inteiro certo e um
destes faltando **não notifica**, e o `flutter test`, o `npm test` e o
`flutter analyze` ficam todos verdes.

### Android

**O ícone da bandeja.** Não existe drawable de silhueta em
`android/app/src/main/res/` — só os `mipmap/ic_launcher`, que são **100%
opacos**. O FCM cai no ícone do launcher e o sistema descarta as cores, usando só
o canal alpha: o recorte vira o retângulo inteiro, ou seja, **um quadrado branco**
na bandeja e na tela de bloqueio, em todo Android 5+. Precisa de um
`drawable/ic_stat_iter.xml`, vetor 24dp, silhueta branca sobre transparente, mais
o `meta-data com.google.firebase.messaging.default_notification_icon`. Com
`minSdk 24`, um vetor basta — não são cinco PNGs. O `flutter_launcher_icons` não
gera esse recurso.

**O canal, e ele é irreversível.** O `meta-data default_notification_channel_id`
**sozinho é inerte**: ele aponta para um canal, não cria nenhum. Sem o canal
existir, o SDK cria o `fcm_fallback_notification_channel` com
`IMPORTANCE_DEFAULT`, que **só toca som** — não abre banner nem acende a tela, que
é o critério de aceite nº 1 falhando com o código certo. E ele aparece nos
Ajustes do aparelho como *"Miscellaneous"*, em inglês, num app inteiro em
português. O canal se cria em Kotlin, no `MainActivity.kt` (hoje um
`FlutterActivity()` sem corpo), com `IMPORTANCE_HIGH`.

Fixar id e importância **antes do primeiro install que receba push**: o app não
pode alterar a importância de um canal já criado — só o usuário, na mão —, e o
`fcm_fallback_notification_channel`, uma vez criado no aparelho, fica na tela de
Ajustes para sempre. É a única decisão desta feature que deploy nenhum desfaz.

**A cor** vai por `android:resource` apontando um `@color`, nunca
`android:value="#RRGGBB"`: escrito como valor, o `Bundle.getInt` devolve 0 e o
meta-data é ignorado **em silêncio** — parece configurado e não está. Precisa de
um `values/colors.xml`, que também não existe.

**`POST_NOTIFICATIONS` já vem da mesclagem** do próprio SDK; declarar de novo é
inócuo. O passo que falta não é declarar, é **conferir** — no manifesto mesclado
ou, à prova de bala, no APK:
`aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk`. E
`FirebaseMessaging.requestPermission()` cobre o Android 13+ sozinho: não entra
`permission_handler`.

**Nunca mandar o ícone pelo payload** da Function. Ele vem do meta-data do
manifesto; no payload, um nome de recurso errado é notificação sem ícone.

Duas coisas para o roteiro de teste: emulador **com Google Play** (uma imagem AOSP
não tem Play Services e `getToken()` nunca resolve), e o passo do fabricante nos
aparelhos brasileiros — Xiaomi, Samsung e Motorola tratam o "limpar tudo" como
parada forçada, e o "início automático" precisa estar ligado.

### iOS

**A capability de Push é obrigatória; Background Modes não** — o desenho é
`notification` + `data`, sem handler de background.

**`CODE_SIGN_ENTITLEMENTS` tem de entrar nas TRÊS configurações** do target
Runner: Debug, Release e **Profile**. A terceira é do Flutter, projetos iOS
normais não a têm, e é a que ninguém revisa.
`grep -c CODE_SIGN_ENTITLEMENTS ios/Runner.xcodeproj/project.pbxproj` precisa
devolver **3** (hoje devolve 0). Faltando na Profile, o build de profile sai sem
`aps-environment`, o iOS recusa o registro, e o sintoma parece intermitente
porque só aparece num dos três builds.

**A chamada nativa do UIScene, com dois cuidados.** O símbolo não existe em Swift
sem `import firebase_messaging` no topo do `AppDelegate.swift` — o exemplo do
README traz o import só na versão Objective-C. E a linha entra **dentro** do
`application(_:didFinishLaunchingWithOptions:)` que já existe, antes do
`return super`: copiar o método do README por cima apaga o
`FlutterImplicitEngineDelegate` e o `didInitializeImplicitFlutterEngine`, e aí
**nenhum plugin registra** — o app morre em `MissingPluginException` no primeiro
`Firebase.initializeApp()`, e parece regressão do Firebase quando é o AppDelegate.

**Esperar o token do APNs antes de pedir o do FCM.** A ordem é
`requestPermission()` → `getAPNSToken()` com retry curto → `getToken()`. Sem a
espera, a primeira abertura num iPhone novo estoura
`apns-token-not-set`, nenhum documento é gravado, e só passa a funcionar depois
de fechar e reabrir o app — o pior modo de falha possível para o critério nº 1.

**Não mexer no `FirebaseAppDelegateProxyEnabled`.** Ausente (= YES) é o caminho
suportado. Posto como `NO` para "endurecer", o token do APNs nunca chega ao
Messaging e `getToken()` falha para sempre, sem erro no log. Vale um comentário
no `AppDelegate` para ninguém tentar.

**A chave APNs `.p8`** (uma só, com o serviço APNs marcado) sobe no console com
**Key ID e Team ID**; ela serve development e production, ao contrário de
certificado. E em `push.js`, `messaging/third-party-auth-error` **não é** token
morto: é credencial errada no console. Confundir os dois faz a limpeza apagar
todos os tokens de iPhone a cada envio, o app regravá-los na abertura seguinte, e
o `fcmTokens` piscar para sempre — com o diagnóstico apontando para o cliente.

O `Podfile` diz `platform :ios, '15.0'` e o `pbxproj` dizia 13.0 nas três
configurações. Alinhado em 25/08/2026.

**O contorno do CDN do CocoaPods, porque vai acontecer de novo.** Ao atualizar os
pods do Firebase, o `pod install` para com
`CDN: trunk URL couldn't be downloaded: https://cdn.jsdelivr.net/... Response:
Error in the HTTP2 framing layer` — sempre no mesmo arquivo, sem ser aleatório. O
mesmo URL responde **HTTP 200 em 70 ms** no `curl`: o defeito é do cliente HTTP/2
do CocoaPods, não da rede nem do projeto. Repetir não resolve.

O que resolve é semear o cache dele à mão. O CDN espelha em
`~/.cocoapods/repos/trunk/`, com o mesmo caminho depois de `cocoa/`:

```bash
url=https://cdn.jsdelivr.net/cocoa/Specs/0/9/f/FirebaseFirestore/12.18.0/FirebaseFirestore.podspec.json
destino="$HOME/.cocoapods/repos/trunk/${url#https://cdn.jsdelivr.net/cocoa/}"
mkdir -p "$(dirname "$destino")" && curl -sfS "$url" -o "$destino"
```

Repetir para cada arquivo que ele reclamar — foram seis nesta atualização
(Firestore, Core, CoreExtension, FirestoreInternal, SharedSwift, Messaging), um
por rodada de `pod update Firebase`, até `Pod installation complete`.

**E o atalho que reordena a etapa A:** dá para provar a fiação inteira do toque —
os três estados, o deep link, o `configureNotificationCenterDelegate` — **antes de
existir qualquer Cloud Function**, com `xcrun simctl push` no simulador. Com uma
condição: o JSON de teste precisa carregar `gcm.message_id` na raiz, ao lado do
`aps`. O plugin filtra por essa chave e **ignora em silêncio** o que não a tem —
sem ela o banner aparece, nada dispara, e perde-se o dia mexendo num AppDelegate
que já estava certo.

### A fiação no Dart

**`getInitialMessage()` em `main()`**, depois do `Firebase.initializeApp` e antes
do `runApp`, sem `await` bloqueando o primeiro frame. Não na `HomeScreen`, que é
o exemplo da documentação: com o app aberto **deslogado** por um toque, a
mensagem fica viva e não consumida no processo, e a Home de **outra pessoa** que
entrar depois a consome — o deep link do celular emprestado, exatamente o bug que
`fcmTokens/{sha256}` existe para fechar.

Quem descarta a intenção de uma sessão deslogada é a `LoginScreen.initState`, não
o `build` do `AuthGate` — aquele `build` é puro, e mutar o notifier de lá é
escrita durante build.

**O `updatedAt` de `fcmTokens` é `FieldValue.serverTimestamp()`, e foge do padrão
da casa de propósito.** Todo `updatedAt` deste app é string ISO; só `at` e
`createdAt` usam carimbo do servidor. A regra nova compara
`updatedAt == request.time`, que só casa com o carimbo — escrito como ISO, toda
gravação volta `permission-denied`, e como o registro é silencioso por desenho, o
app sobe verde e nenhum aparelho recebe nada. Vai comentado no serviço.

**O registro é um segundo future independente** no `initState`, com try/catch
próprio, disparado ao lado de `_publishPublicProfile()` — nunca dentro dele, e
nada que a Home precise pode ficar atrás de `await requestPermission()`, que abre
diálogo de sistema.

**A assinatura do `onTokenRefresh` mora no serviço**, não na Home, que é
desmontada e remontada; o handler lê o `currentUser` na hora de gravar. E o
serviço guarda em memória o último `docId` gravado — é o que permite
`PushMessagingService.unregister()` ser a primeira linha do
`GoogleSignInService.signOut()`, sem mudar assinatura nenhuma e sem tocar em
`home.dart`. O uid sozinho não serve: o id do documento é o `sha256` do token, e
buscá-lo no meio do logout seria rede na hora errada. O delete tem try/catch e
timeout próprios — falhar não pode impedir a saída da conta.

**Dos seis campos `late final` da `HomeScreen`, sai o de `_friends` e só ele.**
`_incoming` e `_profile` **têm** de continuar: sem o `late final`, dois listeners
do Firestore se reinscrevem a cada rebuild da Home, em laço. `_grafics`,
`_listIter` e `_summary` devem continuar, porque o `late final` é o que ativa o
curto-circuito de identidade do Flutter e evita reconstruí-las à toa.

**A intenção é aplicada em `initState` E em `didUpdateWidget`.** Os dois, e é o
ponto que o argumento do `late final` cobria pela metade: trocar de aba desmonta a
`FriendsScreen`, então o caminho mais comum (o usuário está em Gráficos e o toque
leva para Amigos) passa por `initState`; só o `didUpdateWidget` faria o deep link
funcionar exclusivamente para quem já estava em Amigos, e só o `initState` faria o
inverso.

**A intenção é um objeto com identidade, comparada com `identical`**, e a classe
não pode ganhar `==`/`hashCode` de valor: dois convites seguidos geram alvos de
conteúdo idêntico, e com igualdade de valor o segundo push não move nada. Quem a
consome a zera (`take()`), e é isso que impede o parâmetro grudento — sem a
limpeza, **toda** visita futura à aba Amigos reaplica o deep link antigo.

`NotificationTarget.fromData` recebe `Map<String, dynamic>`, que é o tipo real de
`RemoteMessage.data`. E `lib/Utils/pushTarget.dart` não importa
`firebase_messaging`: é função pura sobre um mapa, testável sem Firebase, como o
resto de `Utils/`.

**A mensagem carrega `para: '<uid>'`** e o cliente descarta o que não for da
sessão atual. Custa zero na Function, que já sabe para quem está mandando, e é a
segunda trava do celular emprestado.

## Estratégia de teste

Três camadas, e a primeira é a que paga:

1. **`node --test` em `functions/test/`, sem emulador.** `marcoDe`, o comparador
   de ranking e as frases são funções puras de dados — o equivalente Node do que
   `vehicleCost.dart` e `fuelEconomy.dart` são no Dart. `rank.test.mjs` espelha
   os casos de `test/unit/ranking_test.dart` **com os mesmos números**; é a única
   defesa contra a duplicação divergir em silêncio. `marcos.test.mjs` fixa:
   1→1, 2→1 (a auto-curtida do dono), 9→1, 10→10, **11→10** (a corrida), 25→20,
   0→nenhum; e 1, 5, 10, 15 para comentário.
2. **`firestore-tests/rules.test.mjs`** ganha os casos dos três blocos novos,
   incluindo os negativos que são o ponto deles: outro usuário **não** grava meu
   token; ninguém lê `fcmTokens`; cliente autenticado **não** lê nem escreve
   marcador.
3. **Aparelho, que é a única camada que responde à pergunta que importa.** Nenhum
   dos dois `npm test` alcança um gatilho, e não há emulador de FCM. Para cada
   evento, nos **três** estados (aberto, background, morto), em **Android e
   iPhone**, e nos dois builds. O iOS é obrigatório e não negociável por causa do
   `UIScene`: um recurso pode passar verde em tudo e ficar mudo no iPhone.

   Com uma antecipação que vale a etapa inteira: **a fiação do toque se prova
   antes de existir servidor**, com `xcrun simctl push` e um JSON que carregue
   `gcm.message_id` na raiz. É a tarefa A6, e é o que impede depurar cliente e
   servidor ao mesmo tempo sem saber de que lado está o defeito.

O `test/widget_test.dart` continua quebrado pelo mesmo motivo de sempre, e não é
regressão desta entrega.

## Custo

O que muda de categoria: **até hoje, escrita alheia custava quota; a partir daqui
custa dinheiro.**

- Cada curtida de qualquer pessoa em qualquer post = 1 invocação + 1 leitura de
  agregação. As nove curtidas que não notificam pagam isso.
- O marcador limita os **pushes**, nunca as **invocações**. Curtir e descurtir em
  looping é uma conta do Blaze paga pelo dono, e o remédio é App Check, não
  marcador.
- O gatilho do ranking, sem o conserto do `updatedAt`, custa 13 invocações por
  abertura de app por usuário — todas por mudança nenhuma. Com ele, quase zero.
- FCM não é cobrado. As leituras e as invocações são.

## Fronteiras

**Sempre:**
- `notification` + `data` na mesma mensagem, todo valor do `data` em string.
- Nome e foto vêm de `profiles/{uid}`, nunca denormalizados no documento do evento.
- Marcador criado **antes** do envio.
- Estado de controle em coleção separada — nunca no documento que dispara.
- `--project iter-mn` em todo deploy, e `npm test` das regras antes.

**Perguntar antes:**
- Mudar a régua dos marcos (1/10 e 1/5) ou o teto diário do ranking.
- Acrescentar dependência ao app.
- Notificar um evento novo.
- Mudar a região das funções.

**Nunca:**
- Função *callable* de envio, ou qualquer caminho em que o cliente escolha
  destinatário ou texto.
- Texto de terceiro no corpo da notificação — comentário, post alheio, mensagem.
- Dinheiro, CPF, endereço ou qualquer campo de `user/{uid}` numa notificação.
- Nomear quem curtiu: a regra de `likes` não checa bloqueio.
- Notificar quem bloqueou ou foi bloqueado — o que sai de graça, porque
  `severTies` apaga a amizade no mesmo commit do bloqueio, e a função só lê
  `friends/{uid}/list`.
- Recalcular o passado: o ranking de um mês fechado não gera evento novo.

## Critérios de sucesso

1. Com o app deslizado das recentes, o convite do Cleyton acende o celular do
   Wesley em menos de 10 segundos, no Android **e** no iPhone.
2. O toque abre a aba Amigos com o convite visível — nos três estados.
3. Aceitar o convite notifica **só** quem convidou, **uma** vez.
4. Recusar, retirar, desfazer amizade e bloquear **não** notificam ninguém.
5. Dez curtidas em sequência produzem exatamente **duas** notificações (a 1ª e a
   10ª); descurtir e recurtir não produz nenhuma nova.
6. O dono curtindo o próprio post não é notificado, e a curtida seguinte, de
   outra pessoa, **é** anunciada como primeira.
7. Apagar o post antes do envio cancela a notificação.
8. Abrir o app dez vezes seguidas sem gravar rota nenhuma não dispara **nenhuma**
   invocação do gatilho de ranking (medido no console).
9. Duas contas no mesmo aparelho: depois que a segunda entra, a primeira para de
   receber — mesmo que o logout tenha falhado.
10. `flutter test`, `functions/npm test` e `firestore-tests/npm test` verdes.

## Fora de escopo

Tela de notificações, badge de não-lidas, histórico. Agrupamento de várias
notificações numa só. Agendamento local ("você não registrou rota hoje").
Silenciar por tipo de evento com canais nativos do Android — o opt-out, quando
vier, é um mapa em `user/{uid}` que a função lê antes de enviar, o que custa 1
leitura só quando há algo a notificar. Janela de silêncio noturna, decidida e
recusada em "Decisões". Limpar a bandeja — `firebase_messaging` não tem
`cancel()`, e o dia em que isso for preciso é o dia em que
`flutter_local_notifications` entra e este argumento inteiro se inverte.

## Decisões

Tomadas com o dono em 24/08/2026, junto com a leitura da spec:

1. **A permissão é pedida na abertura do app**, logo depois de publicar o perfil.
   O sistema mostra o diálogo uma vez só, e uma tela de pré-permissão seria UI
   nova para um app de um usuário. O preço, escrito para ninguém se surpreender
   depois: o iOS dá **um** tiro — negado ali, só volta pelos Ajustes do aparelho.

2. **Sem o spike do `authId`. O evento 2 fica no gatilho do apagar do marcador.**
   A pergunta era se valia testar `onDocumentCreatedWithAuthContext`, uma variante
   de gatilho que entregaria de brinde o uid de **quem escreveu** o documento —
   com ela, em vez de deduzir quem aceitou o convite, a plataforma diria. Perde
   por não ser confiável o bastante para sustentar a primeira Function do
   projeto: o campo é opcional no evento, o comportamento não está documentado, e
   há relato de o emulador local preencher com valor falso — e o emulador é onde a
   disciplina de teste deste projeto mora. O gatilho no marcador funciona hoje,
   custa uma leitura, não muda regra nenhuma e vale para quem já tem o app
   instalado. O ganho do `authId` seria trocar quinze linhas por três.

3. **JavaScript, não TypeScript.** A preferência do dono é TS, e a regra que ele
   deu é "se já usa JavaScript, mantém" — o único precedente Node do repositório
   é `firestore-tests/rules.test.mjs`, ESM puro, sem passo de build. O que se
   perde é o tipo no espelho do ranking, que é justamente onde um `pacedStops`
   digitado errado passaria batido; é por isso que `rank.test.mjs` espelhar os
   casos de `ranking_test.dart` **com os mesmos números** não é zelo, é a defesa
   que substitui o compilador. Se `functions/` passar de uns poucos arquivos, TS
   é o upgrade — e aí `tsc` entra junto com o resto.

4. **Sem janela de silêncio noturna.** A pergunta era se o servidor deveria
   segurar ou descartar notificações de madrugada. Fica de fora, e o motivo é o
   público: uma janela fixa (22h–7h, por exemplo) estaria errada **justamente**
   para quem roda Amazon até as 23h e dorme às 4h. O "Não perturbe" do próprio
   celular já resolve isso seguindo o horário real de cada um, com granularidade
   por app, e é do sistema operacional — não é trabalho que este servidor faça
   melhor. Se um dia virar problema, o remédio barato é o mesmo do opt-out por
   evento: uma checagem na hora de enviar, não uma fila com agendamento.

5. **Token de registro, não FID** — decidido em 25/08/2026, durante a A9.

   `firebase-admin` 14 **deprecou** todo o alvo por registration token
   (`TokenMessage`, `MulticastMessage.tokens`) em favor de FIDs, com a nota de
   que na próxima major o nome volta "depois que o baseado em token for
   removido". Isso pôs em questão o esquema de `fcmTokens`, que já estava
   escrito e testado.

   Ficou o token, e **não por inércia: o FID é inalcançável a partir deste app.**
   O `firebase_messaging` 16.6.0 não tem uma linha de FID — busca por
   `fid|onRegistered|installation` no pacote inteiro, Dart e nativo, devolve
   zero. O atalho aparente, ler o FID pelo `firebase_app_installations` e
   mandá-lo no campo novo, é **mecanicamente morto**: o registro por FID é uma
   chamada de rede à parte (`registerOverV1`), atrás de metadata de plataforma
   que este projeto não tem, e um FID lido por `getId()` é um identificador que
   o backend do FCM nunca viu. Gravaríamos 22 caracteres, a regra passaria, os
   testes ficariam verdes e **nenhum celular acenderia** — a pior família de
   falha que existe nesta feature. Pior: ligar aquelas metadatas faz o
   `getToken()` **lançar exceção**, e as duas APIs se excluem por construção.

   Três fatos que tornam a espera barata. Não há data anunciada para a remoção
   do token, e a doc diz que os dois padrões são "fully co-supported". O campo
   `token` **também aceita um FID** durante a transição, então o servidor não
   precisa saber qual identificador está guardando. E o esquema é cego ao
   identificador: `sha256` de qualquer string dá 64 hexadecimais.

   A migração, quando vier, são três coisas juntas — as metadatas de plataforma,
   trocar `getToken()`/`onTokenRefresh` por `register()`/`onRegistered`, e
   `token:` por `fid:` na Function. Meia migração é a feature muda. O gatilho que
   deve nos fazer olhar de novo é o `register()` chegar ao `firebase_messaging`
   publicado — hoje é um PR marcado `do-not-merge`.

   `push.js` já descarta `messaging/installation-id-not-registered` junto com o
   de token: custa uma linha e faz esse caminho ser um no-op na migração.

## Perguntas em aberto

1. ~~Medir se escrita byte-idêntica dispara gatilho.~~ **Respondido em
   27/08/2026: dispara**, ao menos no emulador — oito gravações, oito
   invocações. Ver B5.
2. **Android 13+ não distingue "negou" de "ainda não perguntei"**, então o app não
   consegue dizer honestamente ao motorista que as notificações estão desligadas.
   Vale uma linha em alguma tela, ou fica sem? Decidir quando a etapa A estiver
   rodando no aparelho — é mais fácil responder vendo.

## Tarefas

Três entregas, na ordem em que uma destrava a outra. A fatia é a mesma lógica que
`amigos.md` usou para pôr comentário depois de bloqueio: o que carrega conteúdo
de terceiro vem por último.

**Etapa A — infra e os eventos 1 e 2** (nada aqui depende de App Check)

Doze tarefas, na ordem de dependência. A ordem não é arbitrária: **A6 prova a
fiação do toque inteira antes de existir uma linha de servidor**, o que impede o
erro clássico de depurar cliente e servidor ao mesmo tempo sem saber de qual lado
está o defeito.

- [ ] **A1 · Orçamento e alerta de faturamento no Google Cloud.**
      Aceite: alerta configurado com teto e e-mail. Verificação: console.
      É a primeira tarefa porque é a única que protege contra as outras onze.

- [x] **A2 · `flutter pub add firebase_messaging`.** — feita em 25/08/2026.
      Aceite: `flutter analyze` e `flutter test` iguais à linha de base (169
      avisos; 1142 passando, 1 falhando — o `widget_test.dart` do template),
      **`flutter build apk --debug` passando**, e o app rodando no aparelho com
      login, feed e foto.

      **O aceite ganhou o build por causa do que aconteceu aqui, e a lição vale
      para toda a etapa:** `flutter pub add firebase_messaging` sozinho deixou o
      projeto **sem compilar**, e o `analyze` e os 1142 testes ficaram **verdes**
      o tempo todo. O `pub add` subiu `firebase_core` de 4.13.0 para 4.14.0 —
      única mudança que a resolução exigia — e deixou `firebase_auth` em 6.5.6,
      que referencia `FlutterFirebaseCorePlugin.customAuthDomain`, símbolo que o
      4.14.0 removeu. O erro é Java, na camada Android do plugin, onde a análise
      Dart e o `flutter test` nunca pisam.

      Conserto dirigido: `flutter pub upgrade firebase_auth firebase_storage`
      (6.6.0 e 13.5.0, ambos dentro das restrições que já estavam no pubspec).
      `cloud_firestore` ficou em 6.7.1, que já era o mais novo compatível.

      **Nenhum comando de Dart acusa descompasso na camada nativa.** Sempre que
      esta feature mexer em dependência, o portão é `flutter build apk --debug`
      — e, quando tocar iOS, também o build de lá.

      **E o portão do Android não bastou.** Na A4 apareceu um segundo
      descompasso, do mesmo upgrade e invisível até ali: `cloud_firestore` ficou
      em 6.7.1 pedindo o Firebase iOS SDK antigo, enquanto `firebase_core` 4.14.0
      passou a fixar o 12.18.0. O Android compilava; o `pod install` não. A causa
      do descuido foi a minha verificação, não a resolução do pub — eu conferi as
      versões com um `grep` por "firebase", e **`cloud_firestore` não contém essa
      palavra**. Corrigido com `flutter pub upgrade cloud_firestore` (6.9.0).

      Lição que vale mais que o conserto: **verificação por filtro de nome erra
      no pacote cujo nome não segue o padrão.** O portão certo é compilar as duas
      plataformas, não listar versões.

      Arquivos: `pubspec.yaml`, `pubspec.lock`, `ios/Podfile.lock`,
      `macos/Flutter/GeneratedPluginRegistrant.swift` (gerados).

- [x] **A3 · Android: ícone, canal, cor.** — feita em 25/08/2026, verificada no
      APK: `aapt2 dump resources` mostra `drawable/ic_stat_iter` (XML) e
      `color/notificacao`, e os três meta-data estão no manifesto mesclado. O
      `POST_NOTIFICATIONS` veio da mesclagem do SDK, sem declaração no manifesto
      do app, como previsto. **Falta o olho no aparelho:** se a silhueta lê bem a
      24dp e se o banner sobe é julgamento do dono, não de comando.
      Aceite original:
      Aceite: `drawable/ic_stat_iter.xml` (vetor branco 24dp), `values/colors.xml`,
      as três `meta-data` no manifesto, e o canal `iter_social` com
      `IMPORTANCE_HIGH` criado no `MainActivity.kt`. Verificação: notificação de
      teste desenha a silhueta (não um quadrado) e **abre banner heads-up**; nos
      Ajustes do aparelho o canal aparece com nome em português.
      Arquivos: `android/app/src/main/res/drawable/ic_stat_iter.xml`,
      `res/values/colors.xml`, `AndroidManifest.xml`,
      `kotlin/com/mna/iter/MainActivity.kt`.
      **Decisão irreversível:** id e importância do canal não mudam depois.

- [~] **A4 · iOS: preparado e desligado** — 25/08/2026. O que dependia de mim
      está feito; o resto **está bloqueado por conta paga da Apple**, que o dono
      não tem. A primeira publicação é só Android, por decisão dele.

      **Feito e verificado:**
      - `AppDelegate.swift` com `import firebase_messaging` e
        `FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()`
        **dentro** do método que já existia — o `FlutterImplicitEngineDelegate` e
        o `didInitializeImplicitFlutterEngine` intactos. Sem essa chamada o
        `onMessage` nunca dispara sob UIScene; o README do plugin tem uma seção
        dedicada a isso, e o snippet Swift dele **não traz o import** (só o de
        Objective-C traz).
      - `IPHONEOS_DEPLOYMENT_TARGET` de 13.0 para **15.0** nas três
        configurações, alinhado ao `platform :ios, '15.0'` do Podfile.
      - `ios/Runner/Runner.entitlements` **criado e deliberadamente NÃO ligado ao
        projeto**. Ligá-lo (o `CODE_SIGN_ENTITLEMENTS` nas três configurações)
        faz o iOS exigir o entitlement de Push no perfil de provisionamento —
        que conta gratuita não emite. Quebraria hoje o build no iPhone do dono,
        que funciona, **sem ligar nada em troca**, porque sem chave APNs o push
        não funcionaria de qualquer forma. O arquivo existe para o dia em que a
        conta existir.

      **Verificado** com `flutter build ios --debug --simulator`, que compila e
      **linka** sem exigir assinatura, entitlement nem conta paga: se o símbolo
      `configureNotificationCenterDelegate` não resolvesse, a linkagem falharia.
      `FirebaseMessaging.framework` embarcado, 37 frameworks no total (eram 29).

      Três tentativas falharam antes, **todas por ambiente e nenhuma por
      código** — vale registrar porque cada uma custou uma hora:

      1. Cache corrompido de DerivedData, com o erro apontando para módulos
         Swift do `firebase_auth`/`firebase_core` em `GeneratedPluginRegistrant.m`.
         Receita do `CLAUDE.md`: apagar `DerivedData/Runner-*`.
      2. `flutter clean` apaga `ios/Flutter/Generated.xcconfig`, e o Podfile
         **aborta ao ser interpretado** se ele não existir — o `pod install` do
         build corre antes de ele ser regenerado. O sintoma é um stack de Ruby em
         `Podfile.from_ruby`, que não parece ter relação nenhuma com o que se
         estava fazendo.
      3. Um `xcodebuild` **órfão** de uma tentativa anterior seguia vivo e
         segurando o `build.db`: *"database is locked. Possibly there are two
         concurrent builds"*. A shell dá o comando por encerrado e o processo
         continua. Antes de repetir um build iOS que falhou, confira com
         `ps -eo pid,etime,args | grep [x]codebuild`.

      **O que falta, quando houver conta paga** (nesta ordem):
      1. No portal da Apple: Certificates, Identifiers & Profiles → Keys → criar
         **uma** chave com o serviço APNs marcado, baixar o `.p8` (só dá para
         baixar **uma vez**) e anotar o **Key ID**.
      2. No console do Firebase: Configurações do projeto → Cloud Messaging →
         Apple app configuration → subir o `.p8` com Key ID e **Team ID**. Uma
         chave serve development **e** production, ao contrário de certificado.
      3. No Xcode: target Runner → Signing & Capabilities → **+ Capability** →
         Push Notifications. Isso liga o `Runner.entitlements` ao projeto.
      4. Conferir que entrou nas **três** configurações:
         `grep -c CODE_SIGN_ENTITLEMENTS ios/Runner.xcodeproj/project.pbxproj`
         tem de devolver **3**. A configuração *Profile* é do Flutter, projetos
         iOS normais não a têm, e é a que ninguém revisa — faltando lá, o build
         de profile sai sem `aps-environment` e o sintoma parece intermitente.
      5. Aceite em iPhone: os três estados, nos dois builds.

- [x] **A5 · Regra e testes de `fcmTokens`.** — feita em 25/08/2026.
      Onze casos novos, suíte de 90 para **101, todos passando**. Além dos
      previstos (ISO negado, uid alheio negado, ninguém lê nem lista, id fora do
      sha256 negado, campo a mais e a menos negados, plataforma fora da lista
      negada, anônimo negado, dono apaga o próprio e não o do outro), entraram
      dois que a spec não tinha pedido e que são o desenho inteiro:

      **"o celular emprestado: quem entra depois fica com o aparelho"** — a Bia
      grava por cima do documento da Ana e o teste **afirma o valor** de `uid`
      depois, com as regras desligadas. `assertSucceeds` sozinho não diria de
      quem o aparelho ficou, e é justamente esse o invariante que a chave
      invertida existe para sustentar.

      **"apagar aparelho inexistente passa"** — fixa como intencional o
      `resource == null` do `delete`, que é o que deixa o segundo logout ser
      no-op em vez de erro sem consequência.

      O `CLAUDE.md` foi corrigido junto: dizia 90 casos.
      Verificação: `cd firestore-tests && npm test`.

      **A regra foi publicada só em 26/08/2026, e a falta disso derrubou o
      primeiro teste em aparelho.** Escrevi a regra, testei contra o emulador e
      não fiz o deploy — em produção não existia `match` para `fcmTokens`, e o
      padrão do Firestore é negar. Toda gravação de token voltou
      `permission-denied`, o app engoliu num `debugPrint` (invisível em APK de
      release) e seguiu; os dois gatilhos dispararam certos e registraram
      `aparelhos: 0`.

      É o mesmo buraco que `sem-rota.md` já tinha documentado com outras
      palavras — *"a regra deployada não cria dado nenhum... é o único passo da
      entrega que nenhum teste acusa"* —, e eu caí nele mesmo tendo escrito o
      aviso na seção Commands desta spec. **`npm test` verde não é regra no ar.**
      O aceite de qualquer tarefa que mexa em `firestore.rules` termina em
      `firebase deploy --only firestore:rules --project iter-mn`, e essa linha
      agora está no aceite, não só nos comandos.

- [x] **A6 · A fiação do toque, provada sem servidor.** — feita em 25/08/2026.
      `Utils/pushTarget.dart` + 12 testes (suíte de 1142 para 1154 passando),
      `services/pushMessaging.dart`, `getInitialMessage()` em `main()`, descarte
      na `LoginScreen.initState`, `late final` retirado só de `_friends`, alvo
      aplicado em `initState` **e** `didUpdateWidget` da `FriendsScreen`.
      `flutter build apk --debug` passando.

      Três decisões que a implementação acrescentou:

      **O índice da aba Amigos virou constante.** Era `3` escrito em dois
      lugares (a ordem de `screens` e o `pendingIndex` do badge) e o push seria o
      terceiro. A primeira reordenação de abas quebraria dois deles em silêncio.

      **O toque em primeiro plano não navega.** O link "Ver" do toast estaciona
      o alvo no serviço e deixa o caminho de sempre atender. Um segundo caminho
      de navegação é como os dois lados passam a discordar — a mesma razão de
      `VehicleController.activeFrom()` ser único.

      **A ordem das guardas em `_aoReceberAlvo` é load-bearing.** O `consumir()`
      da aba roda dentro do `build` da Home, e o listener é chamado ali mesmo:
      qualquer `setState` antes da porta `alvo == null` seria escrita durante a
      construção da árvore.

      Falta: abrir a thread do post no evento 5 (depende de
      `PostController.fetch`, etapa C) e o `initialCriterion` da `RankingTab`
      (etapa B). O alvo já carrega os dois dados.

      Aceite original:
      Aceite: `Utils/pushTarget.dart` + `test/unit/pushTarget_test.dart`; o
      `ValueNotifier` no serviço; `getInitialMessage()` em `main()`; a limpeza na
      `LoginScreen.initState`; `late final` retirado só de `_friends`; a intenção
      aplicada em `initState` **e** `didUpdateWidget` da `FriendsScreen`.
      Verificação: **`xcrun simctl push` no simulador** e o equivalente por
      `adb`/console no Android, com `gcm.message_id` na raiz do JSON, cobrindo os
      **três** estados. Nenhuma Cloud Function existe ainda nesta tarefa.

- [x] **A7 · Registro do token no app.** — feita em 25/08/2026. `crypto`
      entrou como dependência **explícita**: era transitiva, e depender de
      transitiva é depender de uma decisão de outro pacote.

      Uma decisão que a spec não tinha fechado: **registra mesmo com a permissão
      negada.** Sair cedo no "não" cria um estado morto e silencioso — quem
      depois liga as notificações nos Ajustes do aparelho continua sem receber
      nada, porque ninguém gravou o token, e só descobre no dia em que reabrir o
      app por outro motivo. O preço de registrar são algumas mensagens enviadas
      para um aparelho que não as desenha; o preço de não registrar é uma
      feature que não volta sozinha.

      O handler do `onTokenRefresh` lê `FirebaseAuth.instance.currentUser` **na
      hora de gravar**, e não o uid de quando a assinatura nasceu: o `AuthGate`
      troca a tela sem trocar o processo, então a escuta sobrevive a um logout
      seguido do login de outra conta.
      Aceite original:
      Aceite: `services/pushMessaging.dart` com permissão pedida na abertura (logo
      após disparar o publish, como segundo future independente), `getAPNSToken()`
      com retry antes de `getToken()` no iOS, `sha256` como id, `serverTimestamp`
      no `updatedAt`, `onTokenRefresh` assinado no serviço.
      Verificação: abrir o app nos dois aparelhos e ver **dois** documentos em
      `fcmTokens`, com o mesmo `uid`.

- [x] **A8 · Baixa do token no logout.** — feita em 25/08/2026. Confirmado o
      que a varredura previa: `signOut()` **não** precisou de assinatura nova.
      O serviço guarda o `sha256` gravado na sessão, e `desregistrarAparelho()`
      é a primeira linha — `home.dart` ficou intocado.

      E **fora do `try` existente**, não dentro: aquele bloco faz `rethrow` e a
      tela mostra o erro. Uma falha ao apagar o token, sem rede, não pode
      impedir alguém de sair da própria conta. O método engole a própria
      exceção e tem prazo de 5s.
      Aceite original:
      Aceite: `PushMessagingService.unregister()` como primeira linha de
      `GoogleSignInService.signOut()`, com try/catch e timeout próprios;
      `home.dart` intocado. Verificação: sair da conta apaga o documento; e o
      caminho que importa de verdade — entrar com a **segunda** conta no mesmo
      aparelho troca o `uid` do documento, e a primeira para de receber.

- [x] **A9 · `functions/` de pé.** — feita em 25/08/2026. `package.json` ESM com
      Node 22 e versões **fixadas** (`firebase-admin` 14.3.0, `firebase-functions`
      7.3.2, sem `^`), região no `index.js`, `texto.js`, `push.js`, bloco
      `functions` no `firebase.json` e 27 testes com `node --test`.

      **Deploy não entra aqui:** não há gatilho nenhum ainda, então
      `firebase deploy --only functions` publicaria zero funções. Ele é o portão
      da A10.
      Aceite original:
      Aceite: `package.json` ESM com Node 22 e `firebase-admin` **fixado**, região
      `southamerica-east1`, `push.js` (busca de tokens por `uid`, envio com
      `priority: 'high'`, limpeza que distingue token morto de erro de credencial
      APNs), `texto.js`. Verificação: `firebase deploy --only functions --project
      iter-mn` conclui e a Cloud Messaging API v1 está habilitada.

- [x] **A10 · Evento 1 — convite enviado.** — código feito e **provado no
      emulador** em 25/08/2026; falta o deploy e o aceite em aparelho.

      `functions/amizade.js`, mais `firebase.js` (acessor único), `perfis.js` e
      `opcoes.js`. Prova: `npm run emulador` sobe Firestore + Functions e a
      escrita em `friendRequests/{bia}/incoming/{ana}` produz
      `{"de":"uid-ana","para":"uid-bia","aparelhos":0,...,"message":"convite"}`;
      o auto-convite termina em 2,7 ms, sem tocar o banco.

      **Duas armadilhas que só o emulador pegou**, e as duas eram silenciosas:

      1. **A região não estava sendo aplicada.** `export { x } from './y.js'` é
         declaração de módulo, e declarações são **içadas**: o `y.js` avalia — e
         o gatilho é declarado — antes de qualquer linha do corpo do `index.js`,
         `setGlobalOptions()` inclusive. O endpoint saía sem região, rumo a
         `us-central1`, incompatível com um banco em `southamerica-east1`. A
         região passou a ir explícita em cada gatilho, a partir de `opcoes.js` —
         imune à ordem de avaliação, e ainda com um lugar só para mudar.

      2. **`getApps().length > 0` não implica que o app *padrão* exista.** A
         função morria em toda invocação com "The default Firebase app does not
         exist". O acessor virou `try { getApp() } catch { initializeApp() }`.
         Nenhum teste unitário pegaria isso; em produção o sintoma seria a função
         morrer a cada disparo com a notificação nunca saindo.

      **`emulador.mjs` fica fora de `test/`** pelo mesmo motivo que
      `firestore-tests/` mora fora de `test/` no Flutter: `npm test` é
      `node --test`, que varre aquele diretório, e este precisa do emulador de
      pé. E `run-emulador.sh` repete o truque do `JAVA_HOME` — o emulador quer
      Java 21, o build Android quer 17.
      Aceite original:
      Aceite: gatilho em `friendRequests/{userId}/incoming/{otherId}`, notifica
      `userId`, nome vindo de `profiles/{otherId}`. Verificação: convidar de um
      aparelho e o outro acender, nos três estados.

      **O deploy, e as duas coisas que ele ensinou** (25/08/2026):

      A primeira tentativa falhou com `403 ... Permission
      "iam.serviceAccounts.ActAs" denied`. Não era permissão do dono nem erro de
      código: as APIs `run` e `eventarc` foram **habilitadas no mesmo comando**,
      segundos antes, e as contas de serviço que elas provisionam nascem de forma
      assíncrona — quando o trigger do Eventarc foi criado, a permissão ainda não
      tinha propagado. **Repetir o mesmo comando resolveu.** Vale escrever porque
      a mensagem aponta para IAM e manda o próximo leitor mexer em papéis que já
      estão certos.

      A segunda: o deploy avisa que **não há política de limpeza** no Artifact
      Registry. Sem ela cada deploy deixa uma imagem de container acumulada e a
      conta cresce devagar, para sempre. Resolvido com
      `firebase functions:artifacts:setpolicy --location southamerica-east1 --days 3 --force --project iter-mn`.

      No ar: `convite`, 2ª geração, `southamerica-east1`, Node 22, 256 MB.


- [x] **A11 · Evento 2 — convite aceito.** — feita e no ar em 25/08/2026.
      Gatilho no `onDocumentDeleted` de `friendRequests/{userId}/outgoing/{otherId}`,
      notificando só quando `friends/{userId}/list/{otherId}` existir depois do
      commit. Os quatro caminhos provados no emulador: aceite notifica quem
      convidou (uma vez), quem aceitou não recebe nada, recusa não notifica.

      **O emulador achou um evento fantasma, e ele era grave.**
      `FriendController.accept` e `decline` apagam os **quatro** caminhos de
      marcador sem saber quais existem — apagar inexistente é no-op, e o
      `CLAUDE.md` registra isso como deliberado. Contra o emulador esse no-op
      entrega um `onDocumentCreated` para o caminho que **nunca existiu**: quem
      convidou recebia "fulano aceitou seu convite" **e** "fulano enviou um
      convite de amizade pra você", o segundo falso, a cada aceite do app
      inteiro. A recusa produzia o mesmo.

      Fechado com `if (!event.data?.exists) return` no gatilho do convite. **Não
      foi verificado se produção se comporta como o emulador, e a porta existe
      justamente para não depender disso:** se se comporta, ela conserta; se não,
      nunca fecha e não custa nada. O modo de falha do outro lado é uma
      notificação mentirosa para todo mundo, o que torna a dúvida cara demais
      para ser resolvida por opinião. Duas asserções no `run-emulador.sh`
      impedem a volta.

      No ar: `convite` e `aceite`, ambas 2ª geração, `southamerica-east1`.
      Aceite original:
      Aceite: gatilho no `onDocumentDeleted` de
      `friendRequests/{userId}/outgoing/{otherId}`, notificando **só** quando
      `friends/{userId}/list/{otherId}` existir depois do commit.
      Verificação: aceitar notifica uma vez, e **recusar, retirar, desfazer
      amizade e bloquear não notificam ninguém** — os quatro caminhos testados um
      a um. O convite mútuo notifica os dois; é a aresta conhecida.

- [~] **A12 · Aceite em aparelho, que é o único que responde.** — primeira
      rodada em 26/08/2026, em dois Android, e **verde em 27/08 depois do deploy
      das regras**: `convite` e `aceite` com `aparelhos: 1` no Cloud Logging, e
      notificação vista nos dois celulares. Falta cobrir os **três estados**
      (app aberto, em segundo plano, fechado) — a rodada de 27/08 provou a
      cadeia, não a matriz. iOS adiado por conta paga (ver A4).

      Histórico da primeira rodada, que vale guardar: **nada notificou, e o
      diagnóstico
      levou minutos porque o log foi desenhado para isso:** os dois gatilhos
      apareceram no Cloud Logging com a direção certa e `aparelhos: 0`, o que
      isola o defeito no cliente e descarta servidor, gatilho e caminho. A causa
      era a regra não publicada (ver A5). Repetir depois de reabrir o app nos
      dois aparelhos.

      O que o `aparelhos` responde, e é o motivo de ele existir: **0** = token
      não registrado, problema no app ou na regra; **N > 0** e ninguém vê nada =
      mensagem saiu, problema no canal, no ícone ou no aparelho; **nenhuma linha
      de log** = o gatilho não disparou, problema no caminho ou no deploy.
      Aceite original:
      Aceite: os dois eventos × três estados (aberto, background, morto) × dois
      sistemas × dois builds (debug e release). Mais os passos de fabricante nos
      Android brasileiros. Nenhum `npm test` alcança um gatilho e não existe
      emulador de FCM — esta tarefa não tem substituto automatizado.

**Etapa B — evento 3** — feita e no ar em 27/08/2026.

- [x] **B1 · `updatedAt` fora dos 13 baldes** (e só deles; a projeção
      `profiles/{uid}` continua com o dele, que a regra exige em `hasAll`). O
      campo não tinha leitor: nem `MonthStats.fromMap`, nem
      `ProfileStats.fromMap`, nem a regra. `refreshAfterRoute` perdeu junto o
      parâmetro `now`, que só existia para carimbar.

- [x] **B2 · Republicar ao excluir rota** (`listIterScreen._republishStats`).
      Gravar rota já republicava; apagar não. A rota sumia do app na hora e
      continuava contando no ranking dos amigos até a próxima abertura — horas
      depois da causa. `unawaited` e com `try` próprio: o dono já viu a rota
      sumir, e erro de rede aqui não pode virar "não foi possível excluir".

- [x] **B3 · `rank.js` + 28 casos espelhando `ranking_test.dart`**, com os
      mesmos números — inclusive o caso real do usuário (17 rotas em 2h49 contra
      5 em 4h27, que pelo ritmo quase empatam). `MonthStats.toMap()` ganhou o
      comentário apontando para `functions/`, como o regex de apelido tem para
      `firestore.rules`.

      Duas linhas do comparador **não existem no Dart** e são o coração da
      adaptação: lá a regra do rodapé mora na concatenação de `rankBy`; aqui,
      sem lista, ela vira código — *quem não disputa está atrás de todo mundo
      que disputa, e a ordem interna do rodapé não é posição*. É o que impede o
      detector de ler "entrou na disputa" como "ultrapassou".

- [x] **B4 · `avisosRanking` com `read, write: if false`** e três casos
      negativos (suíte de 103 para **106**). O ataque que a regra fecha: pré-criar
      o marcador do dia de alguém a emudece pelo dia inteiro, e **a supressão é
      invisível para os dois lados** — ao contrário do apelido tomado, que dá
      erro na cara de quem tenta. É onde a analogia com `nicknames` termina.

- [x] **B5 · O gatilho**, com os dois portões e o teto diário. Dez asserções no
      emulador, e três provam o que não pode acontecer: reescrita não avisa, mês
      velho não avisa, e o mesmo par no mesmo dia avisa **uma vez** mesmo com
      duas ultrapassagens.

      **A pergunta em aberto nº 1 foi respondida por medição, e a resposta
      contraria a documentação:** oito gravações de balde produziram **oito
      invocações** — a escrita byte-idêntica **disparou o gatilho** no emulador,
      apesar de a doc do Firestore dizer que *no-op write* não gera evento. Não
      dá para afirmar que produção se comporta igual, e o desenho deixou de
      depender disso: o portão `baldeMudou` é **load-bearing**, não decoração, e
      sai antes de qualquer leitura de amigo. Tirar o `updatedAt` (B1) continua
      certo — é o que torna a otimização *possível* —, mas a economia não é
      garantida, e o que garante o custo baixo é o portão.

- [x] **B6 · `initialCriterion` na `RankingTab`**, aplicado em `initState` **e**
      `didUpdateWidget` — quem chega de outra aba passa pelo primeiro, quem já
      estava no Ranking só pelo segundo. Aqui igualdade de **valor** basta, ao
      contrário do alvo em si: dois avisos do mesmo critério não têm o que fazer,
      e é isso que impede o parâmetro de grudar quando o usuário troca de
      critério na mão.

No ar: `convite`, `aceite` e `ranking`, todas 2ª geração, `southamerica-east1`.
Regras publicadas junto — agora parte do aceite, não só dos comandos.

**Etapa C — eventos 4 e 5** — feita e no ar em 30/08/2026.

- [~] **C1 · App Check** — código pronto e console configurado; **imposição
      deliberadamente desligada**. Ver "App Check: 90% console".

- [x] **C2 · `marcos.js` + 17 casos**, incluindo o 11→10 que é a razão de a
      régua ser derivada e não testada por igualdade.

- [x] **C3 · `PostController.fetch(id)`**, devolvendo `null` para inexistente
      **e para lápide** — quem filtra o tombstone hoje é o `parse()` da lista, e
      uma thread aberta por link pularia esse filtro.

- [x] **C4 · Os dois gatilhos**, na ordem de operações da spec. As duas linhas
      que quebraram o desenho no papel estão comentadas onde acontecem: sair sem
      criar o marcador quando o autor é o dono, e reler o post antes de enviar.

- [x] **C5 · `posts/{postId}/marcos` com `read, write: if false`** e quatro casos
      (suíte de 106 para **110**), incluindo o que fixa que fechar a subcoleção
      **não** fechou curtir — regra do Firestore não cascateia, e trocar o bloco
      de lugar quebraria o mural inteiro.

- [x] **C6 · Deep link para a thread**, aplicado em `initState` **e**
      `didUpdateWidget` da `FeedTab` — e **antes** da porta do bloqueio, que faz
      `return` cedo. Pendurado depois dela, o link se perderia sempre que a
      lista de bloqueados não tivesse mudado, ou seja, quase sempre.

Cinco asserções novas no emulador, e as duas que mais valem são consequência
direta do desenho:

**A auto-curtida não deixa marcador, e é isso que salva a primeira.** A Inês
curte o próprio post (contagem 1, nenhum aviso, nenhum marcador); o João curte
(contagem 2); a régua deriva o marco 1 e a Inês recebe "Primeira curtida". Com
teste de igualdade — `n === 1` — essa notificação se perderia para sempre, em
todo post que o dono curtisse.

**Dez curtidas em rajada anunciam o marco 10 uma vez.** O log registra
`{"marco":10,"total":12}`: as invocações correram entre si e leram contagens
diferentes, todas convergiram para o mesmo marco, e o marcador deixou passar
uma. A corrida deixou de ser exceção e virou o caso normal.

O post com lápide também está coberto: a curtida é gravada (o Admin SDK ignora a
regra que a barraria) e a função desiste na releitura.

No ar: `convite`, `aceite`, `ranking`, `curtidas` e `comentarios`.

