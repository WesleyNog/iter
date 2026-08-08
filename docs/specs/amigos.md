# Spec: Amigos

Status: **implementada** · Criada, aprovada e implementada em 2026-08-07 ·
Convidar e aceitar verificados em aparelho no mesmo dia · Faltam os fluxos de
recusa, cancelamento, remoção e convite mútuo

## Objetivo

Transformar a aba Amigos (hoje `Center(child: Text('Amigos'))`, quarta aba da
`HomeScreen`) em três sub-telas alternadas por um seletor no topo — **Amigos**,
**Ranking** e **Feed** — entregando a primeira inteira e deixando as outras
duas visíveis e inertes.

Usuário: o entregador. Sucesso = ele digita o `@apelido` do colega que conheceu
no galpão, confere que é a pessoa certa, convida, e quando o outro aceita os
dois passam a se ver na lista.

### Por que esta é a primeira feature social do app

Duas coleções já fogem do `iter/{uid}`: `gastop`, onde qualquer autenticado lê
e escreve com a autoria carimbada (`updatedBy`/`uid` — o autor **fica**
registrado), e `nicknames`, que a busca por `@apelido` já usa. Ler dado de
terceiro não é novidade.

O que Amigos inaugura é outra coisa: **nome e rosto de outro usuário na tela**,
e a primeira regra que autoriza escrever no documento de um terceiro. Isso
puxa uma projeção pública de perfil e um consentimento que as regras precisam
sustentar sozinhas — não há Cloud Functions neste projeto, nem pasta
`functions/`, nem `cloud_functions` no `pubspec.yaml`.

Nenhuma query com `where`/`orderBy` nasce aqui. As três coleções novas são
lidas por id ou por subcoleção inteira, como todo o resto do app. A primeira
query com índice composto é o Feed, e ela vem depois.

## ⚠️ A armadilha desta feature: o perfil que ninguém lê está congelado

`user/{uid}` guarda `name` e `photoUrl` desde o primeiro login e **nunca os
reescreve** — `_createUserIfNeeded` faz `if (register.exists) return`
(`authService.dart:66`). Ninguém percebeu porque **nenhuma tela do app lê esses
campos**: a UI usa `widget.user.displayName` e `widget.user.photoURL`, do objeto
`User` do FirebaseAuth que o `AuthGate` entrega a cada sessão.

Dos doze campos de `user/{uid}`, só dois são lidos em algum lugar:
`activeVehicleId` (cinco pontos) e `nickName` (um). O resto está parado desde o
primeiro dia.

**A projeção se escreve a partir do `User` do Auth, nunca copiando o
documento.** E o gancho não pode ser o login: `signInWithGoogle()` só roda
quando a `LoginScreen` o chama, e quem já tem sessão cai direto na Home pelo
`AuthGate` sem passar por lá — que é exatamente a razão de o documento estar
congelado. **O gancho é a abertura do app**, no `AuthGate`, com `user.reload()`
antes de ler `displayName`/`photoURL` (o `User` em memória é cache).

Errar isso não dá bug visível: dá uma feature que simplesmente não funciona
para ninguém que já usa o app, porque quem não tem `profiles/{uid}` não existe
na busca.

## Layout

```
┌────────────────────────────────────────────┐
│  Olá, Wesley            🚗   ⏻              │  ← AppBar da Home (não muda)
├────────────────────────────────────────────┤
│  ┌──────────┬──────────┬──────────┐        │
│  │  Amigos  │ Ranking  │   Feed   │        │  ← SegmentedSelector<FriendsTab>
│  └──────────┴──────────┴──────────┘        │     trilho grey.shade100, r12
├────────────────────────────────────────────┤
│                                            │
│  CONVITES (2)                              │  ← só aparece se houver
│  ┌────────────────────────────────────┐    │
│  │ 👤  Maria Silva      ✓ Aceitar  ✕  │    │  ← toca → showProfileDialog
│  │     @maria.s7                      │    │
│  └────────────────────────────────────┘    │
│                                            │
│  MEUS AMIGOS (5)                           │
│  ┌────────────────────────────────────┐    │
│  │ 👤  João Pedro                  ›  │    │  ← toca → showProfileDialog
│  │     @joao.p3                       │    │
│  └────────────────────────────────────┘    │
│                                            │
├────────────────────────────────────────────┤
│   📊    📋    💰    👥②        ( + )        │  ← badge = nº de convites
└────────────────────────────────────────────┘
```

Vazio, sem nenhum amigo:

```
              👥
    Você ainda não tem amigos

  Peça o @apelido do colega e busque
        por ele para convidar.

      [  Adicionar amigo  ]
```

As duas abas inertes, no mesmo padrão do selo `Em breve` do menu `+`:

```
              🏆                          📣
        Ranking em breve            Feed em breve

  Quem fez mais rotas, quem       O que os entregadores
  termina mais rápido e quem      estão publicando.
  tem menos insucesso.
```

Busca (tela cheia, empurrada pelo menu `+`):

```
┌────────────────────────────────────────────┐
│  ‹  Adicionar amigo                        │
├────────────────────────────────────────────┤
│  @ [ maria.s7                    ] Buscar  │
│                                            │
│  ┌────────────────────────────────────┐    │
│  │ 👤  Maria Silva                    │    │  ← toca → showProfileDialog
│  │     @maria.s7                      │    │     com actionLabel dinâmico
│  └────────────────────────────────────┘    │
└────────────────────────────────────────────┘
```

## Dados

Três coleções novas nesta entrega: `profiles` (topo), `friends` e
`friendRequests` (indexadas por uid). O Feed acrescenta uma quarta, e está
esboçado em **Dívidas e fora de escopo** — as regras dele **não** sobem agora.

### `profiles/{uid}` — a vitrine

Exatamente o que o dialog de perfil mostra, e nada além disso. É a resposta à
pergunta "é essa a pessoa que eu quero adicionar?".

| campo | tipo | |
|---|---|---|
| `uid` | String | igual ao id do documento — a regra exige |
| `name` | String | `User.displayName` do Auth, **não** de `user/{uid}` |
| `nickName` | String? | conferido contra `nicknames/{apelido}` na regra |
| `photoUrl` | String? | `User.photoURL` do Auth |
| `updatedAt` | String | ISO 8601 |

**CPF, e-mail, telefone e data de nascimento não existem aqui — e isso é
regra, não convenção.** O `hasOnly` no `write` recusa qualquer chave fora da
lista, então nenhum `publish()` futuro consegue vazar um campo a mais por
descuido. É o único item das Fronteiras que uma regra sustenta sozinha.

### `profiles/{uid}/stats/all` — os números de carreira

Um `ProfileStats` serializado. A classe já existe em `Utils/profileStats.dart`
e já é o que o dialog consome; falta o `toMap`/`fromMap`.

| campo | tipo | |
|---|---|---|
| `routes` | int | rotas realizadas (`concluido` + `pago`) |
| `deliveredPackages` | int | pacotes menos insucessos |
| `stops` | int | |
| `failureRate` | double? | % sobre pacotes — **`null` = não dá para calcular** |
| `topCompanyLabel` | String? | de `topCompany.label` |
| `topCompanyShare` | double? | de `topCompany.share`, em % |
| `averageMinutes` | int? | de `averageDuration`; `null` sem hora de fim |
| `updatedAt` | String | ISO 8601 |

A travessia **não é simétrica** e é de propósito: `topCompany` é um record
`({label, share})` que vira dois campos, `averageDuration` é `Duration` que vira
minutos, e `updatedAt` é carimbado pelo `ProfileController` na escrita, fora do
`toMap()` — mexer no construtor de `ProfileStats`, que tem teste e cinco usos,
não vale o preço da simetria.

**`null` nunca vira zero na travessia.** O comentário de `ProfileStats` diz que
"taxa de insucesso 0%" e "ninguém preencheu pacotes" são coisas diferentes;
gravar `0` apagaria essa distinção justamente onde ela fica pública.

### `profiles/{uid}/stats/{yyyy-MM}` — o balde do mês (Ranking)

| campo | tipo | |
|---|---|---|
| `routes` | int | realizadas no mês |
| `packages` | int | só de rotas com `packages > 0` |
| `failures` | int | `failuresOf` somado, mesma população de `packages` |
| `timedRoutes` | int | quantas têm `endAt` |
| `totalMinutes` | int | soma das durações dessas |
| `timedPackages` | int | pacotes das rotas que têm `endAt` **e** `packages > 0` |
| `updatedAt` | String | ISO 8601 |

**Numerador e denominador, nunca a taxa.** `1 insucesso em 8 pacotes` e `125 em
1000` dão a mesma porcentagem e não são o mesmo problema — é a mesma razão de
`FailureRate` carregar os dois números em vez do quociente.

`timedPackages` existe porque `packages` e `totalMinutes` contam **populações
diferentes**: um é sobre rotas com pacotes informados, o outro sobre rotas com
hora de fim. Sem um terceiro campo que cruze os dois, "minutos por pacote" —
que é o único jeito justo de comparar quem pega rota de 200 pacotes com quem
pega de 30 — seria incomputável, e o ranking de velocidade premiaria a rota
pequena. Guardar o campo agora custa um int e evita migrar documento depois.

**O balde é recalculado, nunca incrementado.** `FieldValue.increment` derivaria
no dia em que uma rota é editada ou apagada, e um número público que discorda da
origem sem ninguém conseguir auditar é pior do que número nenhum. O cliente já
tem a lista inteira de rotas em memória, então recalcular custa uma passada.

Isto **não** contradiz o pilar do custo congelado. Aquele pilar é sobre
dinheiro: a provisão é um valor em reais que não pode ser reescrito por uma
tarifa de hoje. Este balde é contagem derivada das próprias rotas — ele *tem*
que concordar com a origem, e recalcular é como ele consegue.

### `friendRequests/{uid}/incoming/{otherUid}` e `.../outgoing/{otherUid}`

O par de convites. **O id do documento é o dado**: quem convidou e quem foi
convidado estão nos caminhos, não no corpo.

```
friendRequests/{uid}/incoming/{otherUid}   ← convites que me mandaram
friendRequests/{uid}/outgoing/{otherUid}   ← convites que eu mandei
  at: Timestamp   ← serverTimestamp(), conferido contra request.time
```

`A` convida `B` num `WriteBatch` só, escrito por `A`: cria
`friendRequests/B/incoming/A` **e** `friendRequests/A/outgoing/B`. As duas
pontas existem porque `A` precisa ver o que enviou (só o dono lê a própria
caixa) e porque o marcador `outgoing` é o que prova o consentimento de `A` na
hora do aceite.

**Convite mútuo cria quatro marcadores.** Se `A` convida `B` e `B` convida `A`
antes de qualquer aceite, existem `A/outgoing/B`, `B/incoming/A`, `B/outgoing/A`
e `A/incoming/B`. O aceite apaga **os quatro** — apagar só o par que ele
consultou deixaria o outro vendo convite pendente de quem já é amigo, e um
segundo toque em "Aceitar" bateria em documento existente.

### `friends/{uid}/list/{friendUid}`

```
friends/{uid}/list/{friendUid}
  at: Timestamp   ← serverTimestamp(), conferido contra request.time
```

O id do documento é o amigo. Nome, foto e apelido vêm de `profiles/{friendUid}`,
sempre — metade dessas arestas é escrita pela outra pessoa.

**`at` é `serverTimestamp()` e a regra confere `at == request.time`**, saindo do
padrão ISO-string do resto do app de propósito: é o campo que ordena a lista
**do outro**, escrito por ele. Sem a conferência, um convidado se fixa no topo
da minha lista para sempre com `at: '9999-12-31'`. Ordenar por dado do
adversário é o tipo de coisa que só aparece quando alguém quer.

Aceitar é um `WriteBatch` escrito por `B`: cria `friends/B/list/A`, cria
`friends/A/list/B`, apaga os até quatro marcadores. Recusar apaga o par.
Desfazer apaga as duas arestas e qualquer marcador remanescente — senão um
marcador vivo autoriza recriar a aresta depois do desfazer.

O `existsAfter` prende só a **criação** das duas arestas, não a remoção: quem
desfizer pela API pode apagar só o próprio lado e deixar o outro ainda vendo a
amizade. Fica assim de propósito — o estrago é cosmético, o outro remove
sozinho quando quiser, e amarrar o `delete` também acrescentaria um modo de
falha a um caminho que não tem consentimento em jogo.

### `firestore.rules`

```
// A vitrine pública.
//
// `get` e não `read`: `read` é `get` + `list`, e `list` numa condição que não
// olha `resource` autoriza baixar a coleção inteira. Toda leitura desta
// feature é por id conhecido (`nicknames/{apelido}` → uid → `profiles/{uid}`),
// então `list` não tem consumidor e fica fechado.
match /profiles/{uid} {
  allow get: if request.auth != null;
  allow list: if false;

  // `hasOnly` é o que impede CPF de vazar por descuido de um `publish()`
  // futuro, e o `get` no apelido é o que impede alguém de aparecer como
  // @outrapessoa na lista de amigos alheia.
  allow write: if request.auth != null
               && request.auth.uid == uid
               && request.resource.data.keys().hasOnly(
                    ['uid', 'name', 'nickName', 'photoUrl', 'updatedAt'])
               && request.resource.data.uid == uid
               && request.resource.data.name is string
               && request.resource.data.name.size() <= 80
               && (request.resource.data.nickName == null
                   || get(/databases/$(database)/documents/nicknames/$(request.resource.data.nickName)).data.uid == uid);

  match /stats/{bucket} {
    allow get: if request.auth != null;
    allow list: if false;
    // `all` ou `2026-08`: sem isso o wildcard é depósito livre na cota.
    allow write: if request.auth != null
                 && request.auth.uid == uid
                 && (bucket == 'all'
                     || bucket.matches('^[0-9]{4}-[0-9]{2}$'));
  }
}

// Convites. `read` aqui inclui `list` de propósito — a coleção já está sob o
// uid do dono, então listar só devolve a própria caixa.
match /friendRequests/{uid}/incoming/{otherUid} {
  allow read: if request.auth != null && request.auth.uid == uid;

  // Só quem envia cria o próprio convite na caixa alheia. Ninguém forja um
  // convite "de" outra pessoa — é essa impossibilidade que sustenta a regra
  // de `friends` lá embaixo.
  //
  // Os **dois** perfis têm de existir. O de quem recebe impede convidar um
  // uid inventado; o de quem envia é o que garante que dá para saber quem
  // convidou — sem ele o convite chega como "Entregador", e aceitar ou
  // recusar sem saber de quem é não é decisão, é chute.
  allow create: if request.auth != null
                && request.auth.uid == otherUid
                && otherUid != uid
                && exists(/databases/$(database)/documents/profiles/$(uid))
                && exists(/databases/$(database)/documents/profiles/$(otherUid))
                && request.resource.data.keys().hasOnly(['at'])
                && request.resource.data.at == request.time;

  // Os dois lados apagam: o dono recusa, quem enviou retira. A condição não
  // toca em `resource`, então apagar marcador inexistente passa — é o que
  // deixa o aceite apagar os quatro caminhos sem saber quais existem.
  allow delete: if request.auth != null
                && (request.auth.uid == uid || request.auth.uid == otherUid);
  allow update: if false;
}

match /friendRequests/{uid}/outgoing/{otherUid} {
  allow read: if request.auth != null && request.auth.uid == uid;
  allow create: if request.auth != null
                && request.auth.uid == uid
                && otherUid != uid
                && exists(/databases/$(database)/documents/profiles/$(uid))
                && exists(/databases/$(database)/documents/profiles/$(otherUid))
                && request.resource.data.keys().hasOnly(['at'])
                && request.resource.data.at == request.time;
  allow delete: if request.auth != null
                && (request.auth.uid == uid || request.auth.uid == otherUid);
  allow update: if false;
}

// A aresta de amizade.
match /friends/{uid}/list/{friendUid} {
  allow read: if request.auth != null && request.auth.uid == uid;

  // `create, update` com a MESMA condição: a escrita é idempotente. Sem isso,
  // reparar uma amizade meio gravada bateria em `update: if false`, porque
  // `set` sobre documento existente é update.
  allow create, update: if request.auth != null
    && friendUid != uid
    && request.resource.data.keys().hasOnly(['at'])
    && request.resource.data.at == request.time
    // As duas arestas nascem no mesmo commit, ou nenhuma nasce.
    && existsAfter(/databases/$(database)/documents/friends/$(friendUid)/list/$(uid))
    && (
         // aceito o que me mandaram: escrevo na minha lista
         (request.auth.uid == uid
          && exists(/databases/$(database)/documents/friendRequests/$(uid)/incoming/$(friendUid)))
         // aceito o que me mandaram: me insiro na lista de quem convidou
      || (request.auth.uid == friendUid
          && exists(/databases/$(database)/documents/friendRequests/$(uid)/outgoing/$(friendUid)))
    );

  allow delete: if request.auth != null
                && (request.auth.uid == uid || request.auth.uid == friendUid);
}
```

**A propriedade que essas regras garantem** é uma só, e vale enunciá-la: *uma
aresta `X → Y` só nasce se o par trocou um convite na direção que a justifica,
e nunca sozinha.* Os dois ataques óbvios morrem no `exists`:

- **Me adicionar à lista de alguém.** Precisaria de
  `friendRequests/{vítima}/outgoing/{eu}`, que só a vítima cria.
- **Adicionar alguém à minha lista sem ele aceitar.** Precisaria de
  `friendRequests/{eu}/incoming/{vítima}`, que só a vítima cria.

O `friendUid != uid` é redundante — a auto-amizade já morre no `otherUid != uid`
das regras de convite. Fica escrito assim mesmo: um invariante que depende de
um guard duas matches acima é um invariante que some na primeira mexida.

**`existsAfter` é o que resolve a meia amizade**, e é o motivo de a regra não
precisar de Cloud Functions para ser atômica entre documentos: ela enxerga o
estado *depois* do batch e *antes* do commit, então cada aresta exige a irmã no
mesmo commit e as duas se satisfazem mutuamente. `exists`/`get`, ao contrário,
avaliam o estado **anterior** ao commit — é por isso que o aceite consegue
consultar um marcador que o mesmo batch está apagando. Cada uma dessas chamadas
é cobrada como leitura, inclusive quando a regra nega; o batch de aceite usa 4
das 20 permitidas.

**Risco assumido, registrado:** quem souber o seu `@apelido` exato vê seu nome,
sua foto, quantas rotas você fez e sua taxa de insucesso. É deliberado — o
dialog de confirmação roda **antes** de existir amizade, e não há como
mostrá-lo com leitura restrita a amigos. Com `list` fechado, "saber o apelido
exato" é mesmo o custo de entrada: não há busca por prefixo, não há busca por
nome, e o apelido é gerado com sufixo aleatório.

**Isso vale enquanto o Feed não existir, e o motivo não é o que parece.** Não é
o `nickName` num mural global — esse já saiu do desenho do post. É o `uid`:
qualquer coleção global com `list` aberto entrega os uids de quem publicou, e
`profiles/{uid}` é `get` liberado. O custo de entrada deixa de ser "saber o
apelido" e passa a ser "abrir o feed". Está desenvolvido em **O Feed, em
esboço**, e é decisão a tomar antes da primeira linha daquela aba.

**O que as regras não fazem.** Não há rate limit e não há moderação de
conteúdo: isso é servidor. Mas **bloquear uma pessoa é expressável em regra** e
não está nesta entrega — hoje quem for recusado reconvida indefinidamente,
acendendo o badge toda vez. Está em Dívidas com o desenho pronto, e não é
dívida de servidor: é escopo que ficou de fora.

### Um buraco que já existe hoje

`match /nicknames/{nickname}` tem `allow read: if request.auth != null`
(`firestore.rules:72`), e `read` inclui `list`. Uma conta qualquer roda
`collection('nicknames').get()` e leva o mapa completo `apelido → uid` da base
inteira.

Nenhum código do app precisa disso: `resolveUid` e `isAvailable` fazem
`docFor(x).get()`, leitura por id. **Trocar por `allow get` não quebra nada** e
fecha a porta antes de `profiles` a tornar rentável — sem os apelidos, saber o
uid de alguém deixa de ser um dump e volta a ser um a um.

Vai junto nesta entrega. É uma linha.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1. `cloud_firestore 6.7.1`, `firebase_auth 6.5.6`.
`setState` puro, sem pacote de estado.

**Nenhuma dependência nova no app.** O Feed vai querer `firebase_storage` e o
anúncio vai querer `google_mobile_ads` — os dois ficam para as entregas
seguintes, e os dois são "perguntar antes".

Os testes de regra são um projeto Node **isolado** em `firestore-tests/`:
`@firebase/rules-unit-testing` mais o runner nativo do Node 22, nada no
`pubspec.yaml`. Fica fora de `test/` porque o `flutter test` varre aquele
diretório atrás de `*_test.dart` e passaria por dentro do `node_modules` a
cada rodada.

## Comandos

```bash
flutter pub get
flutter analyze lib/
flutter test
flutter test test/unit/friendship_test.dart

cd firestore-tests && npm test      # regras, contra o emulador

firebase deploy --only firestore:rules --project iter-mn   # antes da tela
```

O `--project` não é opcional: não existe `.firebaserc`. E o emulador exige
**Java 21+** enquanto o build Android usa 17 — `firestore-tests/run.sh` aponta
o JDK só para aquele comando, sem trocar o java do sistema.

## Estrutura

```
firestore.rules                           → + profiles, friends, friendRequests
firestore-tests/                          → regras no emulador, projeto Node
                                            isolado (novo)
lib/model/publicProfile.dart              → PublicProfile (novo)
lib/controller/profileController.dart     → profiles/{uid} e stats/* (novo)
lib/controller/friendController.dart      → friends + friendRequests (novo)
lib/Utils/friendship.dart                 → FriendshipStatus e a regra (novo)
lib/Utils/monthStats.dart                 → o balde do mês (novo)
lib/Utils/profileStats.dart               → + toMap/fromMap
lib/widget/segmentedSelector.dart         → o trilho, generalizado (novo)
lib/widget/companyFilter.dart             → passa a usar o genérico
lib/widget/profileDialog.dart             → onAction opcional, rótulo repintável
lib/widget/friendTile.dart                → linha de amigo e de convite (novo)
lib/screens/friendsScreen.dart            → seletor + 3 sub-telas, no lugar do stub
lib/screens/addFriend.dart                → busca por @apelido (novo)
lib/screens/home.dart                     → publica a projeção, + item no menu,
                                            user na aba, badge
```

## Estilo de código

O seletor sai de dentro do `CompanyFilter` em vez de ser copiado dele. O
`polimento-glass.md` já registrou o que copiar superfície custa: quatro
widgets, três opacidades diferentes, e polir um só criava a quinta variante.

```dart
/// Trilho segmentado — o mesmo do filtro da lista, agora sem saber de empresa.
class SegmentedSelector<T> extends StatelessWidget {
  const SegmentedSelector({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<SegmentOption<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  // Container 42 / grey.shade100 / r12, pílula branca r9 + sombra 8%,
  // AnimatedContainer 150ms, Opacity 0.45 no inativo, tudo Expanded.
  // Rótulo de texto: fontSize 13, maxLines 1, ellipsis.
}
```

`CompanyFilter` vira casca fina por cima dele. Duas amarras do teste que já
existe: as `ValueKey('filtro-…')` moram no widget tocável
(`HitTestBehavior.opaque`, dentro do `Tooltip`), e o teste **conta os
`Opacity` da árvore inteira** — exatamente um por segmento, nenhum fora deles,
e nada de `AnimatedOpacity`.

## Estados

### Da `FriendsScreen`

A tela abre três streams (`watchFriends`, `watchIncoming`, `watchOutgoing`), e
o primeiro modo de falha desta entrega é `permission-denied` por regra não
publicada.

1. **Carregando** — `CircularProgressIndicator` centralizado, sob o seletor,
   que continua visível.
2. **Erro** — mensagem amigável; em `kDebugMode`, o erro real. Sempre
   `debugPrint`, **porque falha de regra do Firestore já sumiu silenciosamente
   neste projeto antes**. A falha de um stream esconde só a seção dele: convite
   quebrado não pode apagar a lista de amigos.
3. **Vazia** — o estado desenhado acima, com o botão que abre a busca.
4. **Com dados** — convites acima, amigos abaixo. A lista de convites é
   filtrada contra a de amigos: marcador que sobrou não vira convite na tela.

### Do resultado da busca

Dez, e a lista é o que o botão do dialog precisa dizer:

1. **Campo vazio** — nada acontece, botão de buscar inerte.
2. **Apelido inválido** — fora de `^[a-z0-9._-]{3,20}$` depois de normalizar.
   Não vai à rede.
3. **Não encontrado** — "Ninguém usa esse apelido."
4. **Perfil ainda não publicado** — o apelido existe, `profiles/{uid}` não.
   É o estado **normal** de todo usuário anterior a esta entrega que ainda não
   reabriu o app. "Peça para o colega abrir o app", ação inerte. Dizer "ninguém
   usa esse apelido" aqui seria mentir.
5. **Sou eu** — abre o perfil com a ação desabilitada: "Esse é você".
6. **Já é meu amigo** — ação "Remover amigo".
7. **Eu já convidei** — ação "Cancelar convite".
8. **Ele me convidou** — ação "Aceitar convite".
9. **Sem relação** — ação "Adicionar".
10. **Falha ao buscar** — "Não foi possível buscar agora." Sem rede,
    `permission-denied` e apelido inexistente são **coisas diferentes**;
    colapsar os três num "não encontrado" é a mesma mentira do sol desenhado
    quando a API do clima caía.

Falha ao convidar ou aceitar não muda o rótulo do botão: `showNotification`
com `type: 'error'` e o estado volta ao que era.

**A entrada é normalizada antes de buscar.** Nem `resolveUid` nem `isAvailable`
normalizam — `normalize()` hoje só roda em `suggestFrom` e `change`. Digitar
`Maria.S7` bateria em `nicknames/Maria.S7`, que não existe, e a busca diria
"ninguém usa esse apelido" para um apelido que existe. `normalize()` e depois
`isValid()`, antes da rede.

## Estratégia de teste

`test/unit/friendship_test.dart` — a função pura que decide o botão:

- os dez estados saem de `(souEu, temPerfil, éAmigo, convieiEle, eleMeConvidou)`;
- amizade vence convite pendente: marcador não apagado não faz o botão voltar
  a "Aceitar";
- convite mútuo resolve para "Aceitar", não para dois estados ao mesmo tempo.

`test/unit/publicProfile_test.dart` — a travessia da projeção:

- `toMap`/`fromMap` ida e volta preservam nome, apelido e foto;
- `failureRate` e `averageMinutes` ausentes voltam `null`, **nunca zero**;
- `topCompany` vira dois campos e volta a ser um record;
- documento sem `stats` vira zeros com `null` nas taxas — "conta nova" e "não
  dá para calcular" são coisas diferentes.

`test/widget/segmentedSelector_test.dart`:

- os três segmentos têm a **mesma largura entre si** — comparar os três `Size`,
  não fração da tela: o trilho tem `padding: 4` e cada segmento `margin: 2`, e
  um terço exato nasceria vermelho;
- tocar num segmento dispara `onChanged` com o valor daquele segmento;
- só o selecionado está em opacidade cheia.

Testar a *causa*, não o sintoma: nada de asserção sobre "o texto cabe". A fonte
do teste é quadrada — 14,25 px por caractere em `fontSize: 14` — e "Ranking"
(7 caracteres) mediria 99,75 px no teste contra ~50 no aparelho. O caso do
`SegmentedButton` com "Substituição", que passou em três testes de largura e
quebrou linha no iPhone, está em `manutencao.md` e em
`test/widget/addMaintenance_test.dart`. Quem responde é o aparelho, e está nos
critérios de sucesso.

`test/unit/friendController_test.dart` — o que é puro num controller que
quase todo faz rede:

- a ordem da lista é a mais recente primeiro, desempatando pelo uid;
- convite de quem já é amigo sai da caixa de convites;
- os **caminhos** das coleções, que são onde a segurança mora — a regra casa
  `friends/{uid}/list/{friendId}`, e trocar um nome aqui quebraria a
  autorização em silêncio.

`test/widget/friendTile_test.dart`:

- com perfil, nome e `@apelido`;
- sem projeção publicada, o `@apelido` vira o título — nunca linha em branco;
- a inicial do avatar ignora o `@`, senão todo mundo sem perfil teria a mesma;
- nome comprido corta com reticências em vez de quebrar.

`test/widget/addFriend_test.dart` — só os casos que **não** chegam à rede, e é
justamente o ponto: são eles que decidem se a rede é chamada. Se um deles
vazasse para o Firestore, o teste estouraria com Firebase não inicializado, o
que torna a asserção real:

- campo vazio não busca e não reclama;
- apelido curto, longo ou que normaliza para vazio não vai à rede;
- corrigir a entrada limpa a mensagem anterior;
- o campo tem `@` e busca no Enter.

**`friendsScreen_test.dart` não entra, e não é esquecimento.** A tela recebe um
`User` do FirebaseAuth e abre dois `snapshots()`; subir isso exigiria
`firebase_auth_mocks` e `fake_cloud_firestore`, que seriam as primeiras
dependências de teste do projeto — e dependência nova é "perguntar antes". O
que dava para extrair já foi: a decisão de qual convite é convite virou
`pendingOnly`, e a linha virou `FriendTile`, e as duas têm teste. O resto da
tela é verificação em aparelho.

`firestore-tests/rules.test.mjs` — **as regras, contra o emulador**. Trinta
casos, e é o único lugar onde a segurança desta feature é verificada de
verdade:

- perfil e carreira são legíveis por id, e a coleção **não** é listável — nem
  `profiles`, nem `nicknames`;
- `user/{outro}`, onde mora o CPF, continua fechado;
- `hasOnly` recusa CPF na projeção, e publicar com apelido alheio é negado;
- ninguém forja convite "de" outra pessoa, nem convida quem não tem perfil,
  nem carimba o convite com hora escolhida a dedo;
- **criar só uma das arestas é negado**, e o batch com as duas passa — o
  `existsAfter`, que é o trecho de maior risco do desenho;
- convite fantasma não basta: o marcador tem de ser do par certo;
- ninguém mexe na amizade de dois terceiros.

O simulador do console foi removido pelo Google, e ele não testava batch de
qualquer forma — que é justamente onde o `existsAfter` vive. O emulador testa,
e por isso a dívida "teste de regras" saiu da lista: virou `npm test`.

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; texto em pt-BR; contas em `Utils/`,
  nunca no `build`; `null` para "não dá para calcular"; publicar a regra antes
  de testar a tela; nome e foto de terceiro sempre de `profiles/{uid}`.
- **Perguntar antes:** qualquer dependência nova; mexer na `AppBar` da Home ou
  na `GlassNavBar` em si; afrouxar a regra de `user/{uid}`; ligar o Blaze.
- **Nunca:** gravar CPF, e-mail, telefone ou data de nascimento em `profiles`;
  incrementar o balde do mês em vez de recalculá-lo; colapsar `null` em `0` na
  travessia; usar `allow read` onde o app só lê por id.

## Critérios de sucesso

- [x] Buscar um `@apelido` que existe abre o dialog com nome, foto e números.
- [ ] Buscar `Maria.S7` acha `maria.s7` — a entrada é normalizada.
- [ ] Buscar um apelido inexistente diz isso, e não fica carregando.
- [ ] Apelido que existe sem `profiles/{uid}` diz "peça para o colega abrir o
      app", não "ninguém usa esse apelido".
- [ ] Modo avião: a busca diz "não foi possível buscar agora".
- [ ] Buscar o próprio apelido mostra o perfil com o botão **desabilitado**.
- [x] Convidar move o estado para "Convite enviado" sem sair da tela.
- [x] A outra conta vê o convite na aba Amigos e o badge ① na navBar.
- [x] Aceitar faz os dois aparecerem na lista um do outro.
- [ ] Os dois se convidam antes de qualquer aceite; um aceita; nenhum dos dois
      fica com convite pendente e nenhum vê erro.
- [ ] Recusar some com o convite nos dois lados.
- [ ] Cancelar um convite enviado some com ele na caixa do outro.
- [ ] Remover um amigo tira a aresta dos dois lados.
- [ ] Tocar em Ranking e em Feed mostra o aviso "Em breve", não tela branca.
- [x] No iPhone, "Amigos", "Ranking" e "Feed" cabem em uma linha cada.
- [x] Os quatro ataques dão `permission-denied` — verificado no emulador,
      `firestore-tests`, junto com outros 26 casos.
- [x] Abrir o app com sessão restaurada publica/atualiza `profiles/{uid}`.
- [ ] Trocar a foto do Google e reabrir o app atualiza a foto na busca.
- [ ] Cadastrar uma rota e reabrir o dialog na outra conta mostra o número novo.
- [x] `flutter analyze lib/` sem error/warning novo.
- [x] Os 639 testes que já existem continuam passando.

## Decisões

**1. A projeção pública é um documento novo, não uma regra afrouxada.**
`user/{uid}` tem CPF, e-mail, telefone e data de nascimento. Abrir `read` nele
é inaceitável, e nenhum consumidor atual lê esses campos — `profiles/{uid}` é
puramente aditivo e não toca em nenhum dos seis pontos que leem o perfil hoje.

**2. A projeção se escreve do `User` do Auth, na abertura do app.** Do `User`
porque `user/{uid}` está congelado desde o primeiro login; na abertura porque o
login não roda para quem já tem sessão — que é a causa do congelamento. O
backfill de quem já existe acontece sozinho na próxima abertura.

O gancho ficou no `initState` da `HomeScreen`, não no `AuthGate`: o gate é um
`StatelessWidget` com `StreamBuilder`, e publicar de dentro do `build` seria
escrita em rebuild. A `HomeScreen` monta uma vez por sessão, já recebe o `User`
e é onde o CLAUDE.md manda pendurar o que roda uma vez só.

**3. `get`, não `read`.** `read` é `get` + `list`, e uma condição que não olha
`resource` autoriza baixar a coleção inteira. Toda leitura desta feature é por
id conhecido. O mesmo conserto vai em `nicknames`, que está aberto hoje sem
nenhum consumidor de `list`.

**4. O conteúdo público é exatamente o do dialog de perfil.** Aquele dialog
**é** a tela de "é essa a pessoa?", e foi escrito recebendo tudo por parâmetro
justamente para isso. Mostrar menos ali seria pedir confirmação no escuro.

**5. Convite tem dois documentos, não um.** Um só deixaria uma das pontas sem
poder ler ou sem poder escrever — regras não fazem query, só `get`/`exists` em
caminho conhecido. Com `incoming` e `outgoing`, cada um lê a própria caixa e o
`outgoing` vira a prova de consentimento que a regra de `friends` consulta.

**6. A identidade mora no id do documento, não no corpo.** Mesma técnica de
`nicknames/{apelido}`: a regra decide olhando o caminho. Corpo é dado; caminho
é fato. O único campo do corpo é `at`, e a regra o prende a `request.time`.

**7. Amizade é bilateral, explícita e atômica.** Duas arestas, uma em cada
lista, criadas no mesmo commit por força do `existsAfter`. Uma aresta só faria
o Ranking de um lado enxergar o outro sem reciprocidade.

**8. `create, update` com a mesma condição.** A escrita da aresta é idempotente
de propósito: `set` sobre documento existente é `update`, e um `update: if
false` transformaria qualquer reparo em `permission-denied` permanente.

**9. O balde mensal é recalculado.** `increment` derivaria na primeira edição
de rota. E `publish` recalcula os últimos 12 meses na mesma passada, senão o
Ranking nasce zerado para todo mês anterior ao lançamento do gancho.

**10. O Ranking inclui o próprio usuário, e do mesmo lugar que os amigos.**
A linha do dono sai do balde publicado, não das rotas locais — abrir a aba
republica o balde antes de montar a lista. Duas fontes para o mesmo número é a
armadilha que `VehicleController.activeFrom()` existe para evitar: a tela
desenharia um carro enquanto a conta usava outro.

**11. O seletor é o `CompanyFilter` generalizado, não uma cópia.** Já existe o
precedente registrado no `polimento-glass.md`.

**12. Ranking e Feed nascem como abas visíveis e inertes.** Mesmo raciocínio
que o menu `+` usou quando nasceu — as três entradas de uma vez, as futuras com
o selo que `CreateAction.comingSoon` desenha.

## Riscos

| Risco | Mitigação |
|---|---|
| Regra errada expõe dado de terceiro | `firestore-tests/npm test` — 30 casos contra o emulador, incluindo o batch do aceite, que nenhum teste manual alcança |
| `list` aberto enumera a base inteira | `allow get` + `allow list: if false`; vale também para `nicknames`, aberto hoje |
| Regras não publicadas na hora de testar | Está nos Comandos e é a **primeira** tarefa; foi o que travou a tarefa 13 do veículo |
| Aceite grava meia amizade | `existsAfter` exige a aresta espelho no mesmo commit |
| Convite mútuo deixa marcador órfão | O aceite apaga os quatro caminhos; `create, update` na mesma condição torna a escrita idempotente |
| Projeção nunca publicada para quem não desloga | O gancho é o `AuthGate`, não o `signInWithGoogle` |
| Perfil forjado com apelido alheio | A regra confere `nicknames/{apelido}.uid == uid` |
| CPF vazando pela projeção | `hasOnly` na regra — o "Nunca" vira invariante |
| Login anônimo transformaria "autenticado" em "qualquer um" | Conferir no console que só Google está habilitado, antes de publicar |
| Rótulo de texto no seletor quebra linha | Verificação em aparelho; o teste mede larguras iguais, não se o texto cabe |
| N leituras de perfil por rolagem | Um prefetch para um `Map<String, PublicProfile>` no state, nunca leitura por tile |

## Dívidas e fora de escopo

> **O projeto migrou para o Blaze em 07/08/2026**, por causa do Storage. As
> três dívidas abaixo foram reescritas: o que era "impossível sem servidor"
> agora é "possível, e custa dinheiro por uso". Nada do que já foi entregue
> muda — regra continua sendo a defesa mais barata e a única que vale mesmo
> quando há servidor.

- **Ranking (aba 2)** — o balde já está modelado e `publish` já o grava; falta
  a tela. **O defeito que era bloqueio deixou de ser:** com Cloud Functions o
  agregado pode ser escrito por trigger em `iter/{uid}/routes`, e aí o cliente
  perde o `write` em `profiles/{uid}/stats/*` — o número deixa de ser
  forjável. O caminho tem uma armadilha de custo que precisa entrar na conta
  antes de escrever a primeira linha: uma trigger por rota gravada recalcula
  lendo a coleção inteira do usuário, e a leitura é cobrada. Para quem tem 400
  rotas, cada salvamento vira 400 leituras. As saídas são manter o recálculo no
  cliente (que já tem tudo em memória, de graça) e usar a Function só para
  **assinar** o resultado, ou aceitar `increment` na trigger — que é o que a
  Decisão 9 recusa, com razão, no cliente, e que no servidor volta a ser
  defensável porque a trigger vê o `before` e o `after` do documento.
  Independente disso, o Ranking **não terá o filtro de intervalo livre** do
  resto do app: com balde mensal, as opções são mês corrente, meses anteriores
  e carreira.
- **Feed (aba 3)** — tem esboço próprio logo abaixo, em **O Feed, em esboço**.
- **Anúncios entre posts** — a monetização. Reservar o slot no builder do feed
  desde o primeiro dia (um a cada N posts) e ligar o AdMob depois.
  `google_mobile_ads` é dependência nova, quer `APPLICATION_ID` no
  `AndroidManifest.xml`, `NSUserTrackingUsageDescription` e o fluxo de ATT no
  iOS — e o `release` do Android ainda assina com a chave de debug, então não
  há build publicável hoje de qualquer forma. O Blaze não muda nada aqui.
- **Bloquear uma pessoa** — escopo que ficou de fora, e continua cabendo numa
  regra mesmo com servidor disponível: `blocks/{uid}/list/{otherUid}` legível e
  gravável só pelo dono, e `&& !exists(.../blocks/$(uid)/list/$(request.auth.uid))`
  no `create` do convite. Sem isso, quem for recusado reconvida para sempre. A
  lista fica invisível para o bloqueado — o `create` dele só falha. Regra é
  mais barata que Function e não tem cold start; não troque uma pela outra só
  porque agora dá.
- **Moderação e denúncia de conteúdo** — passa a ser possível: uma Function
  que recebe denúncia, esconde o post e notifica. Continua sendo trabalho de
  verdade, e continua sendo **pré-requisito** para abrir o feed a
  desconhecidos.
- **Notificação de convite** — `firebase_messaging` mais uma Function que
  dispara no `create` de `friendRequests/{uid}/incoming`. Hoje o badge só
  acende com o app aberto.
- **Vigiar o custo** — o Blaze cobra por uso acima da cota gratuita, e o risco
  real não é o feed: é uma Function em laço (uma trigger que escreve no
  documento que a dispara). Antes da primeira Function, ligar orçamento e
  alerta de faturamento no console.
- **Apagar a conta** — não existe fluxo hoje, e passa a deixar rastro: arestas
  de amizade em listas alheias e uma projeção pública órfã. O `FriendTile`
  desenha `@apelido` e inicial genérica quando `profiles/{friendUid}` falta, em
  vez de linha em branco.
- **UI para trocar o próprio apelido** — `NicknameController.change()` existe e
  nunca foi ligado a uma tela. Passa a incomodar agora: para alguém te achar,
  você precisa saber e conseguir passar o seu apelido. O dialog de perfil já
  mostra `@apelido` e já tem um botão de ação livre — "Compartilhar" ali
  resolve o mínimo sem abrir a discussão de troca.
- **Busca por nome** — fora de escopo por pedido explícito.

## O Feed, em esboço

Não é esta entrega. Está aqui para a modelagem de `posts` não nascer sem lugar
para curtida e comentário — acrescentar subcoleção depois é barato, mudar o
documento que já tem mil linhas gravadas não é.

```
posts/{postId}                       ← global
  uid, text, company, imagePath, createdAt, deleted
  posts/{postId}/likes/{uid}         ← uma curtida = um documento
    uid, at
  posts/{postId}/comments/{id}
    uid, text, createdAt

iter/{uid}/posts/{postId}            ← espelho do dono, mesmo id
```

O espelho é o par que `StationController.report()` já faz com `gastop` +
`precos`, gravado no mesmo `WriteBatch`, e é o que resolve "minhas postagens"
sem query nem índice na coleção global. Ele precisa de regra própria em
`iter/{userId}/posts/{postId}`, senão o batch inteiro é negado e o post nem
publica.

**A imagem vai para o Storage**, e a subcoleção `posts/{id}/media/image` que
uma versão anterior propunha sai do desenho: era contorno para o base64, e o
contorno perdeu a razão quando o projeto foi para o Blaze. Some junto a
aritmética toda — 1 MiB por documento, 33% de inflação, `WriteBatch` de 10 MiB.

### O post guarda o caminho, não a URL

`imagePath: 'posts/{uid}/{postId}.jpg'`, e o cliente resolve a URL por sessão.
Guardar o retorno de `getDownloadURL()` seria mais simples e está errado por
dois motivos.

**Aquela URL não passa pelas Storage Rules.** Ela carrega um token aleatório e
é servida sem autenticação: é pública, permanente, funciona deslogado e fora do
app, e revogar exige rodar o token à mão no console. As regras controlam quem
consegue *obter* a URL, não quem consegue *usá-la* — e com `list` aberto em
`posts`, um `collection('posts').get()` colhe as de todo mundo de uma vez.

O caminho devolve às `storage.rules` o papel de porteiro. De quebra é o maior
campo do documento: a URL tokenizada tem ~190 bytes, o caminho ~55.

### Correção: o autor não é denormalizado

Uma versão anterior guardava `nickName`, `name` e `photoUrl` dentro do post.
**Sai.** A regra não tem como conferir esses campos contra `profiles`, então
qualquer um publicaria assinando com o apelido de outra pessoa — num mural
global, personificação de graça. E contradizia a própria Fronteira desta spec:
*nome e foto de terceiro sempre de `profiles/{uid}`*.

O post guarda só `uid`. A tela faz **um** prefetch de perfis para um `Map`,
exatamente como a `FriendsScreen` já faz: uma página de 20 posts de 12 autores
custa 12 leituras de perfil — e todo mundo aparece com o nome de agora, não com
o do dia da publicação.

### Apagar é marcar, não apagar

`deleted: true`, com `text` e `imagePath` esvaziados. **O `delete` de verdade
não pode existir aqui**, e a razão é dura:

**O Firestore não apaga subcoleções em cascata.** Some o post, ficam as
curtidas e os comentários — legíveis por qualquer autenticado que tenha o id,
que é todo mundo que abriu o feed. Pior: o `delete` de comentário do dono do
post faz `get()` no post, e `get()` de documento inexistente **erra**, e erro em
regra nega. Ou seja, **apagar o post — o gesto natural de quem foi ofendido — é
exatamente o gesto que torna a ofensa permanente e imoderável.**

E ainda: o id volta a ficar livre, então um post novo no mesmo id nasce herdando
as curtidas e a thread do anterior.

O tombstone resolve os três de uma vez, e custa ~50 bytes. Exige trocar
`update: if false` por um update de dono restrito a esses campos com
`diff().affectedKeys().hasOnly([...])`. A limpeza de verdade — subcoleções e o
objeto no Storage — é Function, e entra junto com a moderação.

### Curtida

`posts/{postId}/likes/{uid}` — **o id do documento é quem curtiu**. Curtir é
criar, descurtir é apagar, e a unicidade sai de graça: ninguém curte duas
vezes, sem contador para conciliar. Mesma técnica de `nicknames`.

O corpo repete o `uid` mesmo sendo redundante com o id, e é de propósito: sem o
campo, `collectionGroup('likes').where('uid', '==', eu)` é impossível, e saber
quais dos 20 posts da tela eu já curti vira 20 `get()`. Um campo que a regra
confere contra o id não abre personificação e economiza uma leitura por post,
para sempre.

**Fora do documento do post**, e o motivo mudou de tamanho mas não de natureza:
um `snapshots()` cobra uma leitura por documento reentregue, por espectador.
Contador dentro do post = 200 feeds abertos num post que recebe 40 curtidas são
**8.000 leituras**, 16% da cota diária gratuita por um número.

**O total é um valor de abertura de tela, não ao vivo.** `count()` não funciona
com listener nem offline — só responde por chamada direta ao servidor. A
curtida do próprio usuário atualiza otimista, no `setState`; o total dos outros
só muda quando a tela recarrega. Isso é decisão de UI, não nota de rodapé.

Custo do `count()`: 1 leitura por lote de até 1000 entradas de índice. Contar 50
curtidas é 1 leitura. **O contador em documento irmão só compensa acima de ~1000
curtidas por post** — e mesmo lá tem de ser contador distribuído em *shards*,
porque um documento único aguenta ~1 escrita/s. A modelagem atual aguenta 500
curtidas/s (o teto da coleção, por causa do timestamp indexado).

### Comentário

`posts/{postId}/comments/{id}` com `uid`, `text` e `createdAt`. Ordena por
`createdAt`, campo único em subcoleção: **não precisa de índice composto**.

Aqui `list` é liberado de propósito, ao contrário de `profiles` e `nicknames`:
a subcoleção está sob um post, então listar devolve os comentários daquele post
e nada mais. `list` fechado é sobre não deixar enumerar a base inteira, não
sobre proibir listagem.

**Sem `update`, como o histórico de preço do posto.** Comentário que pode ser
reescrito depois de alguém responder não é comentário.

### As regras, com o que a revisão encontrou

Duas coisas que a primeira versão deste esboço errou, e valem enunciadas porque
são a mesma lição duas vezes: **o documento global era o menos validado do
bloco**, e **a lição do carimbo de tempo não foi aplicada onde mais doía**.

```
match /posts/{postId} {
  allow get, list: if request.auth != null;

  // O post é o único documento *global* daqui, e por isso o mais validado —
  // não o contrário. Sem `hasOnly` o cliente inventa campo; sem teto de
  // tamanho grava 1 MiB numa coleção que todo mundo lista; sem
  // `createdAt == request.time` um post com data de 9999 fica em primeiro
  // lugar no feed de todo mundo para sempre, e `update` restrito impede até
  // o autor de corrigir.
  //
  // É o mesmo ataque que esta spec já fechou em `friends.at` — "ordenar por
  // dado do adversário é o tipo de coisa que só aparece quando alguém quer".
  // Lá a lista era de um usuário; aqui é de todos.
  allow create: if request.auth != null
                && request.resource.data.uid == request.auth.uid
                && request.resource.data.keys().hasAll(
                     ['uid', 'text', 'createdAt'])
                && request.resource.data.keys().hasOnly(
                     ['uid', 'text', 'company', 'imagePath', 'createdAt'])
                && request.resource.data.text is string
                && request.resource.data.text.size() <= 500
                && request.resource.data.createdAt == request.time
                && (!('imagePath' in request.resource.data)
                    || request.resource.data.imagePath
                         .matches('^posts/' + request.auth.uid + '/.*'));

  // Apagar é marcar. O `diff` prende o update ao tombstone: o autor não
  // reescreve o texto depois de comentado, e ninguém mexe no `createdAt`.
  allow update: if request.auth != null
                && resource.data.uid == request.auth.uid
                && request.resource.data.diff(resource.data)
                     .affectedKeys().hasOnly(['deleted', 'text', 'imagePath'])
                && request.resource.data.deleted == true;

  allow delete: if false;

  match /likes/{likerId} {
    allow get, list: if request.auth != null;
    allow create: if request.auth != null
                  && request.auth.uid == likerId
                  && request.resource.data.keys().hasOnly(['uid', 'at'])
                  && request.resource.data.uid == likerId
                  && request.resource.data.at == request.time
                  && exists(/databases/$(database)/documents/posts/$(postId));
    allow update: if false;
    allow delete: if request.auth != null && request.auth.uid == likerId;
  }

  match /comments/{commentId} {
    allow get, list: if request.auth != null;

    // O `exists` no pai fecha o depósito de lixo: sem ele, qualquer um
    // escreve em `posts/<id-inventado>/comments/*` em laço — documentos
    // permanentes, cobrados, invisíveis no app e que nenhum delete alcança,
    // porque o ramo do dono do post erra num post que nunca existiu.
    allow create: if request.auth != null
                  && request.resource.data.uid == request.auth.uid
                  && request.resource.data.keys().hasAll(
                       ['uid', 'text', 'createdAt'])
                  && request.resource.data.keys().hasOnly(
                       ['uid', 'text', 'createdAt'])
                  && request.resource.data.text is string
                  && request.resource.data.text.size() > 0
                  && request.resource.data.text.size() <= 500
                  && request.resource.data.createdAt == request.time
                  && exists(/databases/$(database)/documents/posts/$(postId));

    allow update: if false;

    // Moderação sem servidor: o dono do post apaga qualquer comentário do
    // próprio post. Quem foi comentado não escolheu ser comentado, e essa é
    // a diferença entre curtida e comentário.
    //
    // Só funciona porque o post nunca é apagado de verdade — com `delete`
    // real, o `get()` erraria e a moderação morreria justo quando importa.
    // O `get()` é uma leitura cobrada por tentativa, inclusive nas negadas.
    allow delete: if request.auth != null
                  && resource != null
                  && (resource.data.uid == request.auth.uid
                      || get(/databases/$(database)/documents/posts/$(postId))
                           .data.uid == request.auth.uid);
  }
}

// Sem isto o batch do espelho é negado e o post não publica.
match /iter/{userId}/posts/{postId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

### O que isso custa de verdade

Os números da primeira versão deste esboço estavam errados, e o erro grande era
o único que vira decisão.

| | |
|---|---|
| Documento do post | ~350 B de piso (foto sem legenda), ~500 típico, ~900 no teto |
| Com índices | ~2,1 KB — todo campo de topo é indexado nos dois sentidos |
| Página de 20 posts | **32 leituras** (20 posts + 12 perfis), ~52 com o estado da curtida |
| Cota gratuita | 50 mil leituras/dia → ~1.000 aberturas de feed, para o projeto **inteiro** |

**O dinheiro não está no Firestore.** A 150 KB por foto, 20 fotos por página e
1.000 aberturas/dia são ~90 GB/mês de egress do Storage — colado no limite
gratuito de 100 GB, e ~US$ 0,12/GB depois. Uma página de feed custa
US$ 0,00002 de Firestore e cem vezes isso de banda de imagem.

Duas consequências para a entrega: `cached_network_image` é **dependência da
feature**, não refinamento — `Image.network` só guarda em memória, e fechar o
app rebaixa tudo de novo. E `text` e `imagePath` pedem *exemption* de índice de
campo único: são ~1 KB por post de índice que nenhuma query usa.

### O `list` de posts reabre a enumeração de perfis

Registrar antes de construir, porque é a mesma porta que esta entrega fechou em
`nicknames`, reaberta pelo lado.

Com `list` em `posts`, uma conta qualquer roda `collection('posts').get()`,
colhe o `uid` de todo mundo que já publicou e percorre `profiles/{uid}` um a um
— nome, foto, apelido, rotas e taxa de insucesso. **Não adianta ter tirado o
`nickName` do post: o vetor é o `uid`.** E paginar não ajuda; `list` é `list`.

Isso muda o "Risco assumido, registrado" desta spec, que hoje diz que o custo de
entrada é saber o apelido exato. Passa a ser: *abrir o feed*. É decisão de
produto, não de engenharia, e tem de ser tomada com o número na mesa antes do
passo 1 — mural público é mural público, e talvez seja exatamente o que você
quer. A alternativa, se não for, é `stats/all` deixar de ser público e o dialog
de confirmação mostrar só nome, foto e apelido.

### A ordem em que isso pode ser construído

**Curtida é um botão: não tem como ofender ninguém. Comentário é texto livre de
uma pessoa aparecendo embaixo do post de outra.** Quem publica assume o que
escreve; quem é comentado não escolheu.

1. **App Check, orçamento e alerta de faturamento.** Deixou de ser dívida
   futura: uma coleção global gravável no Blaze sem App Check é um script de
   dez linhas fazendo você pagar. Não é Function, não tem cold start.
2. `posts` + espelho + imagem no Storage + tombstone;
3. curtida;
4. **bloqueio e denúncia**, mais a Function que limpa subcoleção e objeto;
5. comentário;
6. abrir o feed para quem você não conhece.

E cada um dos doze ataques desta revisão vira caso em
`firestore-tests/rules.test.mjs`. O `existsAfter` só foi confiável porque foi
testado contra o emulador, e nada aqui é mais óbvio do que aquilo parecia.
## Perguntas em aberto

**Três, e nenhuma bloqueia a entrega 1.**

O mural é público de verdade? Com `list` em `posts`, quem abrir o feed colhe os
uids e, por eles, o nome, a foto, as rotas e a taxa de insucesso de todo mundo
que já publicou. Talvez seja exatamente o que você quer — mural é mural. Se não
for, a saída é `stats/all` deixar de ser público e o dialog de confirmação
mostrar só nome, foto e apelido. É decisão de produto, e precisa ser tomada
antes do passo 1 do Feed.

"Mais rápido" no Ranking é **duração média** ou **minutos por pacote**? A
média bruta premia quem pega rota de 30 pacotes; o ritmo é a comparação justa.
O balde já guarda `timedPackages` para as duas contas caberem sem migração.

E o que fazer com o amigo sem dado suficiente — quem nunca preenche `endAt` não
tem tempo médio, quem nunca preenche `packages` não tem taxa. Colapsar em zero
coroaria campeão quem não entregou nada. As saídas são deixar de fora, mostrar
com "sem dados" no rodapé, ou exigir um mínimo de rotas como o `_minimumFills`
faz no consumo real.

---

# Plano de implementação

```
(1) firestore.rules ─────┬──────────────┬─────────────────┐
    publica + verifica   │              │                 │
                         ▼              ▼                 ▼
(3) PublicProfile ──→ (4) ProfileController          (6) FriendController
    toMap/fromMap         publica no AuthGate            5 operações
                                        │                 │
(5) friendship.dart ────────────────────┼─────────────────┤
    função pura                         │                 │
                                        ▼                 ▼
(2) SegmentedSelector ──────────────→ (7) addFriend ──→ (8) FriendsScreen
    + CompanyFilter                      + menu +          + friendTile
                                                              │
                                                              ▼
                                                     (9) badge ──→ (10) fechamento
```

(1), (2), (3) e (5) não dependem entre si — dá para inverter a ordem sem
prejuízo. (1) vem primeiro mesmo assim: sem regra publicada, nada de (4), (6),
(7) ou (8) é verificável, e é o erro que já custou uma tarefa na spec do
veículo.

---

# Tarefas

- [x] **1. `firestore.rules` + deploy**
  - Aceite: as cinco matches novas (`profiles`, `stats` aninhada, `incoming`,
    `outgoing`, `friends` — o bloco `posts` **não** sobe agora) compilam e são
    publicadas em `iter-mn`; `nicknames` passa de `read` para `get`; o console
    confirma que só o provedor Google está habilitado.
  - Verificar: `cd firestore-tests && npm test` (30 casos, emulador) e depois
    `firebase deploy --only firestore:rules --project iter-mn`.
  - Arquivos: `firestore.rules`, `firestore-tests/`, `firebase.json`,
    `.gitignore`

- [x] **2. `SegmentedSelector<T>` + `CompanyFilter` por cima dele**
  - Aceite: o trilho genérico aceita 2..4 segmentos com rótulo de texto ou
    widget; `CompanyFilter` mantém as `ValueKey('filtro-…')` no widget tocável
    e exatamente um `Opacity` por segmento, nenhum fora deles.
  - Verificar: `flutter test test/widget/companyFilter_test.dart` passa **sem
    edição no arquivo de teste**;
    `flutter test test/widget/segmentedSelector_test.dart`
  - Arquivos: `lib/widget/segmentedSelector.dart`,
    `lib/widget/companyFilter.dart`

- [x] **3. `PublicProfile` + `ProfileStats.toMap/fromMap`**
  - Aceite: ida e volta preserva os campos; ausente vira `null`, nunca `0`;
    `topCompany` ⇄ dois campos e `averageDuration` ⇄ minutos; `updatedAt` é
    carimbado pelo controller, fora do `toMap()`.
  - Verificar: `flutter test test/unit/publicProfile_test.dart`
  - Arquivos: `lib/model/publicProfile.dart`, `lib/Utils/profileStats.dart`

- [x] **4. `ProfileController` + publicação na abertura do app**
  - Aceite: `publish(user, routes)` grava `profiles/{uid}`, `stats/all` e os
    baldes dos últimos 12 meses num batch; `HomeScreen.initState` chama a cada
    abertura, com `user.reload()` antes; `NicknameController.change()`
    atualiza `nickName` na projeção **no mesmo batch** que já usa; gravar ou
    apagar rota reescreve o balde do mês afetado.
  - Verificar: à mão — abrir o app com sessão restaurada e conferir o
    documento no console; trocar a foto do Google e reabrir.
  - Arquivos: `lib/controller/profileController.dart`,
    `lib/Utils/monthStats.dart`, `lib/screens/home.dart`,
    `lib/controller/nicknameController.dart`

- [x] **5. `friendship.dart` — o estado como função pura**
  - Aceite: os dez estados; amizade vence convite pendente; convite mútuo
    resolve para um estado só; "perfil não publicado" é distinto de "não
    encontrado".
  - Verificar: `flutter test test/unit/friendship_test.dart`
  - Arquivos: `lib/Utils/friendship.dart`

- [x] **6. `FriendController` — convidar, aceitar, recusar, cancelar, remover**
  - Aceite: cada operação é **um** `WriteBatch`; o aceite apaga os quatro
    caminhos de marcador; desfazer apaga arestas e marcadores remanescentes;
    `watchFriends`, `watchIncoming`, `watchOutgoing`.
  - Nota: `set` cego nas arestas é seguro e ler antes seria pior. A regra
    libera `create` **e** `update` sob a mesma condição de propósito — a
    versão anterior desta spec mandava ler as duas arestas para não bater num
    `update: if false` que deixou de existir quando a escrita virou
    idempotente. Ler primeiro só acrescentaria uma corrida.
  - Verificar: à mão, com duas contas, os seis fluxos mais o do convite mútuo.
    A autorização de cada um já está coberta pelo `firestore-tests`; o que
    falta aqui é o app montar os batches como o teste monta.
  - Arquivos: `lib/controller/friendController.dart`

- [x] **7. Tela de busca `addFriend.dart` + entrada no menu `+`**
  - Aceite: normaliza a entrada; os dez estados; reusa `showProfileDialog` com
    `onAction` opcional (botão desabilitado no "sou eu") e rótulo repintável
    depois da ação; a entrada do menu é a quarta, com título e subtítulo em
    pt-BR, e navega **depois** do `pop`; o comentário obsoleto de
    `_showCreateMenu` (`home.dart:80-81`) é atualizado.
  - Verificar: `flutter test test/widget/addFriend_test.dart`
  - Arquivos: `lib/screens/addFriend.dart`, `lib/widget/profileDialog.dart`,
    `lib/screens/home.dart`

- [x] **8. `FriendsScreen` com o seletor e a lista**
  - Aceite: recebe `user` (hoje é a única aba sem parâmetro); três abas, as
    duas últimas com o aviso "Em breve"; convites acima, filtrados contra a
    lista de amigos; **o tile de convite abre o perfil** — aceitar ou recusar
    sem saber de quem é não é decisão; estado vazio com botão; carregando e
    erro por seção; um prefetch de perfis para um `Map` no state, nunca
    leitura por tile; respiro de `24 + MediaQuery.paddingOf(context).bottom`
    por causa do `extendBody`.
  - Nota: o prefetch usa `missingProfiles()`, que devolve `List` e não
    `Iterable`. Não é estilo: `where()` é preguiçoso e reavalia o filtro a
    cada iteração, então marcar os uids como "carregando" numa passada fazia
    a passada seguinte enxergar as próprias marcas e não buscar nada. Todo
    mundo aparecia como "Entregador".
  - Verificar: `flutter test test/widget/friendsScreen_test.dart`
  - Arquivos: `lib/screens/friendsScreen.dart`, `lib/widget/friendTile.dart`,
    `lib/screens/home.dart`

- [x] **9. Badge de convites na navBar**
  - Aceite: `GlassNavBar` já tem `pendingCount`/`pendingIndex` e a Home não usa
    nenhum dos dois — ligar com `pendingIndex: 3` e a contagem de
    `watchIncoming`, já filtrada contra a lista de amigos.
  - Verificar: à mão; convite recebido acende o badge sem trocar de aba.
  - Arquivos: `lib/screens/home.dart`

- [ ] **10. Verificação em aparelho e fechamento**
  - Aceite: os critérios de sucesso, com duas contas reais; `CLAUDE.md`
    atualizado — sai `socialScreen.dart` da lista de stubs, sai a linha do menu
    `+` com entradas sem `onTap`, entram a aba Amigos e as coleções
    `profiles`/`friends`/`friendRequests`.
  - Verificar: `flutter analyze lib/` e `flutter test` (639 verdes, o
    `widget_test.dart` do template segue vermelho e não é regressão).
  - Arquivos: `CLAUDE.md`
