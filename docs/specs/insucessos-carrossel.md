# Spec: Carrossel de Insucessos

Status: **implementada** · Criada em 2026-08-02 · Card único de índice acrescentado em 2026-08-03

Complementa `docs/specs/graficos.md`, que passa a ter a seção **Layout**
desatualizada e precisa ser corrigida junto.

## Objetivo

Hoje as métricas de insucesso estão espalhadas: duas dentro do carrossel de
**Empresas** (páginas 3 e 4) e uma dentro do de **Bairros** (página 2). Quem
roda as rotas acompanha insucesso como um assunto só — e para comparar "onde"
com "em que tempo" precisa hoje arrastar dois carrosséis diferentes e lembrar do
número anterior.

Este spec junta as três num carrossel dedicado, acrescenta o eixo novo (**por
clima**, possível desde que a rota passou a gravar `weather`) e o coloca logo
depois dos cards de dinheiro.

Sucesso = o entregador olha um carrossel só e responde: *qual empresa dá mais
problema, em que bairro, e com que tempo* — trocando de recorte sem sair do
lugar.

## Tech Stack

Flutter 3.41.4 / Dart `^3.11.1`. Sem dependência nova: `BarRankChart`,
`ChartCarousel` e `RankEntry` já existem e não mudam de contrato.

## Comandos

```bash
flutter analyze lib/ test/                    # sem error/warning novo
flutter test test/unit/routeStats_test.dart
flutter test test/widget/chartCarousel_test.dart
flutter test                                  # widget_test.dart já falhava antes
flutter run -d <simulador>                    # conferir no aparelho
```

## Estrutura

```
lib/Utils/routeStats.dart        → FailureRate + failuresPerWeather +
                                   failureRatePerWeather/Bairro (novos);
                                   failureRatePerCompany passa a devolver FailureRate
lib/widget/failureRateCard.dart  → o card de índice dos três eixos (novo)
lib/widget/chartCard.dart        → ChartProgressBar (era privado do summaryCards)
lib/widget/summaryCards.dart     → usa o ChartProgressBar compartilhado
lib/screens/graficsScreen.dart   → _insucessoPages (novo); _companyPages e _bairroPages encolhem
lib/widget/chartCarousel.dart    → esconde as bolinhas quando há uma página só
test/unit/routeStats_test.dart   → grupos "rankings por clima" e "índice por bairro"
test/widget/failureRateCard_test.dart → novo
test/widget/chartCarousel_test.dart   → novo
docs/specs/graficos.md           → seção Layout atualizada
```

`failureRatePerCompany` mudou de `List<RankEntry>` para `List<FailureRate>`
porque o card mostra a conta junto da taxa ("6,3% — 3 de 48 pacotes"): a
porcentagem sozinha não distingue 1 em 8 de 125 em 1000, e é essa diferença que
decide se vale agir. Os três eixos usam o mesmo tipo.

`ChartProgressBar` saiu de dentro do `summaryCards.dart` para o `chartCard.dart`,
que já é a casa do vocabulário compartilhado (`ChartStat`, `ChartEmpty`): agora
dois cards desenham a mesma barra.

## Layout

Antes → depois:

```
ANTES                                DEPOIS (revisto em 2026-08-24)
Resumo do período (4 págs)           Resumo do período (4 págs)
                                     ── Análise das rotas concluídas e pagas
Análise das rotas concluídas e pagas   Empresas          (4 págs)
  Empresas          (4 págs)             valor
    valor                                rotas
    rotas                                pacotes                   ← novo
    insucessos por empresa   ──┐          paradas                   ← novo
    índice de insucesso      ──┤        Bairros           (1 pág)
  Bairros           (2 págs)   │          mais rodados
    mais rodados               │        Tempo             (2 págs)
    com insucesso            ──┘      ── Insucessos ──── fundo laranja
  Tempo             (2 págs)            Insucessos por empresa   (un.)
                                        Bairros com insucesso    (un.)
                                        Insucessos por clima     (un.)
                                        Índice de insucesso      (%)
                                          Empresa · pior
                                          Bairro  · pior
                                          Clima   · pior
```

**O carrossel de insucessos fecha a tela**, e não abre o miolo dela. A primeira
versão o punha em segundo, com o argumento de ser o que se acompanha todo dia —
mas ele é o único bloco de notícia ruim, e começar por ele enterrava o dinheiro
e a análise embaixo. No fim, o fundo laranja o separa do resto sem precisar de
aviso nenhum.

As três primeiras páginas são **quantidade**, uma por eixo; a última é o
**índice** dos três eixos juntos. Índice e quantidade respondem coisas
diferentes — "quanto aconteceu" e "quão ruim foi" —, e separá-los assim evita
que a página de porcentagem pareça repetição da anterior.

O card de índice mostra **o pior de cada eixo**, não todos os itens: a pergunta
que se faz olhando aquilo é "onde dói mais", e uma lista de três empresas mais
três bairros mais três climas responderia isso pior. Cada linha é uma barra
horizontal no estilo da "Taxa de entrega" do resumo, com o valor e a conta ao
lado (`12,5% (2 de 16)`).

A escala das barras é **relativa ao pior dos três**, não 0–100: com índices
baixos (2%, 6%, 12%) uma régua absoluta deixaria as três visualmente idênticas e
vazias. O número em porcentagem ao lado é que diz o valor real. Se não houver
insucesso nenhum, nenhuma barra enche — zero dividido por zero não pode virar
barra cheia.

O carrossel de Insucessos ganha rótulo de seção próprio — **"Insucessos das
rotas concluídas e pagas"** — porque usa o mesmo recorte `realized` do bloco de
análise e está separado dele por dois outros carrosséis. Sem o rótulo, quem
chega rolando ao fim da tela não teria como saber que aqueles números excluem
rota agendada.

### O fundo laranja

`ChartPalette.alerta` é o complementar do azul na roda de cores, **nos mesmos
degraus do Material** que o azul usa (900 / 700 / 400): o antagonismo sai da
construção, não de tentativa e erro.

A paleta é o conjunto inteiro — gradiente, barras e barra de progresso — e não
só o fundo. Trocar apenas o gradiente deixaria as barras erradas: elas foram
escolhidas **contra o azul**, e o salmão (`#FF8A80`) sobre laranja é a mesma cor
duas vezes.

As quatro cores de barra do laranja não foram escolhidas no olho. Passaram no
validador de paleta em croma, separação sob daltonismo (protan/deutan), piso de
visão normal e contraste contra a superfície. A única checagem que elas
"reprovam" é a faixa de luminosidade, calibrada para superfície neutra quase
preta — sobre laranja vivo a barra precisa justamente sair dessa faixa para
contrastar.

Medido no mesmo validador: a paleta **azul** falha o piso de visão normal — o
verde e o ciano dos dois primeiros degraus ficam a ΔE 11,2, abaixo de 15, e o
salmão tem 2,02:1 de contraste contra o fundo. Está anotado aqui em vez de
corrigido porque repintar o card azul é mudança visível que ninguém pediu.

Altura 340, igual aos outros dois de barras.

Com Bairros caindo para uma página, `ChartCarousel` passa a **esconder a linha
de bolinhas quando há só uma** — uma bolinha solitária sugere que existe algo
para arrastar quando não existe.

## Dados

O eixo novo lê `NewRouteModal.weather` (`String?`), gravado desde o cadastro com
seletor manual. Regras:

| Situação | Como conta |
|---|---|
| rota com `weather` | insucesso **inteiro** da rota vai para aquele clima |
| rota sem `weather` (ou vazio) | fica fora do ranking |
| clima que apareceu no período sem insucesso | aparece **zerado** |
| índice: rota sem `packages` | fica fora, como já acontece no índice por empresa |

Não há rateio como em bairro: uma rota tem **um** clima, então a atribuição é
exata. Bairro precisa ratear porque uma rota passa por vários.

Clima sem insucesso aparecendo zerado segue a mesma decisão de
`failuresPerCompany`: são poucos climas e "no sol não deu problema nenhum" é
informação. Bairro é que fica de fora quando zerado: são mais de cem.

O eixo é o **céu, não a hora**. Desde 2026-08-22 o app grava Noite limpa e
Noite nublada, mas `_weatherLabelOf` passa o tipo por `daytimeOf` antes de
rotular, então elas somam com Sol e Nublado num degrau só. O motivo é este
gráfico: rota noturna cadastrada antes daquela data está gravada como `clouds`
e o clima gravado nunca é reinterpretado, de modo que separar os rótulos
partiria uma população em dois degraus menores por data de cadastro — e com
`maxBars: 4` aqui e só o primeiro colocado no card de índice, o pior clima podia
sumir da tela por ter sido dividido. A lua continua no card da rota, onde a hora
é informação.

O rótulo sai de `weatherLabel(WeatherType.fromString(weather))`, então o gráfico
mostra "Chuva forte" e não `heavyRain`.

### Índice por bairro é estimativa, não medição

Não existe "pacotes do Aeroporto": `packages` é da rota inteira. Para ter um
índice por bairro, `failureRatePerBairro` divide os pacotes da rota **por igual**
entre os bairros dela — uma rota de 48 pacotes em 2 bairros vira 24 para cada,
mesmo que na prática tenham sido 40 e 8.

O numerador é melhor que o denominador: usa a distribuição de insucesso que o
usuário informou e rateia só o resto, a mesma regra de `failuresPerBairro` (a
atribuição está extraída em `_attributeFailures`, para as duas não divergirem no
primeiro ajuste).

Por isso o card carrega a ressalva no rodapé. Sem ela, um número aproximado
passaria a ser lido como medido.

**Estado inicial esperado:** `weather` começou a ser gravado hoje, então as duas
páginas de clima nascem vazias até existirem rotas novas concluídas. A mensagem
de vazio diz isso com todas as letras, em vez do genérico "sem dados".

## Estilo de código

Funções puras em `routeStats.dart`, na convenção do arquivo (recebe lista já
filtrada, devolve `List<RankEntry>` ordenada):

```dart
/// Insucessos por clima da rota.
///
/// Sem rateio, ao contrário de [failuresPerBairro]: uma rota tem um clima só,
/// então o insucesso dela é inteiro daquele tempo. Rota sem clima informado não
/// entra — atribuir a algum seria inventar o dado.
List<RankEntry> failuresPerWeather(List<NewRouteModal> routes) { … }
```

Textos novos em pt-BR. `withValues(alpha:)` se precisar de cor.

## Estados de vazio

| Página | Mensagem |
|---|---|
| Insucessos por clima | "Nenhuma rota do período informou o tempo." + "O clima passou a ser gravado nas rotas novas." |
| Índice — linha sem dado | cada eixo explica o próprio motivo, no lugar da barra: "Sem pacotes informados no período." / "Sem rota com bairro e pacotes informados." / "Sem rota com tempo e pacotes informados." |
| As duas que mudaram de lugar | mantêm as mensagens que já têm |

O card de índice **nunca fica inteiro vazio**: cada linha some sozinha. Se só o
clima falta, empresa e bairro continuam respondendo.

## Estatísticas de cada página

| Página | Barras | Stats |
|---|---|---|
| Insucessos por empresa | quantidade | TOTAL · MAIOR · MENOR |
| Bairros com insucesso | quantidade (rateada) | BAIRROS · TOTAL · MAIOR |
| Insucessos por clima | quantidade | TOTAL · CLIMAS · MAIOR |
| Índice de insucesso | 3 barras horizontais | GERAL |

`GERAL` é o índice do período inteiro — a régua para ler cada linha como "acima
ou abaixo da minha média".

## Estratégia de teste

`test/unit/routeStats_test.dart`, grupo novo "rankings por clima" — funções
puras, sem Firebase, como o resto do arquivo:

- [ ] soma os insucessos das rotas de cada clima
- [ ] clima que rodou sem insucesso aparece zerado
- [ ] rota sem clima informado não entra
- [ ] lê o clima gravado com `fromString` (`heavyRain` → "Chuva forte")
- [ ] índice é percentual sobre os pacotes daquele clima
- [ ] clima sem pacotes informados fica fora do índice
- [ ] lista vazia não divide por zero

Grupo "índice por bairro", onde mora o rateio dos dois lados:

- [ ] os pacotes da rota são divididos por igual entre os bairros
- [ ] o numerador respeita a distribuição informada, sem ratear
- [ ] sem distribuição, o insucesso é rateado como no ranking
- [ ] bairro com pacotes e sem insucesso aparece zerado
- [ ] rota sem pacotes ou sem bairro fica fora
- [ ] a soma dos insucessos rateados bate com o total da rota

`test/widget/failureRateCard_test.dart` (novo):

- [ ] mostra o pior de cada eixo, com a conta ao lado
- [ ] a barra é relativa ao pior índice, não a 0–100
- [ ] sem insucesso nenhum, nenhuma barra enche
- [ ] eixo sem dado explica o motivo em vez de mostrar 0%
- [ ] sem pacotes no período, o GERAL vira travessão
- [ ] número rateado do bairro não vira dízima na tela

`test/widget/chartCarousel_test.dart` (novo):

- [ ] com duas páginas ou mais, desenha uma bolinha por página
- [ ] com uma página só, não desenha bolinha nenhuma

A composição da tela (ordem dos carrosséis) é verificada no simulador: a
`GraficsScreen` precisa de um `User` do Firebase e não sobe em teste de widget.

## Fronteiras

- **Sempre:** `flutter analyze` e testes antes de commitar; texto em pt-BR;
  agregação nova entra como função pura em `routeStats.dart`, nunca dentro do
  widget.
- **Perguntar antes:** mudar o recorte `realized`; mexer no `BarRankChart`;
  alterar como o insucesso por bairro é rateado; gravar campo novo na rota.
- **Nunca:** duplicar as páginas (sair de um carrossel *e* ficar no outro);
  inventar clima para rota que não informou; deixar clima virar rótulo cru
  (`heavyRain`) na tela.

## Critérios de sucesso

Verificado no simulador (iPhone 16 Plus, iOS 18.6):

- [x] Existe um carrossel "Insucessos" com 4 páginas, logo após os cards de
      dinheiro.
- [x] A página de clima mostra a mensagem de vazio explicando que o clima passou
      a ser gravado agora (antes de existir rota com tempo).
- [x] O card de índice mostra as três linhas com o pior de cada eixo, a conta ao
      lado e as barras em escala relativa.
- [x] Rota concluída com clima e insucesso aparece no eixo de clima com o rótulo
      em pt-BR ("Clima · Chuva").

Verificado por teste:

- [x] `flutter analyze lib/ test/` sem error/warning novo.
- [x] `flutter test test/unit/ test/widget/`: 189 passando.
- [x] Bairros, com uma página só, não mostra bolinha (`chartCarousel_test`).

Falta conferir na mão:

- [ ] Rolar até Empresas e Bairros e confirmar que nenhuma métrica de insucesso
      sobrou neles (a rolagem sintética do simulador não funciona neste
      ambiente).

## Questões em aberto

- Rotas antigas (sem clima) ficam invisíveis nesse eixo. Se um dia isso incomodar,
  a saída não é inventar um balde "Sem informar" no ranking — é mostrar, no
  rodapé do card, quantas rotas do período ficaram de fora. Fora do escopo agora.
- Índice por clima com poucas rotas oscila muito (uma rota de 8 pacotes com 1
  insucesso = 12,5%). Se virar problema, o caminho é um mínimo de pacotes para
  entrar no ranking — mas é cedo para escolher esse número.
