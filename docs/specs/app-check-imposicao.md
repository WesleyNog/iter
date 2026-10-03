# Spec: App Check — a imposição

> **Status: em observação, aguardando a métrica decair (2026-10-03).** O
> código do app está pronto desde 2026-08-28 (`docs/specs/notificacoes.md`,
> seção "App Check: 90% console, 10% Dart" — o runbook de referência, que
> esta spec não repete). Feito em 03/10: painel atestando com Fraud Defense
> (chave `6LfAKN0t…`, no ar); as TRÊS digitais conferidas no Play Integrity
> (debug `7f:e4…`, Play `ed:c1:84…` — batida com a aba Assinatura de apps —,
> upload `fe:2d:e7…` adicionada); a sonda do app confirmou no Samsung que a
> atestação falhava por token de depuração não registrado — o 2º suspeito
> dos 18%. **Antes do interruptor falta**: registrar o token de depuração
> do Samsung (o CLI local não tem `appcheck:debugtokens:create`; é colar no
> console) e o do iPhone quando rodar lá; e a fração não verificada do
> Firestore decair de 18% para ~0 por alguns dias.

## Objetivo

Ligar a imposição do App Check em **Cloud Firestore e Cloud Storage** — nunca
Authentication, pela assimetria já documentada: atestação falhando com Auth
imposto tranca o dono para fora da própria conta. Com a imposição ligada,
`posts`, `reports`, `gastop` e as demais coleções abertas a "qualquer
autenticado" passam a aceitar escrita só de quem provar ser **este app** (ou
o painel, ou o Admin SDK das functions, que não passa por App Check). O
script de dez linhas que o Blaze tornaria caro morre aqui.

## O que mudou desde a spec de agosto

### 1. O painel admin é um cliente web que não existia

`site/admin.html` + `admin.js` (2026-10-03) leem Firestore e Storage com o
SDK web. **Impor hoje mata o painel**: ele não envia token de App Check.

- **O reCAPTCHA clássico foi descontinuado** (banner do console,
  2026-10-03): o caminho é o **Fraud Defense** (o reCAPTCHA Enterprise
  renomeado). A chave nasce no Cloud Console (Segurança → Fraud Defense →
  criar chave: site web, por pontuação/sem desafio, domínio
  `iter-mn.web.app`) e o registro do Web App em App Check usa essa chave.
  O nível gratuito (10 mil avaliações/mês) cobre o painel com sobra de
  ordens de magnitude. A chave de site é pública (vai no JS).
- Código: `initializeAppCheck(app, { provider: new
  ReCaptchaEnterpriseProvider('<chave>'), isTokenAutoRefreshEnabled: true })`
  em `admin.js`, antes de qualquer leitura — `ReCaptchaEnterpriseProvider`
  e não `ReCaptchaV3Provider`, que é o clássico descontinuado. Mesma regra
  do app: ativar sem impor não muda nada, então o deploy é seguro a
  qualquer momento — e é PRÉ-REQUISITO do interruptor.

As Functions seguem fora: gatilho não é callable, e o Admin SDK da moderação
ignora App Check — zero mudança em `functions/`.

### 2. A Play re-assina, e a digital registrada é a antiga

O registro do Play Integrity no App Check informou o **SHA-256 da chave de
debug**, correto quando o release assinava com ela e o app vivia fora da
loja. Desde `0716897` o release assina com a **chave de upload**, e a Play
re-assina o que distribui com a **chave de assinatura do app** — o testador
que instala pela loja atesta com uma digital que o App Check não conhece.

É a mesma classe do incidente do Sign-In ("a loja não loga e o debug loga:
conferir SHA antes de qualquer outra coisa"), uma camada acima: lá a falta
do SHA-1 negava o login; aqui, a falta do SHA-256 faria a imposição derrubar
exatamente os aparelhos dos testadores — os que menos têm canal de suporte.

Levantamento feito em 2026-10-03 (keytool local + console):

| Chave | SHA-256 | Registrada? |
|---|---|---|
| debug | `7F:E4:26:C6:33:2F:F0:39:…:2F:87` | **sim** (1ª do formulário) |
| upload (`~/keystores/`) | `FE:2D:E7:AE:9D:ED:99:AF:6A:19:F1:CC:08:5B:ED:03:E6:67:68:97:6B:FD:5C:A5:6D:2C:A8:AE:39:25:5C:8D` | **não — adicionar** |
| assinatura do app (Play) | Play Console → Integridade do app → aba Assinatura de apps | provavelmente a 2ª do formulário (`ed:c1:84:…`) — **conferir lá** |

O formulário aceita várias digitais ("Adicionar outra impressão digital").
A de upload cobre o APK de release instalado localmente; a da Play cobre
todo mundo que instala pela loja; a aba Assinatura de apps do Play Console
mostra as duas, o que fecha a conferência numa página só.

### 3. iOS: sem conta da Apple, o caminho é só o token de depuração

Não há conta de desenvolvedor Apple (2026-10-03), então App Attest não
atesta de qualquer forma — ele exige entitlement e assinatura de
distribuição. O iPhone do dono roda build de debug → `AppleDebugProvider` →
**token de depuração registrado** (aparece no console do Xcode na primeira
execução; cadastrar em App Check → Apps → `⋮` do app iOS → Gerenciar tokens
de depuração). Sem isso, a imposição derruba o app no iPhone — recuperável
registrando o token depois, mas melhor antes. Quando a conta Apple existir
e o app for distribuído, registrar App Attest vira pendência real.

## O portão: a métrica, não o calendário

Impor quando **App Check → APIs** mostrar Firestore e Storage com
requisições verificadas em ~100% por alguns dias — a fração não verificada
tem de ser explicável. Builds dos testadores: o SDK entrou no app em 28/08,
antes do primeiro build do teste fechado, então **não há instalação ativa
sem App Check** — a métrica confirma ou desmente.

**Leitura de 2026-10-03**: Storage **100% verificado / 0%** — pronto.
Firestore **82% / 18%** — e o suspeito número um dos 18% é o próprio
**painel admin**, nascido HOJE sem App Check e usado intensamente hoje;
o suspeito dois é aparelho de desenvolvimento sem token de depuração
registrado (a `_sonda` do app diz no log de debug qual é o caso). Depois
do painel atestar e dos tokens registrados, a fração deve decair para ~0
em poucos dias — é essa decaída que libera o interruptor do Firestore.
Authentication marca 57/43 e **não importa**: nunca se impõe.

## O dia do interruptor

1. Painel com reCAPTCHA **já no ar** e conferido (abrir a fila logada).
2. Os três SHA-256 no registro do Android; iOS registrado; tokens de
   depuração dos aparelhos do dono cadastrados.
3. Métrica verde nos dois produtos, por dias.
4. **Impor Cloud Firestore.** Vale em até 15 minutos; o token tem TTL de 1h,
   então um cliente recém-atestado não cai no meio.
5. Usar o app e o painel normalmente por um dia. Os modos de falha
   silenciosos estão na spec de agosto — o resumo: `fcmTokens` negado mata o
   push sem log do lado do app, o cache do Firestore mascara leitura, e
   "Não foi possível salvar a rota. Tente novamente." sob imposição é
   permanente, não transitório. **Sintoma estranho depois da imposição:
   olhar App Check ANTES de olhar regra.**
6. **Impor Cloud Storage.**
7. Reverter é destravar no mesmo lugar — o interruptor é reversível e vale
   em minutos; nenhuma migração de dado envolvida.

## Fronteiras

- **Sempre**: painel antes do interruptor; métrica antes do interruptor; um
  produto por vez; conferir o painel e o app logo após cada imposição.
- **Perguntar antes**: qualquer mudança nas configurações avançadas do Play
  Integrity (afrouxar depois de impor é o que deixa aparelho de fora).
- **Nunca**: impor Authentication; registrar token de depuração que não
  saiu de um aparelho do dono (token de depuração registrado É um bypass);
  interruptor com métrica mostrando tráfego não verificado inexplicado.

## Critérios de sucesso

1. Painel abre a fila normalmente com App Check ativo (antes e depois da
   imposição).
2. Métrica: ~100% verificado em Firestore e Storage antes do clique.
3. Depois de impor: app funciona nos aparelhos do dono (debug e release
   local), app da loja funciona num aparelho de testador, painel funciona,
   push continua chegando (o sintoma silencioso nº 1).
4. Um cliente SEM atestação (ex.: script com o config público) é negado no
   Firestore — a prova de que o interruptor prende alguém.

## Questões em aberto (as leituras que só o console dá)

1. **Web**: registrar o `Painel Admin` com reCAPTCHA v3 e me passar a
   **chave de site** — eu escrevo o código do painel e publico.
2. **Android**: o formulário do Play Integrity aceita múltiplos SHA-256?
   Adicionar os três da tabela; me dizer como ficou.
3. **iOS**: o app iOS aparece registrado em App Check? Com qual provedor?
4. **Métrica**: o que App Check → APIs mostra hoje para Firestore e Storage
   (% verificado)? Uma captura resolve.
