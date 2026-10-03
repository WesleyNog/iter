# Spec: Moderação automática do mural

> **Status: validada pelo dono em 2026-10-03** (ver "Decisões" no fim).
> Pendência única antes do deploy: **confirmar no console** que o orçamento
> de faturamento com alerta existe — a resposta foi "acredito que sim", e
> crença não destrava trava.

## Objetivo

Hoje todo conteúdo do mural só é julgado se alguém denunciar — e o pior
conteúdo é justamente o que ninguém deveria precisar ver para ele sair do ar.
Uma Function acionada a cada publicação (post **e comentário**) classifica o
texto e a imagem com o Gemini e age pela gravidade: o grave sai do ar em
segundos, o ambíguo vira denúncia automática na fila do painel que já existe
(`docs/specs/painel-admin.md`). A máquina **tria**; quem julga continua sendo
o dono, no mesmo lugar onde já julga as denúncias humanas.

**Sucesso**: um post com teor criminoso evidente dura segundos no mural e
chega ao painel com o original preservado em quarentena; um post de gíria
pesada mas inocente não é tocado; e nenhuma falha de API jamais remove nada.

## Premissas assumidas

1. **Gemini via Vertex AI**, não via chave do AI Studio: a chamada autentica
   com a service account das Functions (nenhuma chave em disco), o dado fica
   com o processador que o app já usa (LGPD: Google já processa tudo do
   iter), e no Vertex o conteúdo não treina modelo. A região do modelo é
   independente da região da Function — o endpoint pode ser `global`/
   `us-central1` com a Function em `southamerica-east1`; residência de dado
   não é exigência da LGPD.
2. **Modelo `gemini-2.5-flash-lite`**, temperatura 0, saída estruturada
   (JSON com categorias e confiança). Se a precisão decepcionar na prática,
   subir para `gemini-2.5-flash` é trocar uma constante.
3. **Multimodal dispensa OCR**: a imagem do post vai na mesma chamada
   (bytes inline — o teto de 2 MiB do `storage.rules` cabe com folga no
   limite do Vertex), e o modelo lê inclusive texto dentro da imagem.
4. **Pós-publicação, não pré**: o post aparece e a análise roda 1–3 s
   depois. Essa janela é inerente ao desenho; segurar toda publicação até a
   análise passar mudaria o app inteiro para castigar os 99% inocentes.
5. **Gatilho `onDocumentCreated`, nunca `onWrite`**: a lápide que a própria
   Function grava re-dispararia um `onWrite` — o loop exato que o CLAUDE.md
   avisa que custa dinheiro. `onCreate` não re-dispara em update, por
   construção.
6. **Orçamento de faturamento com alerta é pré-requisito de deploy.** Já era
   a pendência registrada antes da primeira Function; esta adiciona uma
   chamada paga por publicação, então deixa de ser aviso e vira trava.

## O desenho: dois degraus, porque a lápide destrói

A lápide do app apaga o texto para sempre (`text: ''`, sem caminho de volta
pelas regras). Remoção automática não é "esconder", é **destruir** — e
classificador erra. O falso positivo é o lado que engana, então o desenho
nunca deixa a máquina destruir sozinha o que não consegue devolver:

| Degrau | Categorias (proposta) | Ação da Function |
|---|---|---|
| **Grave, confiança alta** | teor sexual envolvendo menores; ameaça direta / violência iminente | **1.** copia o original para `quarentena/{alvo}` (e move a foto no Storage) **2.** grava a lápide / apaga o comentário **3.** denúncia automática na fila |
| **Ambíguo, ou grave de confiança baixa** | racismo e ofensa discriminatória; golpe; teor sexual explícito adulto | denúncia automática na fila — **não remove**; o humano decide no painel |
| **Limpo** | — | nada: nenhum documento, nenhum rastro, nenhum custo além da chamada |

Racismo começa no degrau 2 **de propósito**, apesar de ser crime: é a
categoria em que a precisão do classificador em pt-BR é mais fraca (gíria,
ironia, citação), e o custo do erro é destruir post inocente. Depois de
observar os acertos na fila, promovê-lo ao degrau 1 é mudar uma linha da
tabela de decisão — com os dados do painel como justificativa, não um chute.

**A quarentena existe pelos dois erros possíveis.** Se a máquina errou, o
original está lá para restaurar (via console no v1). Se acertou — e for o
crime de verdade —, destruir seria destruir **evidência**: o caminho certo é
preservar e denunciar (SaferNet / autoridade), e a cópia é o que torna isso
possível. Apagar a quarentena nunca é da máquina.

### O bloqueio do próprio Gemini é sinal, não falha

O Vertex recusa processar certas entradas (`PROHIBITED_CONTENT` — na
prática, imagem de abuso infantil). Essa recusa é o filtro de maior precisão
do Google inteiro disparando: tratar como **grave de confiança alta**
(degrau 1, categoria `bloqueado-pelo-filtro`). Um bloqueio genérico de
`SAFETY`, mais impreciso, cai no degrau 2. Falha de rede/quota é outra
coisa — ver abaixo.

### Falha da API nunca remove: fail-open com retry

API fora do ar, timeout, quota: a Function **lança** e o retry da plataforma
re-tenta (como `excluirConta`, com `failurePolicy`); esgotado o retry, o
post fica no ar **sem** marca — o canal humano de denúncia continua
existindo, e remover por falha seria punir o inocente pela indisponibilidade
do juiz. Todo passo é idempotente porque a fonte é **`event.data`** (o
snapshot do documento criado), nunca uma releitura: rodar duas vezes grava
os mesmos bytes nos mesmos lugares — e o emulador prova rodando duas vezes,
como a suíte da exclusão de conta já faz.

## O que nasce e o que muda

- **`functions/moderacao.js`** — o gatilho (posts e comentários) e a
  orquestração: classificar → decidir → agir.
- **`functions/veredito.js`** — a decisão **pura** (categorias × confiança →
  degrau), testável com `node --test` sem emulador, como `texto.js` e
  `marcos.js`. A tabela de decisão mora aqui, num lugar só.
- **`functions/gemini.js`** — a chamada ao Vertex, **injetável**: o emulador
  e os testes passam um classificador falso; nenhum teste chama API real.
  Safety settings em `BLOCK_NONE` nas categorias configuráveis — o
  classificador precisa *ver* o conteúdo para julgá-lo; o bloqueio
  irredutível é o sinal da seção anterior.
- **`quarentena/{alvo}`** (Firestore) — id na gramática dos alvos
  (`p_{postId}` / `c_{postId}_{commentId}`), corpo com autor, texto
  original, caminhos de imagem (antigo e novo), categorias, confiança e
  carimbos. Regras: `get, list: if isAdmin()`, escrita `if false` — só o
  Admin SDK escreve. Storage: a foto move de `posts/{uid}/…` para
  `quarentena/{alvo}/…`, com a negação explícita no `storage.rules` (o
  catch-all já nega, mas silêncio não diz que foi escolha — regra da casa).
- **Denúncia automática** — `reports/{alvo}__maquina`: o sufixo identifica a
  procedência (nenhum uid real colide), o painel já agrupa por alvo, e as
  denúncias humanas do mesmo alvo caem no mesmo cartão. `reason` vem de uma
  lista fechada própria (`sexual-menores`, `ameaca`, `racismo`, `golpe`,
  `sexual-explicito`, `bloqueado-pelo-filtro`, `resposta-invalida`) — as
  regras só prendem o cliente, e o painel ganha os rótulos. O corpo carrega
  `removeu: true|false`, para o cartão distinguir revisar um ato de decidir
  um.
- **Painel** (`site/admin.js`, mudança pequena) — selo "automática" quando o
  sufixo é `__maquina`, categorias no cartão, e o conteúdo de quarentena
  exibido quando foi a máquina que removeu — para o dono julgar o
  julgamento dela.

Pré-requisitos de console (uma vez): habilitar `aiplatform.googleapis.com`
no projeto e dar `roles/aiplatform.user` à service account das Functions.
Dependência nova: `@google/genai` (Node 22 atende).

## Comandos

```bash
cd functions && npm test              # decisão pura, sem emulador
cd functions && npm run emulador      # fluxo completo, classificador falso
cd firestore-tests && npm test        # regras de `quarentena`
firebase deploy --only firestore:rules,storage
firebase deploy --only functions:moderacaoPosts,functions:moderacaoComentarios
firebase deploy --only hosting        # painel com os selos
```

Ordem: regras → functions → hosting. Regra sem function é coleção vazia;
function sem regra escreveria numa coleção que o cliente não lê mesmo.

## Estratégia de teste

1. **`veredito.js` com `node --test`**: cada linha da tabela de decisão, os
   dois lados de cada corte de confiança, bloqueio-como-sinal, resposta
   malformada do modelo → degrau 2 (na dúvida, humano).
2. **Emulador** (`functions/test`), classificador falso injetado:
   - grave → lápide exata + foto movida + quarentena + denúncia `__maquina`;
   - ambíguo → só a denúncia, post intocado;
   - limpo → nenhuma escrita;
   - comentário grave → apagado + quarentena + denúncia;
   - classificador lançando → post intocado, Function lança (retry);
   - **tudo rodado duas vezes** → estado idêntico.
3. **`firestore-tests`**: admin lê `quarentena`, conta comum não, ninguém
   escreve pelo cliente.
4. O que teste nenhum pega, registrado como no `norouterule`: a qualidade
   real do classificador em pt-BR só aparece em produção — e o lugar de
   observá-la é a fila do painel, comparando veredito da máquina com o seu.

## Fronteiras

- **Sempre**: decisão em módulo puro com a API injetável; `event.data` como
  fonte (nunca re-ler o documento); cópia em quarentena **antes** da lápide;
  fail-open em falha de API; `npm test` dos três projetos antes de deploy.
- **Perguntar antes**: mudar categorias ou cortes de confiança; promover
  racismo ao degrau 1; backfill do acervo; trocar de modelo; qualquer coisa
  que mande conteúdo para fora do Google.
- **Nunca**: deploy sem orçamento + alerta de faturamento; `onWrite` nestes
  gatilhos; remover por falha de API; a máquina apagar quarentena ou
  denúncia; chave de API em disco quando a service account basta.

## Critérios de sucesso

1. Post do degrau 1 (teste controlado) some do mural em segundos: lápide
   exata, foto fora de `posts/` no Storage, original legível em
   `quarentena/{alvo}` pelo painel, denúncia `__maquina` na fila com selo e
   categorias.
2. Post do degrau 2 continua no ar e aparece na fila como denúncia
   automática.
3. Post limpo: nenhum documento novo em lugar nenhum.
4. Comentário grave: apagado, com quarentena e denúncia.
5. Com a API indisponível (emulador), nada é removido e a Function re-tenta.
6. Suíte do emulador roda cada cenário **duas vezes** com estado final
   idêntico.
7. `functions npm test`, emulador e `firestore-tests` verdes; `flutter test`
   intocado — nenhuma mudança no app.
8. Custo observado no primeiro mês condizente com a estimativa abaixo.

## Custo

Uma chamada Flash-Lite por publicação: ~1 k tokens de entrada (texto +
imagem + instrução) e ~100 de saída ≈ **menos de R$ 0,01 por post, com
folga** — US$ 0,10/M de entrada e US$ 0,40/M de saída. Mil publicações/mês
custam centavos; o risco financeiro real não é o preço unitário, é loop de
gatilho — fechado pela premissa 5 — e por isso o orçamento com alerta é
trava e não sugestão.

## Fora do v1, de propósito

- **Backfill do acervo** (varrer posts antigos): script avulso, um dia, com
  orçamento próprio.
- **Restaurar pelo painel** (callable que desfaz a lápide a partir da
  quarentena): no v1, restauração de falso positivo é manual via console —
  rara por construção, já que o degrau 1 é estreito.
- **Nomes de perfil e apelidos**: outra superfície, outro gatilho, outra
  spec.
- **App Check**: segue sendo a pendência que fecha a torneira de escrita de
  robô — esta spec não a substitui.

## Decisões (validadas em 2026-10-03)

1. **Tabela de degraus conforme a recomendação** — racismo no degrau 2 até
   a fila do painel provar a precisão; promover depois é mudar uma linha de
   `veredito.js`, com os acertos observados como justificativa.
2. **Orçamento de faturamento**: o dono acredita que existe; **conferir no
   console antes do deploy das functions** (Billing → Budgets & alerts). Se
   não existir, criar é pré-requisito, não tarefa paralela.
3. **Sem backfill**: o acervo existente (só posts de teste) fica como está.
   A moderação nasce valendo do primeiro post após o deploy em diante.
