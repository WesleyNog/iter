# Spec: Excluir a conta

Status: **implementada e publicada** · Criada, aprovada, implementada e com
deploy em 2026-09-16 (índices, Function `excluirConta` e Hosting em
`iter-mn.web.app`) · Falta confirmar os três índices como "Ativado" no console
antes de o app com o botão chegar a alguém, e a primeira exclusão real em
produção

## Objetivo

A Play exige, de todo app que deixa criar conta, duas portas para apagá-la: uma
**dentro do app** e uma **página web** para quem já desinstalou. O iter não
tinha nenhuma — `amigos.md` registrava a ausência como dívida desde que as
arestas de amizade passaram a morar em listas alheias.

Usuário: o entregador que quer sair. Sucesso = um toque no menu, a confirmação
do Google, e nada que o identifique sobra no projeto.

## Por que o app não apaga sozinho

A primeira ideia — um `WriteBatch` grande no cliente — esbarra nas próprias
regras, e cada esbarrão é uma decisão antiga e correta:

- `fcmTokens` é ilegível até para o dono. O celular só conhece o **próprio**
  token; os outros aparelhos da pessoa continuariam recebendo push de uma conta
  que não existe.
- `gastop/*/precos` é imutável: histórico que se reescreve não é histórico.
- Achar os comentários e curtidas da pessoa em posts **alheios** exige
  `collectionGroup`, que exige regra em `/{path=**}/` e índice — aparato aberto
  para todo cliente só para servir a um fluxo que roda uma vez na vida.
- O app pode morrer no meio, e conta meio apagada é o pior dos dois mundos.

O projeto está no Blaze e já tem Functions. O Admin SDK não passa pelas regras,
então o servidor faz o que o cliente não pode — sem afrouxar regra nenhuma.

## O gatilho: a conta sumir do Auth

`functions/conta.js` exporta `excluirConta`, pendurada em
`auth.user().onDelete`. **O app não chama função nenhuma**: pede o login do
Google de novo, chama `user.delete()`, e a limpeza acontece do lado de lá.

Três razões, na ordem em que pesaram:

1. **Toda exclusão limpa, venha de onde vier.** O pedido pela página web é
   atendido apagando o usuário no console do Firebase — e isso dispara a mesma
   limpeza. Uma função *callable* cobriria só o botão do app, e o pedido por
   e-mail precisaria de um script com credencial de admin na máquina do dono.
2. **O login recente é o Firebase que exige.** `user.delete()` devolve
   `requires-recent-login` se o login for antigo; numa callable, essa checagem
   (`auth_time`) seria código nosso — e código de segurança que a gente escreve
   é código de segurança que a gente pode errar.
3. **Nenhuma dependência nova no Flutter** (`cloud_functions` ficaria só para
   isto).

O preço, registrado para ninguém redescobrir:

- **É de 1ª geração.** Não existe gatilho de exclusão de usuário na 2ª — só os
  bloqueantes `beforeUserCreated`/`beforeUserSignedIn`. As outras cinco funções
  continuam na 2ª.
- **O app não sabe se a limpeza terminou.** Por isso `failurePolicy: true`
  (repete por até 7 dias) e **cada passo pode rodar de novo** sem estrago:
  apagar o que não existe é no-op, e a anonimização tira o `uid` que a própria
  busca usa para achar o documento.
- **A Function tem de estar no ar antes do botão.** Sem ela, `user.delete()`
  funciona, a pessoa vê "conta excluída" e **todos os dados ficam**, sem dono e
  sem ninguém que saiba o uid. É a mesma classe de falha de `norouterule`: nenhum
  teste pega um deploy esquecido.

## O destino de cada dado

| Dado | Destino | Por quê |
|---|---|---|
| `user/{uid}` | apagado | CPF, e-mail, telefone |
| `iter/{uid}/*` — rotas, veículos, abastecimentos, manutenções, espelho de posts | apagado | é a pessoa |
| `profiles/{uid}` e `stats/*` | apagado | vitrine pública |
| `nicknames/*` com o uid | apagado | o apelido volta a ficar livre |
| `fcmTokens/*` com o uid | apagado | **todos** os aparelhos, não só este |
| `friends` — a lista dela **e** a aresta dela na lista de cada amigo | apagado | senão ela continua na lista do outro |
| `friendRequests` — os quatro marcadores com cada pessoa | apagado | idem |
| `blocks/{uid}/list/*` | apagado | a lista é dela |
| curtidas dela (`collectionGroup('likes')`) | apagado | gesto dela |
| comentários dela em qualquer post (`collectionGroup('comments')`) | apagado | texto dela |
| Storage `posts/{uid}/*` | apagado | foto dela |
| `avisosRanking/*` com o uid no id | apagado | registra "A passou B", que é vínculo |
| `posts` dela | **lápide** | ver abaixo |
| `gastop/*/precos` dela e `gastop.updatedBy` | **fica, sem o uid** | ver abaixo |
| `reports` que ela fez | **fica** | ver abaixo |
| `blocks` que **outras pessoas** fizeram contra ela | fica | é dado de quem bloqueou |

### Posts viram lápide, igual ao "apagar" de hoje

`PostController.erase` já grava `{deleted: true, text: '', imagePath: null}`, e
a razão de nunca ser `delete` continua valendo com o Admin SDK: os comentários
**de outras pessoas** embaixo do post são dado delas. Apagar de verdade levaria
esses comentários junto. A lápide some do feed (`parse` filtra `deleted`), e o
que sobra no documento é `uid`, `createdAt` e `company`.

### Relatos de preço ficam, sem o uid

A mediana é de todo mundo, e apagar os relatos tiraria dos outros um preço que
foi verdade. Mas o `uid` **sai**, e a razão é concreta: `gastop/*/precos` é
listável por qualquer autenticado, e o feed entrega o uid de todo autor. Relatos
com uid são a trilha de **onde e quando** a pessoa abasteceu.

Isso já vaza **hoje**, com a conta viva — está fora do escopo desta spec e
anotado no fim. A exclusão só não pode deixar o vazamento eterno.

### Denúncias ficam

`reports` tem `get` e `list` fechados para todo cliente: o uid ali só é visto
pelo dono do app, no console. E a denúncia fala do conteúdo **de outra pessoa**
— apagá-la porque quem denunciou saiu desfaria moderação sobre um conteúdo que
continua no ar. É a mesma razão de `delete: if false` na regra.

## A ordem que importa: arestas antes de marcadores

`aceite` (em `amizade.js`) dispara quando **qualquer**
`friendRequests/{a}/outgoing/{b}` é apagado e decide lendo se a aresta
`friends/{a}/list/{b}` existe. Se a limpeza apagasse o marcador com a aresta de
pé, o ex-amigo receberia **"fulano aceitou seu convite"** de uma conta que acabou
de deixar de existir — e o emulador já mostrou que apagar marcador *inexistente*
também entrega evento.

Então: primeiro as duas arestas com **toda** pessoa que aparece em amizade *ou*
convite, e só depois os quatro marcadores. As duas listas de caminhos são
funções puras em `functions/exclusao.js`, com teste.

## Índices

`collectionGroup('comments' | 'likes' | 'precos').where('uid', '==', …)` exige
índice de campo único com escopo **de grupo de coleções**, que o Firestore não
cria sozinho. `firestore.indexes.json` declara os três.

**O emulador não cobra índice.** O teste passa com ou sem o arquivo; em
produção, sem ele, a Function morre com `FAILED_PRECONDITION` na primeira
exclusão — e repete por sete dias. Deploy dos índices **antes** da Function, e
esperar o console marcar "Ativado".

Um override de campo **substitui** os índices automáticos daquele campo, por
isso cada entrada repete os três de escopo de coleção (asc, desc, contains) além
do novo.

## O app

- **Onde:** o botão de sair da `AppBar` virou um menu com "Sair" e "Excluir
  conta". A Play pede o caminho "fácil de achar"; um item vermelho no mesmo menu
  do sair é onde as pessoas procuram.
- **`DeleteAccountScreen`** diz o que some e o que fica **antes** de pedir
  qualquer coisa, e o botão só acende depois de marcar "Entendo que isso não
  pode ser desfeito".
- **`GoogleSignInService.deleteAccount()`** pede o Google de novo *sempre*, em
  vez de tentar e reagir a `requires-recent-login`: a reautenticação é também a
  segunda confirmação. Devolve `false` quando a pessoa desiste no seletor, igual
  ao `signInWithGoogle` devolve `null`. Escolher **outra** conta Google dá
  `user-mismatch`, e a tela diz isso com todas as letras.
- Depois do `delete()`, `disconnect()` revoga o acesso do app à conta Google —
  melhor esforço, porque a conta já não existe e falhar aqui não desfaz nada.
- A tela foi empilhada com `push`, então o `AuthGate` troca a Home pelo login
  **embaixo** dela. `popUntil(isFirst)` depois do sucesso, senão a pessoa fica
  olhando uma tela de uma conta apagada.

## As páginas web

`site/` no Firebase Hosting do próprio `iter-mn`:

- `/privacidade` — a política exigida na ficha da loja.
- `/excluir-conta` — a porta para quem desinstalou: como fazer pelo app, como
  pedir por e-mail, o que some e o que fica.

O pedido por e-mail é atendido **apagando o usuário no console** (Authentication
→ usuário → excluir). A Function faz o resto.

## Verificação

- `functions/test/exclusao.test.mjs` — os caminhos e a leitura do id do aviso.
- `functions/emulador.mjs`, bloco "Exclusão de conta" — uma conta completa, um
  amigo com convite pendente, curtida e comentário cruzados, relato de preço,
  denúncia, foto no Storage. Apaga o usuário **no emulador de Auth**, espera a
  Function e confere documento por documento o que sumiu e o que tinha de
  ficar. Roda a limpeza uma segunda vez para provar que repetir não quebra, e o
  `run-emulador.sh` proíbe o aceite falso — **o que não prova a ordem**: o
  gatilho lê de forma assíncrona, e com a ordem invertida as arestas quase
  sempre já teriam sumido quando ele lesse. A ordem é garantida pelo código de
  `desfazerVinculos`, não por este teste.
- `test/widget/deleteAccount_test.dart` — o botão apagado até a confirmação, e
  a desistência no Google não mostrando erro.

## Fora de escopo

- **O vazamento de `precos` com a conta viva.** Fechar `list` ou tirar o `uid`
  do relato muda o que a mediana pode fazer um dia (um relato por pessoa por
  posto). Merece spec própria.
- **Aresta órfã do outro lado.** Se `friends/{x}/list/{uid}` existir sem o par
  em `friends/{uid}/list/{x}` e sem convite entre os dois, a limpeza não a acha:
  a aresta só tem `at`, sem campo para consultar. O app nunca produz esse estado
  (`severTies` apaga os dois lados); um cliente forjado produziria. O `FriendTile`
  já desenha o fallback quando o perfil falta.
- **Apagar as subcoleções das lápides** — a mesma Function de economia de cota
  que `amigos.md` já lista.
- **Aviso por e-mail de que a exclusão terminou.**
