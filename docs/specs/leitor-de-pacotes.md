# Spec: Leitor de pacotes

Status: **em implementação** · Escrita, aprovada e implementada até a tarefa 9
em 2026-10-06 · Falta o aparelho: a tarefa 8 rodando no iPhone e no Android, e
a carga real no CD (tarefa 10)

## Objetivo

No CD do Mercado Livre, antes de sair, o entregador confere a carga: quantos
pacotes, quantos de cada tipo e — principalmente — quantos **A**, porque
agência ou Place fechado é pacote que sai da rota. É esse total corrigido que
ele lança no app do Mercado Livre. Hoje a conta é feita de cabeça, pacote por
pacote, e depois digitada de novo no iter (Pacotes, Paradas, bairros).

O leitor faz as duas coisas de uma vez: a câmera lê cada etiqueta, uma barra
conta os tipos enquanto ele lê, e ao finalizar a rota sai de **Agendado** para
**Em rota** já com pacotes, paradas e bairros preenchidos — e com **quantos
pacotes foram para cada bairro**, que o app nunca soube e hoje estima.

Usuário: o entregador, no CD, com o celular numa mão e o pacote na outra.
Sucesso = ler uma carga de 100 pacotes sem digitar nada, sem contar um pacote
duas vezes, e sair com o número que vai lançar no app do Mercado Livre.

## A etiqueta entrega isso? — medido, não suposto

As duas fotos de etiqueta que vieram com o pedido foram decodificadas no Mac
antes desta spec ser escrita: o QR com o OpenCV, o texto com o Vision da Apple
(OCR no aparelho, do mesmo tipo que o app vai usar). As fotos ainda passaram
pela compressão do WhatsApp — a câmera ao vivo entrega imagem melhor que isso.

**O QR não traz endereço nem tipo.** O conteúdo inteiro é:

```json
{"id":"47806623578","t":"lm"}
```

`id` é o número impresso embaixo do código de barras — o envio. Isso resolve a
parte mais importante, que é **não contar o mesmo pacote duas vezes**: a câmera
vê a mesma etiqueta em dezenas de quadros seguidos, e o `id` é a identidade
dela. Bairro e letra têm de vir do texto impresso.

**O texto sai, e sai certo onde importa:**

| campo | foto 1 (saco plástico) | foto 2 (caixa, impressão gasta) |
|---|---|---|
| endereço | `Endereço: Rua Pereira de Miranda 575,` + linha seguinte `Papicu` | `Endereço: Avenida António Justa 3330, Meireles` |
| bairro extraído | **Papicu** (está em `fortaleza_bairros`) | **Meireles** (está em `fortaleza_bairros`) |
| letra do tipo | `R`, confiança 0,5 | `R`, confiança 1,0 |
| CEP | `CEP: 60175045` | `CEF. 60165090` — prefixo errado, dígitos certos |

Na foto 2 o OCR também leu `Complemeato` e `António` — erros de impressão
térmica gasta. Nenhum deles cai num campo que o leitor usa, mas é o aviso de
que o parser tem de ser tolerante na âncora (`Endereço`) e exigente no que
grava (o bairro só entra se casar com a lista).

**Confiança por campo:**

| campo | confiança | por quê |
|---|---|---|
| identidade do pacote | **certa** | JSON do QR, verificado |
| bairro | **alta** | lido nas duas fotos; validado contra `fortaleza_bairros` |
| letra R/C/A | **média-alta** | lida nas duas, mas só existem amostras de **R**. Ninguém viu ainda um C ou um A passar pelo OCR |
| paradas | **média** | derivada de CEP + número; um erro de OCR em qualquer dos dois separa uma parada em duas |

O que a etiqueta tem e o leitor **não usa**: o número na caixa preta (`3`,
`5`), `SCE1`, o `> 52`/`> 11` do fim da rota de triagem e o horário (`05:00`)
— nenhum deles tem significado confirmado nem alimenta conta. O código de
barras de baixo da foto 2 é a chave da DANFE (44 dígitos) e é ignorado: o
leitor só aceita QR.

## O fluxo

1. **Gesto.** Na lista, deslizar da esquerda para a direita uma rota
   **Agendada do Mercado Livre** revela a ação "Ler pacotes" — o mesmo lado
   do "Pagar". Em qualquer outro status ou empresa o painel não existe. Os dois
   nunca disputam o lado: "Pagar" é só Concluído.
2. **Câmera** em tela cheia, com a mira e a barra de contagem por cima.
3. **A cada etiqueta nova:** vibração curta e um cartão no topo com o que foi
   lido (`Papicu · R`). Etiqueta já lida: aviso discreto "Já lido", sem vibrar
   e sem contar.
4. **A** lido: vibração mais forte e o cartão diz **AGÊNCIA** por extenso —
   é o momento de olhar se ela está aberta, com o pacote ainda na mão.
5. **Letra não lida:** o pacote entra no total na hora e aparecem três botões
   `R  C  A` no cartão. Ler o próximo pacote sem responder deixa este como
   **?** — nada bloqueia a fila, e o "?" aparece na barra até ser resolvido na
   lista. O app nunca chuta a letra.
6. **Lista da sessão** (tocar na barra; tocar num tipo abre filtrada por ele):
   os pacotes lidos, com os últimos dígitos do envio, o bairro e o tipo.
   Deslizar remove — é assim que a agência fechada sai da contagem. Tocar no
   tipo corrige. Um pacote removido **não volta sozinho** se a câmera o vir de
   novo: o cartão diz "foi tirado da carga" e oferece "Contar de novo".
7. **Finalizar** pausa a câmera e abre a revisão: pacotes, paradas e bairros,
   os dois números editáveis e os bairros pelo seletor que o formulário já
   usa. "Voltar a ler" retoma a sessão de onde parou.
8. **Salvar** grava e volta para a lista, com "Rota iniciada · 87 pacotes" e
   um **Desfazer**.

```
┌──────────────────────────────────┐
│  ┌────────────────────────────┐  │
│  │ ✓ Papicu · Residencial     │  │  ← cartão da última leitura
│  └────────────────────────────┘  │
│                                  │
│         ┌──────────────┐         │
│         │              │         │  ← mira
│         │              │         │
│         └──────────────┘         │
│                            [💡]  │  ← lanterna
│ ┌──────────────────────────────┐ │
│ │  87 pacotes   ·   74 paradas │ │
│ │  R 70    [ C 12 ]  [▌A 5 ▐]  │ │  ← C destacado, A mais ainda
│ │              [ Finalizar ]   │ │
│ └──────────────────────────────┘ │
└──────────────────────────────────┘
```

Sair da tela com pacotes lidos e sem salvar pergunta "Descartar 47 pacotes
lidos?". A sessão vive só na memória da tela: se o sistema matar o app no meio
da leitura, ela se perde (ver [Riscos](#riscos)).

## Regras de leitura

Tudo que decide "o que esta etiqueta disse" mora em
`lib/Utils/packageLabel.dart`, **função pura**, sem tipo de câmera nem de ML
Kit na assinatura — o mesmo desenho de `nicknameFromScan` no convite por QR. A
tela só entrega texto com posição; o parser é testado com as linhas reais das
duas fotos.

**Identidade.** O QR tem de ser um JSON com `id` só de dígitos. Qualquer outro
QR (convite do iter, Wi-Fi, cartaz) é recusado com "Esse código não é uma
etiqueta do Mercado Livre" — dizer o que o código **é** evita a conclusão de
que o leitor está quebrado.

**Letra.** Um elemento de texto com exatamente um caractere entre `R`, `C`,
`A`, cujo centro esteja na faixa horizontal do QR e logo **abaixo** dele (até
~0,6 da altura do QR). A posição vem dos cantos que o `mobile_scanner` já
devolve. Sem essa âncora geométrica, qualquer letra solta da etiqueta viraria
tipo; com ela, só a tarja embaixo do QR conta. Nas duas fotos o `R` cai
exatamente nessa janela.

**Bairro.** O bloco começa na linha cujo início casa com `Endereço:` —
tolerante: `Endereco`, `Enderego` — e segue pelas linhas alinhadas à esquerda
logo abaixo, até a que começa com `CEP`, `Cidade de destino` ou `Complemento`.
O texto depois da **última vírgula** do bloco é o bairro (na foto 1 ele está
na linha seguinte; por isso o bloco e não a linha). Esse texto só vira bairro
se casar com `fortaleza_bairros`:

1. igual depois de `normalizeKey` (`Utils/text.dart`), ou
2. um **único** candidato a distância de edição ≤ 1 (até 6 letras) ou ≤ 2
   (acima). Dois candidatos à mesma distância = nenhum: `Praia do Futuro I` e
   `II` ficam a 1 letra um do outro, e escolher seria inventar.

Sem casamento, o pacote conta e fica "sem bairro"; o texto lido vai para a
revisão ("2 pacotes em 'Água Fria', que não está na lista"). Um nome fora da
lista **nunca** entra em `adress`: os rankings de bairro agrupam por texto
exato, e um "Meirelles" viraria um bairro novo no gráfico.

**Parada.** Chave = CEP (8 dígitos) + número da casa (último grupo de dígitos
antes da vírgula final do endereço) — **mesmo prédio, qualquer apartamento**,
que é como o app do Mercado Livre conta. Pacotes com a mesma chave são uma
parada. Faltando qualquer um dos dois, o pacote é uma parada própria — o erro
vai para o lado de **mais** paradas, visível e corrigível na revisão, e nunca
junta dois endereços diferentes num só.

**Tentativas.** O OCR roda no quadro em que o QR novo aparece. Se faltou letra
ou bairro, tenta de novo nos quadros seguintes **do mesmo QR**, até 3 vezes ou
1,5 s, e então fecha com o que tem. Um OCR por vez: quadros que chegam com um
em andamento são descartados, para a fila não crescer atrás da câmera.

## Pacotes por bairro: a estimativa vira medição

`failureRatePerBairro` (`Utils/routeStats.dart`) se declara estimativa: "uma
rota de 48 pacotes em 2 bairros vira 24 para cada, mesmo que na prática tenham
sido 40 e 8". O leitor é o **único momento** em que o 40 e o 8 existem —
fechada a tela, somem. Por isso a rota ganha um campo, e o índice passa a usá-lo
na mesma entrega (sem o consumidor, o campo não entraria).

`NewRouteModal.pacotesPorBairro`: `Map<String, int>`, bairro → pacotes. Mesmo
formato de `insucessoPorBairro` no Firestore — array de `{bairro, qnt}` por
`distributionToList`/`distributionFromList`, porque chave com ponto quebra
field path. Vazio em toda rota que não passou pelo leitor.

**A regra de atribuição é a que o insucesso já usa**, e passa a existir uma vez
só: `_attributeFailures` hoje faz "parte exata pela distribuição, resto rateado
por igual entre os bairros da rota". Ela vira um `_attributeByBairro(total,
distribution, bairros, add)` que serve aos dois lados do índice — numerador
(insucessos) e denominador (pacotes). Duas cópias divergiriam no primeiro
ajuste, que é o mesmo argumento que já está escrito ali.

Os casos, por rota:

| a rota tem | pacotes no índice |
|---|---|
| `pacotesPorBairro` cobrindo tudo | exato |
| cobrindo parte (pacotes "sem bairro" na leitura, ou `packages` aumentado depois no formulário) | exato + resto rateado |
| nada (toda rota de hoje) | rateio inteiro, como antes |

A distribuição gravada passa por `reconcileDistribution` antes de contar — o
formulário deixa mudar `packages` e os bairros depois da leitura, e o que está
no banco pode citar bairro que a rota não tem mais ou passar do total.

**Os dois caminhos que reescrevem a rota inteira têm de carregar o campo**, e
nenhum dos dois reclama se esquecer:

- `NewRouteModal.withProvision` copia os campos um por um. Esquecer o novo não
  dá erro de compilação (parâmetro nomeado e opcional) e apaga a distribuição
  no save que calcula a provisão — ou seja, **ao concluir a rota**, exatamente
  quando ela vira dado de gráfico.
- `AddIter._saveRoute` monta a rota do zero e grava com `set`. O formulário não
  mostra o campo, mas tem de carregá-lo de `_fillFromRoute`, reconciliá-lo com
  os bairros e o `packages` da tela, e zerá-lo na Sem Rota — como já faz com
  `adress`.

O rodapé do card de índice ("No bairro, os pacotes da rota são rateados entre
eles") passa a dizer que rotas lidas pelo leitor contam pacote por pacote.

## O que é gravado — e o que nunca sai do aparelho

Salvar é um `update` em `iter/{uid}/routes/{id}` com cinco campos:

```
status:           'andamento'        (o "Em rota" que já existe)
packages:         87
stops:            74
adress:           ['Papicu', 'Meireles', ...]   ← substitui o que estava
pacotesPorBairro: [{bairro: 'Papicu', qnt: 40}, ...]
```

`adress` **substitui** os bairros marcados no agendamento: aqueles eram
palpite, estes são a carga. A ordem é por quantidade de pacotes, maior
primeiro — é a ordem em que `reconcileDistribution` preserva quando precisa
cortar, e a que o card da rota mostra.

`update`, e não `set`, pelo mesmo motivo de `RouteController.updateStatus`: o
que não é enviado não pode ser sobrescrito. E o atalho é legítimo pelo mesmo
argumento do "Pagar": Agendado e Em rota não são `hasRun`, nenhum dos dois
tem provisão nem `noRoutePayment`, então trocar um pelo outro não implica
recálculo nenhum. Também não mexe nos números públicos do perfil:
`profileStats` só lê `realized`, e Em rota não é.

O **Desfazer** regrava os cinco campos como estavam antes — a tela tem a rota
original na mão. As duas direções montam o pacote pela **mesma função**, então
o desfazer não tem como esquecer um campo que o salvar escreveu.

A contagem por tipo (R/C/A) **não é gravada**: nenhuma conta do app a usa. Ela
existe na tela, para o lançamento no app do Mercado Livre.

A etiqueta carrega dados de **terceiros** — nome, apelido, rua, número,
complemento, CEP de quem vai receber. Nada disso tem conta a alimentar no
iter, então nada disso fica:

- a imagem nunca é enviada; o arquivo temporário do quadro (o OCR lê de
  arquivo) é apagado num `finally` logo depois da leitura;
- CEP, número e `id` do envio existem só na memória da sessão, para deduplicar
  e agrupar paradas, e morrem com a tela;
- nenhum texto de OCR vai para log — `debugPrint` **também imprime em
  release**, no logcat de qualquer um que plugar o cabo.

As regras do Firestore não mudam: `iter/{uid}/routes` é só-do-dono e não
valida campos.

## Dependências

`mobile_scanner` já está no projeto (convite por QR) e já entrega o que falta:
`returnImage: true` devolve o quadro junto com o QR, e `Barcode.corners`, a
posição dele. Falta só o OCR.

**OCR por canal nativo** (`lib/services/textReader.dart`, canal `iter/ocr`):
o **Vision** da Apple no iOS, que vem no sistema, e o **ML Kit** no Android,
com o modelo latino embutido via Gradle
(`com.google.mlkit:text-recognition:16.0.1`). No aparelho, grátis e offline —
o CD não garante sinal. Nenhuma dependência nova no `pubspec`, nenhum pod.

Foi o plano B. O plano A — o pacote `google_mlkit_text_recognition` — caiu na
tarefa 1 porque quebrava o simulador iOS; ver
[Desvios](#desvios-decididos-durante-a-implementação). Custo do que ficou:

- dois arquivos nativos, `MainActivity.kt` (o canal entrou ao lado do de
  notificação) e `ios/Runner/TextReader.swift` (registrado à mão nos quatro
  pontos do `project.pbxproj`, como o `SceneDelegate.swift`). O lado nativo só
  se verifica no aparelho; o lado Dart do contrato tem teste;
- **dois motores**: o parser foi validado com saída do Vision (as duas fotos);
  a do ML Kit no Android só se vê no aparelho;
- Android: **~13 MB a mais** por aparelho arm64 (o modelo embutido). iOS: nada.

O modelo embutido e não o do Google Play Services
(`play-services-mlkit-text-recognition`), que economizaria os 11 MB mas baixa o
modelo no primeiro uso — e o primeiro uso é no CD.

Descartado: OCR na nuvem (o Gemini das Functions). Sem sinal no CD não lê;
cada etiqueta vira uma chamada paga, cem por carga; e manda nome e endereço de
terceiros para um servidor por uma conta que só precisa do bairro.

## Commands

```bash
flutter pub get                                   # depois de mexer no pubspec
flutter analyze
flutter test test/unit/packageLabel_test.dart     # parser
flutter test test/unit/packageSession_test.dart   # contagem
flutter test test/unit/routeStats_test.dart       # índice por bairro
flutter test test/widget/routeSlidable_test.dart  # gesto
flutter test                                      # tudo (widget_test.dart falha desde sempre)
df -h /System/Volumes/Data                        # ANTES de qualquer build iOS
flutter test test/unit/textReader_test.dart       # contrato do canal de OCR
flutter build ios --simulator --debug             # o que derrubou o plano A
flutter run -d <iphone>                           # câmera só existe no aparelho
```

## Estrutura

```
lib/Utils/packageLabel.dart        NOVO  parser puro: QR → id; linhas → LabelRead
lib/Utils/packageSession.dart      NOVO  contagem pura: somar, deduplicar, remover, totais
lib/screens/packageReader.dart     NOVO  câmera, fina (o padrão de scanFriend.dart)
lib/services/textReader.dart       NOVO  o canal de OCR: contrato e leitura defensiva
lib/widget/packageCounterBar.dart  NOVO  a barra
lib/widget/packageList.dart        NOVO  a lista da sessão (remover, corrigir tipo)
lib/widget/packageReview.dart      NOVO  a revisão antes de salvar
lib/model/newRouteModal.dart             pacotesPorBairro (+ withProvision)
lib/screens/addIter.dart                 carrega, reconcilia e grava pacotesPorBairro
lib/Utils/routeStats.dart                _attributeByBairro; índice usa o exato
lib/Utils/insucessoBairro.dart           só o comentário: as regras servem às duas distribuições
lib/screens/graficsScreen.dart           rodapé do card de índice
lib/widget/routeSlidable.dart            canReadPackages + a ação no painel da esquerda
lib/screens/listIterScreen.dart          abre o leitor, Desfazer
lib/controller/routeController.dart      startWithPackages / restore
ios/Runner/TextReader.swift        NOVO  o canal no iOS: Vision, conversão para pixels
ios/Runner/AppDelegate.swift             registra o canal junto dos plugins (UIScene)
ios/Runner.xcodeproj                     TextReader.swift nos quatro pontos
ios/Runner/Info.plist                    NSCameraUsageDescription cita as etiquetas
android/app/build.gradle.kts             com.google.mlkit:text-recognition
android/.../MainActivity.kt              o canal no Android
```

## Code style

O contrato do parser — tipos próprios, nada de ML Kit na assinatura:

```dart
/// O que uma etiqueta do Mercado Livre disse, já sem nada que identifique quem
/// vai receber. CEP e número só existem dentro de [stopKey], e [stopKey] só
/// existe na memória da sessão.
class LabelRead {
  const LabelRead({
    required this.shipmentId,
    this.type,
    this.bairro,
    this.rawBairro,
    this.stopKey,
  });

  final String shipmentId;

  /// `null` = a letra não foi lida. Nunca um palpite.
  final PackageType? type;

  /// Sempre um nome de `fortaleza_bairros`, ou `null`.
  final String? bairro;

  /// O que o OCR leu depois da vírgula, para a revisão mostrar o que não casou.
  final String? rawBairro;

  final String? stopKey;
}

enum PackageType { residencial, comercial, agencia }

/// Uma linha de texto com a posição dela no quadro. Tipo próprio para o parser
/// ser testado com as linhas reais das fotos, sem câmera.
class OcrLine {
  const OcrLine(this.text, this.box);
  final String text;
  final Rect box;
}

String? shipmentIdFromQr(String raw);

LabelRead readLabel({
  required String shipmentId,
  required List<Offset> qrCorners,
  required List<OcrLine> lines,
});
```

`switch` sobre `PackageType` sem `default`, como os de `StatusRoute`. Arquivos
em camelCase, textos em pt-BR, comentário explicando o porquê.

## Testes

**Unidade, `packageLabel_test.dart`** — fixtures com as linhas e posições
reais das duas fotos:

- foto 1: bairro na linha seguinte ao endereço → `Papicu`, `R`;
- foto 2: `CEF.` no lugar de `CEP`, `Complemeato` → `Meireles`, `R`, CEP lido;
- a mesma etiqueta sem a linha do `R` → `type == null`, nunca `residencial`;
- um `A` solto **fora** da janela abaixo do QR → ignorado;
- bairro fora da lista → `bairro == null`, `rawBairro` preenchido;
- `Meirelles` → `Meireles` (fuzzy único); `Praia do Futuro Il` → `null` (empate);
- QR do convite do iter e QR qualquer → `shipmentIdFromQr == null`;
- endereço sem número → `stopKey == null`.

**Unidade, `packageSession_test.dart`:** mesmo `id` duas vezes conta uma;
remover devolve o total e tira o bairro que ficou sem pacote; dois pacotes com
a mesma `stopKey` são uma parada; `stopKey` nula é parada própria; "?" conta no
total e em nenhum tipo; corrigir o tipo move entre as contagens; bairros saem
ordenados por quantidade; `pacotesPorBairro` só tem bairros da lista.

**Unidade, `routeStats_test.dart`:** o teste existente dos 24/24 continua
verde sem mudança; com `pacotesPorBairro {Aeroporto: 40, Vila União: 8}` dá
40 e 8; distribuição parcial rateia só o resto; distribuição citando bairro
que a rota não tem é descartada; a soma dos pacotes no índice bate com
`packages`.

**Modelo e formulário:** `withProvision` preserva `pacotesPorBairro`;
`toMap`/`fromMap` vão e voltam; editar uma rota lida no `AddIter` e salvar sem
tocar em nada mantém a distribuição; trocar para Sem Rota a zera; tirar um
bairro no formulário tira a parte dele.

**Widget:** `routeSlidable_test.dart` — a ação aparece em Agendado + Mercado
Livre e em nenhuma das outras 14 combinações de status × empresa; "Pagar"
continua só em Concluído. `packageCounterBar_test.dart` — A e C usam o estilo
de destaque (a **causa**, por chave/estilo, não a cor do pixel — ver "Widget
tests cannot tell you whether text fits" no CLAUDE.md); o "?" só aparece com
pacote sem letra. `packageList_test.dart` — deslizar remove, tocar no tipo
corrige. `packageReview_test.dart` — Salvar desabilitado com zero pacotes;
bairros não reconhecidos listados.

**No aparelho, no CD** — o que nenhum teste alcança: uma carga real de pelo
menos 30 etiquetas, com **C e A entre elas**, anotando quantas saíram sem
letra e sem bairro.

## Boundaries

- **Sempre:** o bairro gravado é um nome de `fortaleza_bairros`; o `id` do QR
  deduplica; letra não lida é `null` e aparece como "?"; `update` só com os
  cinco campos, montados pela mesma função no salvar e no desfazer;
  `flutter analyze` e `flutter test` antes de cada commit.
- **Perguntar antes:** qualquer campo além de `pacotesPorBairro`; qualquer
  dependência além do OCR (inclusive trocar o `mobile_scanner` pelo `camera`
  se a medição da tarefa 8 pedir); abrir o leitor para Amazon ou Shopee;
  gravar o `id` do envio.
- **Nunca:** gravar imagem, nome, endereço, CEP ou complemento; mandar quadro
  para a nuvem; logar texto de OCR; chutar a letra; deixar um bairro fora da
  lista entrar em `adress`; trocar o status por qualquer caminho que não seja
  Agendado → Em rota.

## Critérios de sucesso

1. A ação "Ler pacotes" só aparece em rota Agendada do Mercado Livre (teste de
   widget nas 15 combinações).
2. A mesma etiqueta lida 10 vezes seguidas conta 1.
3. As duas fotos do pedido, pelo parser, dão `Papicu/R` e `Meireles/R`.
4. Na carga real de ≥ 30 etiquetas: ≥ 95% com bairro e ≥ 90% com letra sem
   intervenção, e **nenhuma** letra errada (não lida é aceitável; errada não).
5. Uma leitura não espera mais de 1 s entre o QR enquadrado e o cartão na
   tela, num Android intermediário.
6. Salvar deixa a rota Em rota com os cinco campos, e nenhum outro campo do
   documento mudou (provisão, valor, clima, horários).
7. Desfazer devolve os cinco campos ao que eram.
8. Concluir a rota pelo formulário depois da leitura mantém `pacotesPorBairro`,
   e o índice de insucesso por bairro usa os números lidos.
9. Nenhum arquivo de quadro sobra no diretório temporário depois da sessão.

## Decidido

Fechado em 2026-10-06, respondendo às seis perguntas do rascunho:

1. **Pacotes por bairro: sim**, gravado e consumido pelo índice na mesma
   entrega — ver a seção própria acima.
2. **Bairros lidos substituem** os marcados no agendamento.
3. **Contagem R/C/A não é gravada.**
4. **Parada = mesmo prédio**: mesmo CEP e número, qualquer apartamento. É como
   o app do Mercado Livre conta.
5. ~~**OCR pelo pacote** `google_mlkit_text_recognition`, não por canal
   nativo.~~ **Revertida no mesmo dia**: o pacote quebrou o simulador iOS, e o
   OCR é canal nativo — Vision no iOS, ML Kit no Android. Ver Desvios.
6. **A agência fechada sai pela lista da sessão**, deslizando. O "modo remover"
   relendo a etiqueta fica para se a lista se mostrar lenta no CD.

## Desvios decididos durante a implementação

**Tarefa 8 — o que o aparelho ensinou (iPhone 13, iOS 26.6, 2026-10-06).** O
canal funciona e o OCR leva 130–700 ms por quadro, dentro do critério 5. As
coordenadas batem: o topo do QR fica na altura do rótulo "Endereço:", como na
etiqueta. Três coisas que as fotos não mostravam, cada uma medida por um
diagnóstico só de posições e sim/não (`labelDiagnostics`, em debug — o texto
lido não vai para log nem lá):

- **A letra é pequena demais.** Com a etiqueta a um palmo, o QR tem ~100 px
  num quadro de 1080×1920 e a tarja ~12 px, branca sobre preto — o Vision nem
  a devolve como texto. Quando o celular chegava perto (QR de ~230 px) ela era
  lida, e caía na janela abaixo do QR. Daí a **segunda olhada**: o canal
  ganhou `readRegion`, que recorta a janela (`letterWindow`), inverte as cores
  e amplia 4× antes do OCR; só roda quando a letra faltou, e leu R e C com QR
  de 96 px.
- **A vírgula some.** O Vision parte a linha do endereço ou lê a vírgula como
  ponto, e o bairro da linha de baixo se perdia. Agora, se o depois da vírgula
  não casar, cada linha do bloco é tentada contra a lista (só nome da lista
  passa), e sem vírgula o número da casa sai da linha do rótulo.
- **Existe um segundo leiaute.** Em etiquetas C, nenhuma linha se parece com
  "Endereço:" (a mais próxima a 5–6 letras de 8) e o CEP fica **à direita** do
  QR. O parser ainda não lê esse modelo — falta uma foto dele.

Também do aparelho: `flutter run` só conectou com o iPhone **no cabo** (sem
fio, a descoberta mDNS falhou duas vezes), e só com o Modo de Desenvolvedor
ligado.

**Tarefa 8 — o overlay, pelo que o entregador pediu ao usar.** ✓ verde no meio
da tela quando conta e ✗ quando lê o que já estava contado (ou foi tirado da
carga) — `ScanMark`, que aparece e some em 0,9 s; o lado de fora da janela
fosco e escuro (`ScanFrame`), dentro nítido; R, C e A do mesmo tamanho numa
linha só, o destaque só de cor; um contador de bairros achados ao lado do A,
sem os "Sem bairro"; e o Finalizar em verde — não azul, que no app é Agendado.

**Tarefa 9 — o ícone do gesto.** A spec pedia "o ícone e a cor de Em rota". O
ícone de Em rota é um carro, que diz "iniciar" e não "ler as etiquetas": ficou
a **cor** de Em rota (o resultado) com `Icons.qr_code_scanner` (o gesto).

**Tarefa 9 — a gravação não espera o servidor.** O "Pagar" (`_changeStatus`)
espera o `update` completar antes de avisar. Sem rede, isso só acontece quando
a rede volta — e a leitura é no CD. `_readPackages` dispara a escrita, avisa na
hora (a lista já mostra Em rota pelo cache local) e só fala de novo se o
servidor recusar.

**Tarefa 1 — versão do pacote (plano A, desfeito).** A spec pedia `^0.17.1`; o `pub get` recusou,
porque a 0.17 exige Dart `^3.12.0` e Flutter `>=3.44`. A 0.16.0 (julho de 2026)
aceita Dart `>=3.8`, usa o mesmo modelo latino e o mesmo piso de iOS 15.5.
Atualizar o Flutter do projeto inteiro por causa de um pacote seria uma
mudança muito maior que a feature; subir para a 0.17 fica para quando o
Flutter subir por outro motivo.

**Tarefa 1 — o simulador derrubou o pacote, e o OCR virou canal nativo.**
Com o `google_mlkit_text_recognition` instalado, `flutter build ios
--simulator` falhou no link, depois de 30 minutos de build limpo:

```
Building for 'iOS-simulator', but linking in object file
(…/MLImage.framework/MLImage[arm64]) built for 'iOS'
```

Os frameworks do ML Kit para iOS são binários com só duas fatias — `x86_64`
(simulador em Mac Intel) e `arm64` **de aparelho**. Não existe a de simulador
para Mac com chip Apple. O contorno conhecido, excluir `arm64` do simulador e
rodar tudo como Intel sob Rosetta, valeria para **todo** build de simulador do
app — inclusive o iPhone 16 Plus onde ficam as contas de teste dos amigos — e
a Apple anunciou o Rosetta só até o macOS 27. Decidido em 2026-10-06, em
conversa: plano B. O pacote saiu, o iOS voltou para 15.0, e os dois parágrafos
abaixo (R8 e tamanho) ficam como registro do que o plano A custava.

As tarefas 2 a 7 foram feitas **enquanto o build da tarefa 1 rodava**, contra o
que este plano dizia ("parar antes da tarefa 2"). Não se perdeu nada porque o
parser recebe `OcrLine` — texto e posição, de qualquer motor — e só a tela da
câmera chamava o pacote, em uma linha. Mas a ordem foi quebrada, e o registro
fica.

**Tarefa 1 — o plano B verificado.** `flutter build ios --simulator --debug`
passou com o `Runner` em `x86_64 arm64` — nativo no Mac com chip Apple, sem
Rosetta. `flutter build apk --release` passou **sem** regra de R8: o
`proguard-rules.pro` do plano A só existia porque o plugin referenciava os
reconhecedores de outros alfabetos, e o `MainActivity.kt` só usa o latino. APK
release arm64: 75,3 MB — o mesmo modelo do plano A, então os mesmos ~13 MB por
aparelho pela Play.

**Tarefa 1 — R8 (plano A, desfeito).** O release Android não compilava: o plugin referencia os
reconhecedores de chinês, devanágari, japonês e coreano, que são artefatos
opcionais e não estão instalados, e o R8 recusa classe ausente. A correção são
quatro `-dontwarn` em `android/app/proguard-rules.pro`, que o plugin Gradle do
Flutter carrega sozinho quando o arquivo existe (`FlutterPlugin.kt`). O arquivo
diz por que é seguro e quando deixa de ser.

**Tarefa 1 — tamanho (plano A; o Android do plano B tem o mesmo modelo).** O APK release arm64 foi de **44,3 MB para 75,2 MB**,
mas o número engana: `--target-platform android-arm64` restringe só o motor do
Flutter, e a biblioteca nativa do OCR entra nas três arquiteturas
(`libmlkit_google_ocr_pipeline.so`: 11,1 MB arm64, 11,6 MB x86_64, 6,8 MB
armeabi-v7a). Pela Play, que entrega por arquitetura, um aparelho arm64 recebe
**~13 MB a mais** (11,1 MB da biblioteca + ~1,5 MB de modelos + ~0,5 MB de
dex). A alternativa que economizaria esses 11 MB é o modelo *não embutido*
(`play-services-mlkit-text-recognition`, baixado pelo Google Play Services no
primeiro uso) — mas o primeiro uso precisaria de sinal, no lugar onde o sinal
não é garantido, e trocar o artefato do plugin pede excluir dependência no
Gradle. Não vale para economizar 11 MB.

## Riscos

- **C e A nunca foram vistos pelo OCR.** Só há amostra de R. A carga de teste
  tem de ter os dois antes de qualquer conclusão sobre a letra.
- **Os cantos do QR e as caixas do OCR podem não estar no mesmo sistema de
  coordenadas.** *Reduzido lendo o código do `mobile_scanner` 7.4: nas duas
  plataformas os cantos são calculados sobre a mesma imagem, já em pé, que o
  plugin devolve em JPEG — rotacionada pelo sensor no Android, com a conexão
  fixa em retrato no iOS. O modo de depuração continua, agora para
  confirmar.* O `mobile_scanner` mede no quadro de análise; o OCR mede no
  JPEG que ele devolve, que pode vir em outra escala ou rotacionado 90°. Se não
  baterem, a janela da letra cai no lugar errado e **nenhuma** letra é lida — o
  lado seguro, mas o leitor vira contador. A tarefa 8 desenha as duas coisas
  sobre a câmera, num modo de depuração, antes de qualquer ajuste fino.
- **Custo do `returnImage`.** Com ele ligado, o plugin codifica JPEG em todo
  quadro com QR. `detectionTimeoutMs` limita a frequência; se ainda assim
  passar de 1 s por leitura, a saída é o pacote `camera` — dependência nova,
  então pergunta antes.
- **Impressão térmica gasta** (a foto 2 já mostra) e **CD mal iluminado**:
  botão de lanterna desde a primeira versão.
- **Sessão só em memória.** Uma ligação longa e o sistema matando o app no
  meio de 80 pacotes perde a leitura. Persistir a sessão localmente pediria
  outra dependência; fica para se acontecer.
- **O Mercado Livre muda a etiqueta.** O parser se ancora em `Endereço:` e na
  tarja abaixo do QR; se o leiaute mudar, a leitura degrada **sem erro**. O
  sinal é a revisão: "40 pacotes sem bairro" diz que algo mudou — por isso
  esse número tem de aparecer, nunca ser escondido.
- **Dois motores de OCR.** O Vision (iOS) leu as fotos; o ML Kit (Android)
  ainda não leu etiqueta nenhuma. Se o Android ler pior, o parser é o mesmo e
  os limiares mudam com dados — não com palpite.
- **A etiqueta removida volta sozinha.** Tirar a agência fechada pela lista e
  fechar a lista com a etiqueta dela ainda na frente da câmera a contaria de
  novo no quadro seguinte. Por isso um pacote removido, lido de novo, mostra
  "foi tirado da carga" com um "Contar de novo" — não volta sem um toque.

## Fora de escopo

- Etiquetas da Amazon e da Shopee (leiaute diferente; outra spec, com fotos).
- Ler o retorno no fim do dia para preencher `insucessoPorBairro` — o mesmo
  leitor faria isso com medição em vez de distribuição manual, e é a
  continuação natural desta feature.
- Ordem de entrega, navegação, mapa.
- Guardar quais envios foram entregues.
- O KM inicial continua sendo digitado no formulário.

---

## Plano

Três blocos, nesta ordem, cada um fechando num checkpoint:

**A. Riscos primeiro (tarefa 1).** A dependência é a única decisão que pode
voltar atrás — se o pod quebrar o simulador ou o build, o plano B (canal
nativo) troca a tarefa 8 inteira. Então ela é verificada antes de qualquer
linha de feature. Nada do resto depende dela para *compilar*, mas tudo depende
dela para *valer a pena*.

**B. O núcleo puro (tarefas 2–5).** Parser, sessão, campo novo e índice: tudo
testável sem câmera e sem Firebase, e é onde moram as regras que quebrariam em
silêncio (dedupe, letra nunca chutada, bairro só da lista, `withProvision`,
`set` do formulário). Ao fim do bloco, o índice por bairro já sabe usar
medição — antes de existir quem a produza, e com todo documento atual dando o
mesmo resultado de hoje.

**C. A tela (tarefas 6–9).** Widgets testáveis primeiro (barra, lista,
revisão), a câmera fina depois, a fiação na lista por último — assim o gesto só
aparece quando há uma tela inteira atrás dele.

**D. Campo (tarefas 10–11).** A carga real no CD decide os limiares (janela da
letra, tentativas, distância do fuzzy); a documentação entra depois, com o que
o campo ensinou.

Paralelizável: 2 e 3 são independentes entre si e da 4; a 6 só precisa da 3.
Sequencial de verdade: 4 → 5, e 8 → 9 → 10.

## Tarefas

- [x] **1. OCR e plataformas** — *refeita no plano B; ver Desvios*
  - Acceptance: canal `iter/ocr` com Vision no iOS e ML Kit (Gradle) no
    Android; nenhuma dependência nova no pubspec, iOS em 15.0; o app compila
    para Android release, para o simulador do Mac e para iPhone;
    `NSCameraUsageDescription` cita as etiquetas; o lado Dart do contrato com
    teste.
  - Verify: `flutter test test/unit/textReader_test.dart`, `flutter analyze`,
    `flutter build ios --simulator --debug`, `flutter build apk --release`
    (R8 sem regra extra) e `df -h` antes de cada build.
  - Files: `lib/services/textReader.dart`, `ios/Runner/TextReader.swift`,
    `ios/Runner/AppDelegate.swift`, `ios/Runner.xcodeproj/project.pbxproj`,
    `android/app/build.gradle.kts`, `MainActivity.kt`, `ios/Runner/Info.plist`

- [x] **2. Parser da etiqueta**
  - Acceptance: `shipmentIdFromQr` e `readLabel` como na seção de regras; os
    casos de `packageLabel_test.dart` listados em Testes, com as linhas reais
    das duas fotos como fixture.
  - Verify: `flutter test test/unit/packageLabel_test.dart`
  - Files: `lib/Utils/packageLabel.dart`, `test/unit/packageLabel_test.dart`

- [x] **3. Sessão de leitura**
  - Acceptance: `PackageSession` pura — adicionar (novo/repetido), definir tipo,
    remover; total, por tipo, "?", paradas, bairros ordenados, `pacotesPorBairro`,
    bairros não reconhecidos com contagem.
  - Verify: `flutter test test/unit/packageSession_test.dart`
  - Files: `lib/Utils/packageSession.dart`, `test/unit/packageSession_test.dart`

- [x] **4. Campo `pacotesPorBairro` no modelo e no formulário**
  - Acceptance: campo no modelo (`fromMap`, `toMap`, `withProvision`); o
    `AddIter` carrega, reconcilia com bairros e `packages` da tela, e zera na
    Sem Rota; os testes de modelo e formulário listados em Testes.
  - Verify: `flutter test test/unit/routeProvision_test.dart test/widget/addIter_test.dart`
    e `flutter analyze`
  - Files: `lib/model/newRouteModal.dart`, `lib/screens/addIter.dart`,
    `test/unit/routeProvision_test.dart`, `test/widget/addIter_test.dart`

- [x] **5. Índice por bairro usa a medição**
  - Acceptance: `_attributeByBairro` único servindo insucessos e pacotes; o
    teste dos 24/24 verde **sem edição**; os casos novos de `routeStats_test`;
    rodapé do card atualizado; comentário de `insucessoBairro.dart` dizendo que
    as regras servem às duas distribuições.
  - Verify: `flutter test test/unit/routeStats_test.dart test/widget/failureRateCard_test.dart`
  - Files: `lib/Utils/routeStats.dart`, `lib/Utils/insucessoBairro.dart`,
    `lib/screens/graficsScreen.dart`, `test/unit/routeStats_test.dart`

  **Checkpoint B:** `flutter test` inteiro verde (fora o `widget_test.dart` de
  sempre) e `flutter analyze` limpo. Nada visível mudou para o usuário ainda.

- [x] **6. Barra e lista da sessão**
  - Acceptance: `PackageCounterBar` com total, paradas, R, C destacado, A mais
    destacado, "?" só quando houver; `PackageList` com deslizar para remover e
    tocar para corrigir o tipo.
  - Verify: `flutter test test/widget/packageCounterBar_test.dart test/widget/packageList_test.dart`
  - Files: `lib/widget/packageCounterBar.dart`, `lib/widget/packageList.dart`,
    e os dois testes

- [x] **7. Revisão antes de salvar**
  - Acceptance: pacotes e paradas editáveis, bairros pelo
    `showBairrosMultiSelect`, não reconhecidos listados com a contagem, Salvar
    desabilitado com zero, "Voltar a ler".
  - Verify: `flutter test test/widget/packageReview_test.dart`
  - Files: `lib/widget/packageReview.dart`, `test/widget/packageReview_test.dart`

- [ ] **8. Tela da câmera** — *escrita e compilando nas duas plataformas; falta rodar no aparelho*
  - Acceptance: `mobile_scanner` com `returnImage` e só QR; OCR um por vez,
    com tentativas, arquivo temporário apagado em `finally`; cartão da última
    leitura, botões R/C/A, vibração (mais forte no A), lanterna, confirmação
    ao sair; modo de depuração que desenha cantos do QR e caixas do OCR.
    Nenhum `debugPrint` de texto lido.
  - Verify: `flutter analyze`; no iPhone, as duas fotos do pedido na tela do
    computador lidas como `Papicu/R` e `Meireles/R`; o modo de depuração
    mostra a janela da letra sobre a tarja; tempo por leitura anotado
    (critério 5).
  - Files: `lib/screens/packageReader.dart` (e ajustes pontuais em 2/3 se a
    câmera ensinar algo que as fotos não ensinaram)

- [x] **9. Gesto, gravação e desfazer**
  - Acceptance: `RouteSlidable.canReadPackages`; ação "Ler pacotes" com o ícone
    e a cor de Em rota; `RouteController.startWithPackages` e `restore`
    montando os cinco campos pela mesma função; a lista abre o leitor, grava,
    avisa e desfaz.
  - Verify: `flutter test test/widget/routeSlidable_test.dart test/unit/routeController_test.dart`;
    no aparelho, salvar e desfazer uma rota de teste e conferir o documento no
    console (critérios 6 e 7).
  - Files: `lib/widget/routeSlidable.dart`, `lib/controller/routeController.dart`,
    `lib/screens/listIterScreen.dart`, e os dois testes

  **Checkpoint C:** a feature inteira funciona no aparelho com etiquetas de
  teste. Antes do CD.

- [ ] **10. Carga real no CD**
  - Acceptance: ≥ 30 etiquetas, com C e A; taxas de bairro e letra anotadas
    nesta spec; nenhuma letra errada; limiares ajustados com os dados (cada
    ajuste vira caso de teste na tarefa 2).
  - Verify: os critérios 4, 5 e 9.
  - Files: `docs/specs/leitor-de-pacotes.md`, e o que os ajustes pedirem

- [ ] **11. Documentação**
  - Acceptance: seção no `CLAUDE.md` com o que não é óbvio (o QR não traz
    endereço; dados de terceiros nunca ficam; `pacotesPorBairro` e os dois
    caminhos que o apagariam; o mesmo `_attributeByBairro` para os dois lados);
    status desta spec atualizado.
  - Verify: leitura.
  - Files: `CLAUDE.md`, `docs/specs/leitor-de-pacotes.md`
