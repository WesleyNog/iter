# Spec: Painel Admin de moderação

> **Status: validada pelo dono em 2026-10-03** (ver "Decisões" no fim).
> Pendência única: o uid da conta admin, a copiar do console
> (Authentication → Users). A implementação pode nascer com um placeholder
> na regra — os testes extraem o literal do próprio `firestore.rules`, então
> trocar o placeholder pelo uid real não quebra nada.

## Objetivo

Hoje a fila de denúncias (`reports`) é lida à mão no console do Firebase, e
esconder um post é uma escrita de admin feita lá — o próprio
`firestore.rules` registra: "o documento é o canal". Funciona, mas o console
mostra o documento cru: para julgar uma denúncia é preciso copiar o `postId`,
navegar até `posts/{id}`, abrir a foto pelo caminho do Storage, e escrever a
lápide à mão com a forma exata — um erro de digitação grava um tombstone
inválido que nenhuma regra confere, porque o console não passa pelas regras.

O painel é uma página web no Hosting que já existe (`site/`, servido em
`iter-mn.web.app`), acessível **só pela conta do dono**, que mostra a fila de
denúncias com o conteúdo denunciado ao lado e resolve cada uma com um botão:
remover o post (a mesma lápide que `PostController.erase` grava), apagar o
comentário, ou ignorar. Diferente do console, o painel **passa pelas regras**
— a forma da lápide é conferida pelo `firestore.rules`, não pela atenção de
quem digita.

**Sucesso**: o dono abre a página no celular ou no desktop, loga com Google,
vê o que foi denunciado sem caçar ids, e resolve em um toque. Qualquer outra
conta que abra a mesma página não lê um byte.

## Premissas assumidas

1. **Um único admin, identificado pelo uid.** O acesso é decidido no
   `firestore.rules` por uid fixo (`function isAdmin()`), não por custom
   claim. Para um moderador só, o uid na regra é visível em revisão, não
   exige service-account key (o artefato mais perigoso que o projeto poderia
   ter em disco) e é testável no emulador com o mesmo literal. Se um dia
   houver um segundo moderador, a função vira
   `request.auth.token.admin == true` num commit só.
2. **Sem Cloud Functions no v1.** As regras bastam: abrir leitura de
   `reports` para o admin e estender duas escritas já existentes. Uma
   Function que notifica denúncia nova é etapa futura, não pré-requisito.
3. **Página estática no `site/`**, como `privacidade.html` e
   `excluir-conta.html` — HTML + JS puro com o SDK web do Firebase via CDN,
   sem build. É o primeiro JavaScript do site.
4. **Zero mudança no app Flutter.** O v1 toca `firestore.rules`,
   `storage.rules`, `firestore-tests/` e `site/`. Nenhum arquivo em `lib/`.
5. A URL do painel é pública (Hosting não autentica), e isso é aceitável:
   quem abre vê uma tela de login, e sem a conta do dono toda leitura volta
   `permission-denied`. A segurança é das regras, como no app.

## O que o admin passa a poder (e o que continua não podendo)

| Ação | Como | Mudança de regra |
|---|---|---|
| Ler a fila de denúncias | `reports` | `allow get, list: if isAdmin()` — a razão de `get/list: false` ("a lista de quem delatou quem") não se aplica ao moderador, que é o destinatário do canal |
| Ver o alvo (post, comentário, perfil do autor, foto) | leituras que **qualquer autenticado já tem** | nenhuma |
| Remover post denunciado | a lápide exata de `PostController.erase` | `update` de `posts` ganha `|| isAdmin()` **mantendo a forma pinada** — o admin não ganha update arbitrário, ganha o direito de gravar a mesma lápide |
| Levar a foto junto | delete do objeto em `posts/{uid}/…` | `storage.rules` ganha o admin no `delete` — a lápide anula `imagePath`, mas os bytes ficariam legíveis por qualquer autenticado que guardou o caminho |
| Apagar comentário denunciado | delete do documento | `delete` de `comments` ganha `|| isAdmin()` (hoje: autor ou dono do post) |
| Dar baixa na denúncia | `moderation/{alvo}` com `{resolution, at}` | coleção nova, só-admin, `resolution` de lista fechada |

A denúncia em si **permanece imutável** — "denúncia que se apaga não é
denúncia", e o `update` dela está pinado à forma de quem denuncia. A decisão
vive em `moderation/{alvo}`, onde o id é o **alvo** (`p_{postId}` ou
`c_{postId}_{commentId}`), não o id da denúncia: três pessoas denunciando o
mesmo post são três documentos em `reports` e uma decisão só — a baixa por
alvo resolve as três de uma vez. A fila pendente é `reports` agrupado por
alvo, menos os alvos presentes em `moderation`, join feito no cliente (a
fila inteira é pequena; são duas listas do admin). `delete: if false` na
baixa: a errada se corrige sobrescrevendo, não apagando.

O que o admin **não** ganha, de propósito:

- **Ler `user/{uid}`.** CPF, e-mail e telefone não julgam post nenhum. A
  moderação precisa do conteúdo, não da pessoa — o painel mostra
  `profiles/{uid}`, que já é a vitrine pública.
- **Delete real de post.** Apagar é marcar, pelas razões que o
  `firestore.rules` já documenta (subcoleções órfãs, id reciclado, `get()`
  da moderação errando).
- **Escrever em nome de outro.** Nenhuma regra nova relaxa `uid ==
  request.auth.uid` de criação nenhuma.

## Stack e estrutura

- `site/admin.html` — a página (login Google + fila + ações), pt-BR,
  reaproveitando `site/estilo.css`.
- `site/admin.js` — SDK web modular (`firebase-app`, `firebase-auth`,
  `firebase-firestore`, `firebase-storage`) via CDN do gstatic.
- `firestore.rules` / `storage.rules` — as mudanças da tabela acima.
- `firestore-tests/` — os casos novos (ver Testes).

Pré-requisito de console (uma vez): **registrar um Web App** no projeto
`iter-mn` para obter o config web (apiKey etc. — público por desenho, não é
segredo). `iter-mn.web.app` já é domínio autorizado do Auth por padrão.

## Comandos

```bash
cd firestore-tests && npm test            # regras, no emulador (hoje 103 casos)
firebase deploy --only firestore:rules    # depois do npm test verde
firebase deploy --only storage            # regras do Storage
firebase deploy --only hosting            # publica o painel
```

Ordem de deploy: regras primeiro (testadas), Hosting por último — o painel
sem regra nova só vê `permission-denied`, o que é inofensivo; regra nova sem
painel é invisível.

## Estilo de código

Como o `site/` existente: HTML semântico simples, texto em pt-BR, sem
framework e sem build. O JS segue o padrão do projeto de distinguir falha de
ausência: `permission-denied` na fila é "esta conta não é o admin", não
"fila vazia" — duas sentenças diferentes na tela, pela mesma razão que
`getWeather` não colapsa `null` em `clear`.

## Testes

As regras são o produto; os testes delas são a suíte que já existe
(`firestore-tests`, emulador, `npm test`). Casos novos:

1. Admin lista `reports`; conta comum e anônimo não (get e list).
2. Admin grava a lápide exata num post alheio; admin com texto ≠ `''`,
   `deleted` ≠ `true` ou chave extra é negado (a forma pinada vale para ele
   também).
3. Admin apaga comentário de terceiro num post de terceiro; conta comum
   continua negada.
4. `moderation`: admin lê e escreve; conta comum não lê nem escreve.
5. Regressão: nada do que os 103 casos atuais garantem muda — em especial,
   conta comum continua sem ler `reports` e sem lápide em post alheio.

O painel em si não ganha suíte própria no v1: é uma página de listagem cujo
comportamento de autorização é exatamente o que os testes de regra cobrem.
Validação manual na entrega (ver Critérios de sucesso).

## Fronteiras

- **Sempre**: `npm test` antes de qualquer deploy de regras; toda capacidade
  nova do admin nasce como regra + caso de teste no mesmo commit; a lápide
  gravada pelo painel é byte a byte a de `PostController.erase`.
- **Perguntar antes**: qualquer leitura nova aberta ao admin (sobretudo
  `user/{uid}`); banir/excluir conta pelo painel; editar `norouterule` pelo
  painel; adicionar Cloud Function.
- **Nunca**: service-account key no repo, no site ou na máquina sem
  necessidade; Admin SDK no navegador; delete real em `posts`; campo de
  texto livre em `moderation` que vire canal de recado (a `resolution` é
  lista fechada: `removido` | `ignorado`).

## Critérios de sucesso

1. Logado como o dono em `iter-mn.web.app/admin`, a fila mostra cada
   denúncia pendente com: motivo, data, o texto do post (ou do comentário),
   a foto quando houver, e nome/@apelido do autor do conteúdo.
2. Logado com qualquer outra conta Google, a página diz que a conta não tem
   acesso e nenhum dado é lido (verificável: `npm test` cobre a negação).
3. "Remover post" grava a lápide; o post some do feed do app no próximo
   refresh e a foto some do Storage.
4. "Apagar comentário" remove o comentário da thread no app.
5. "Ignorar" e "Remover" tiram a denúncia da fila pendente; o documento em
   `reports` permanece intacto; reabrir o painel não ressuscita a denúncia.
6. Denúncias múltiplas do mesmo alvo aparecem agrupadas (o id já carrega o
   alvo: `p_{postId}` / `c_{postId}_{commentId}`), e resolver o alvo dá
   baixa em todas.
7. `npm test` verde com os casos novos; `flutter test` intocado (nenhum
   arquivo do app muda).

## Custo

Hosting e Auth: cobertos pelo nível gratuito nesta escala. Firestore: a fila
é lida pelo admin, dezenas de documentos por sessão — centavos. Nenhuma
Function no v1. (O avisado em CLAUDE.md permanece: App Check + orçamento de
billing seguem pendentes e são anteriores a divulgar o app, não a este
painel.)

## Futuro deliberadamente fora do v1

- **Notificação de denúncia nova** (Function `onCreate` em `reports` → FCM
  para o dono). Hoje a fila só anda quando o painel abre.
- **Editar `norouterule` pelo painel** — hoje é escrita de console; com
  `isAdmin()` existindo, vira uma regra e um formulário.
- **Banir usuário**: não existe mecanismo sem servidor; excluir a conta pelo
  console já dispara a limpeza (`excluirConta`). Fica como está.
- **App Check**: quando for ativado (pendência conhecida), o Web App do
  painel precisa do provider reCAPTCHA registrado, ou o painel para de
  funcionar — anotar isso na tarefa do App Check.
- **Limpeza de subcoleções de post tombstonado** — já anotada em CLAUDE.md
  como economia de cota, não correção.

## Decisões (validadas em 2026-10-03)

1. **Conta admin: wesmark85@gmail.com.** A regra usa o uid dessa conta
   (console → Authentication → Users). Até o dono copiar o uid, a regra
   carrega o placeholder `COLOQUE_O_UID_DO_ADMIN_AQUI` — com ele no lugar,
   ninguém é admin e o painel inteiro é inerte, que é o lado seguro de
   falhar.
2. **Escopo do v1 confirmado**: fila + remover post + apagar comentário +
   ignorar. Fora: banir conta, editar `norouterule`, notificação push.
3. **Uid fixo na regra**, conforme a recomendação. O que isso significa:
   cada conta tem um identificador interno (uid) que não é senha e não dá
   acesso a nada; ele fica escrito no `firestore.rules`, que está no repo.
   Sem risco — o `list` de `posts` já entrega o uid de quem publica — e a
   alternativa (custom claim) exigiria uma service-account key, essa sim
   perigosa.
4. **`/admin` no mesmo site** de `privacidade` e `app-ads.txt`.
