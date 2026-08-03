# Spec: Carrossel de Insucessos

Status: **proposta** · Criada em 2026-08-02 · Aguardando aprovação

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
lib/Utils/routeStats.dart        → failuresPerWeather + failureRatePerWeather (novos)
lib/screens/graficsScreen.dart   → _insucessoPages (novo); _companyPages e _bairroPages encolhem
lib/widget/chartCarousel.dart    → esconde as bolinhas quando há uma página só
test/unit/routeStats_test.dart   → grupo "rankings por clima"
test/widget/chartCarousel_test.dart → novo
docs/specs/graficos.md           → seção Layout atualizada
```

## Layout

Antes → depois:

```
ANTES                                DEPOIS
Resumo do período (4 págs)           Resumo do período (4 págs)
                                     ── Insucessos ────────────────
Análise das rotas concluídas e pagas   Insucessos por empresa   (un.)
  Empresas          (4 págs)           Bairros com insucesso    (un.)
    valor                              Insucessos por clima     (un.)   ← novo
    rotas                              Índice de insucesso      (%)     ← card único
    insucessos por empresa   ──┐          Empresa · pior
    índice de insucesso      ──┤          Bairro  · pior              ← novo
  Bairros           (2 págs)   │          Clima   · pior              ← novo
    mais rodados               │     ── Análise das rotas concluídas e pagas
    com insucesso            ──┘       Empresas          (2 págs)
  Tempo             (2 págs)             valor
                                         rotas
                                       Bairros           (1 pág)
                                         mais rodados
                                       Tempo             (2 págs)
```

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
análise, mas agora aparece antes dele. Sem o rótulo, o "Análise das rotas
concluídas e pagas" que hoje explica esse recorte ficaria depois de um carrossel
que também depende dele.

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
`failuresPerCompany`: são poucos climas (sete), e "no sol não deu problema
nenhum" é informação. Bairro é que fica de fora quando zerado — são mais de cem.

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
| Índice por clima | "Nenhuma rota do período tem tempo **e** pacotes informados." + "Sem pacotes não há como calcular o índice." |
| As três que mudaram de lugar | mantêm as mensagens que já têm |

## Estatísticas de cada página

| Página | Barras | Stats |
|---|---|---|
| Insucessos por empresa | quantidade | TOTAL · MAIOR · MENOR |
| Índice por empresa | % | GERAL · MAIOR · MENOR |
| Bairros com insucesso | quantidade (rateada) | BAIRROS · TOTAL · MAIOR |
| Insucessos por clima | quantidade | TOTAL · CLIMAS · MAIOR |
| Índice por clima | % | GERAL · MAIOR · MENOR |

`GERAL` nas duas páginas de índice é o mesmo número — o índice do período
inteiro. É a régua: serve para ler cada barra como "acima ou abaixo da minha
média", e ter duas réguas diferentes na mesma pilha de páginas confundiria mais
do que ajudaria.

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

- [ ] Existe um carrossel "Insucessos" com 5 páginas, logo após os cards de
      dinheiro.
- [ ] Empresas ficou com 2 páginas (valor, rotas) e Bairros com 1 (mais
      rodados) — nenhuma métrica de insucesso sobrou neles.
- [ ] Bairros, com uma página só, não mostra bolinha.
- [ ] As páginas de clima mostram a mensagem de vazio explicando que o clima
      passou a ser gravado agora.
- [ ] Cadastrando uma rota concluída com clima e insucesso, ela aparece nas duas
      páginas de clima com o rótulo em pt-BR.
- [ ] `flutter analyze lib/ test/` sem error/warning novo.
- [ ] `flutter test test/unit/ test/widget/` passa.

## Questões em aberto

- Rotas antigas (sem clima) ficam invisíveis nesse eixo. Se um dia isso incomodar,
  a saída não é inventar um balde "Sem informar" no ranking — é mostrar, no
  rodapé do card, quantas rotas do período ficaram de fora. Fora do escopo agora.
- Índice por clima com poucas rotas oscila muito (uma rota de 8 pacotes com 1
  insucesso = 12,5%). Se virar problema, o caminho é um mínimo de pacotes para
  entrar no ranking — mas é cedo para escolher esse número.
