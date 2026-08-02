# Spec: Insucesso por bairro

Status: **implementada** · Criada em 2026-08-01 · Falta verificar no simulador

## Objetivo

Deixar o entregador dizer **em qual bairro** cada insucesso aconteceu, em vez de
o app adivinhar rateando.

Hoje `NewRouteModal` guarda uma lista de bairros e um único `insucessoQnt`. O
card "Bairros com insucesso" divide esse número igualmente entre os bairros da
rota (`docs/specs/graficos.md`, Decisão 2), porque o dado de qual bairro falhou
nunca foi coletado. O rateio mantém o total certo, mas o ranking é um chute
distribuído: três insucessos todos na Barra do Ceará aparecem como 1,0 em cada
um de três bairros.

Esta spec paga essa dívida — que já estava registrada como "precisão real exige
registrar insucesso por bairro no `addIter`".

Usuário: o entregador. Sucesso = o ranking de bairros com insucesso passa a
apontar o bairro certo, e ele consegue decidir onde tomar cuidado.

## Fluxo

No card "Opcionais" do `addIter`, com o switch de insucesso **ligado** e **mais
de um bairro** selecionado, aparece um campo abaixo de "Bairros":

```
┌ Bairros ──────────────────  Aldeota + 2  ▾ ┐
└────────────────────────────────────────────┘
┌ Onde foram os insucessos? ───── 3 de 5  ▾ ┐   ← novo
└────────────────────────────────────────────┘
```

Tocar abre um sheet igual ao de bairros, mas listando **só os bairros já
escolhidos** e trocando o checkbox por um seletor de quantidade:

```
        Onde foram os insucessos?
        ┌──────────────────────────┐
        │ Restam 2 de 5            │
        └──────────────────────────┘

  Aldeota                    ─   2   +
  Centro                     ─   1   +
  Cocó                       ─   0   +

        ┌──────────────────────────┐
        │        Confirmar         │
        └──────────────────────────┘
```

O `+` de cada bairro trava quando não resta insucesso para distribuir. Sem
busca: a lista tem no máximo os bairros da rota.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1 · cloud_firestore 6.7.1. **Nenhuma dependência
nova.** `setState`, como no resto do app.

## Comandos

```bash
flutter pub get
flutter run
flutter analyze lib/
flutter test test/unit/insucessoBairro_test.dart
flutter test test/unit/routeStats_test.dart
flutter test
```

## Estrutura

```
lib/model/newRouteModal.dart       → campo insucessoPorBairro + serialização
lib/Utils/insucessoBairro.dart     → regras de distribuição, puras (novo)
lib/widget/selectInsucessoBairro.dart → o sheet com os seletores (novo)
lib/screens/addIter.dart           → o novo campo e o preenchimento na edição
lib/Utils/routeStats.dart          → failuresPerBairro passa a usar o exato
lib/widget/routeCard.dart          → detalhe mostra a distribuição
test/unit/insucessoBairro_test.dart  → as regras (novo)
test/unit/routeStats_test.dart       → o novo comportamento do ranking
```

`insucessoBairro.dart` separado porque as regras chatas (cortar excesso,
descartar bairro removido, calcular o que resta) precisam valer **em três
lugares**: no sheet enquanto o usuário mexe, no `addIter` ao salvar, e no
`routeStats` ao ler documento antigo. Regra duplicada em três lugares diverge no
primeiro ajuste.

## Dados

Campo novo em `iter/{uid}/routes/{routeId}`:

```json
"insucessoPorBairro": [
  {"bairro": "Aldeota", "qnt": 2},
  {"bairro": "Centro",  "qnt": 1}
]
```

**Array de map, e não `{"Aldeota": 2}`.** Nenhum dos 123 bairros de
`Utils/bairros.dart` tem hoje ponto, barra ou colchete, mas chave de mapa com
esses caracteres quebra field path no Firestore, e um "Pref. José Walter"
entrando na lista amanhã viraria um bug silencioso. O array também é o mesmo
formato de `adress`, que já está ali ao lado.

Só entram bairros com `qnt > 0` — bairro zerado não vira registro.

Campo **opcional**: ausente ou vazio significa "não distribuído", e é o que todo
documento já gravado tem.

## Regras de distribuição

**Só aparece com switch ligado e 2+ bairros.** Com um bairro só não há escolha:
ao salvar, todos os insucessos vão para ele automaticamente, sem campo nenhum na
tela. Atribuição exata de graça.

**Distribuição parcial é permitida, e o resto é rateado.** "2 foram na Aldeota,
o resto não lembro" é uma resposta legítima e melhor que nenhuma. Os 2 contam
exato; os 3 restantes se dividem entre **todos** os bairros da rota, como hoje.
O total do ranking continua batendo com o total de insucessos, sempre.

**Baixar o total corta o excesso do fim.** Distribuiu 5 e voltou o total para 3:
reduz a partir do último bairro da lista até caber. Preserva o começo do que ele
marcou e a soma nunca passa do total.

**Bairro removido da rota some da distribuição.** Tirou a Aldeota de "Bairros"
depois de marcar 2 nela: aqueles 2 voltam a ser "não distribuídos" e entram no
rateio. Deixar um registro órfão faria o ranking citar um bairro que a rota não
tem.

## Efeito no gráfico

`failuresPerBairro` passa a decidir **por rota**:

| A rota tem | Como conta |
|---|---|
| distribuição cobrindo todos os insucessos | exato |
| distribuição parcial | exato + rateio do restante |
| sem distribuição (documento antigo) | rateio, como hoje |

As rotas já salvas continuam funcionando sem migração — só não ficam mais
precisas. Nenhuma outra métrica muda: a **taxa** de insucesso (por empresa e no
perfil) usa o total da rota, que não mexeu.

## Estilo de código

Regras como funções puras, no padrão de `routeTime.dart`:

```dart
/// Quantos insucessos ainda não têm bairro.
int remaining(int total, Map<String, int> distribution) =>
    total - distribution.values.fold(0, (sum, qnt) => sum + qnt);

/// Ajusta a distribuição ao que a rota tem hoje: descarta bairro que saiu e
/// corta o excesso do fim quando o total diminuiu.
Map<String, int> reconcile({
  required Map<String, int> distribution,
  required List<String> bairros,
  required int total,
}) { ... }
```

`Map<String, int>` na memória (a ordem de `bairros` manda), array de map só na
serialização. Texto de interface em pt-BR, arquivos em camelCase.

## Estratégia de teste

`test/unit/insucessoBairro_test.dart`:

- `remaining` com distribuição vazia devolve o total;
- `reconcile` descarta bairro que saiu de `adress` e devolve a quantidade dele
  para o "restante";
- `reconcile` corta do fim quando o total baixou, preservando os primeiros;
- `reconcile` não mexe em distribuição já válida;
- quantidade negativa ou acima do total é recusada;
- serialização ida e volta (`toMap`/`fromMap`), ignorando entrada malformada
  (sem `bairro`, `qnt` nulo, bairro repetido).

`test/unit/routeStats_test.dart` (novos casos):

- rota com distribuição exata: o ranking usa ela, sem rateio;
- rota com distribuição parcial: exato mais rateio do restante, e a soma bate
  com o total de insucessos;
- rota sem distribuição: continua rateando (documento antigo não quebra);
- rota com um bairro só: tudo nele;
- distribuição citando bairro fora de `adress` é ignorada.

O sheet e o campo no formulário ficam em verificação manual, como o resto do
`addIter` — que não tem teste hoje.

## Fronteiras

- **Sempre:** `flutter analyze lib/` limpo; texto em pt-BR; regra em
  `Utils/insucessoBairro.dart`, nunca dentro do `build`; documento antigo
  continua carregando.
- **Perguntar antes:** qualquer dependência nova; mudar `firestore.rules`;
  migrar/reescrever documentos já gravados.
- **Nunca:** quebrar `fromMap` para quem não tem o campo; remover o rateio (ele
  é o fallback de todo documento antigo).

## Critérios de sucesso

- [ ] Com insucesso ligado e 2+ bairros, o campo aparece; com 0 ou 1 bairro, não.
- [ ] O sheet lista só os bairros da rota, com seletor de quantidade.
- [ ] A soma nunca passa do total: o `+` trava quando não resta nada.
- [ ] O campo mostra o andamento (`3 de 5`) sem precisar abrir.
- [ ] Salvar grava `insucessoPorBairro` como array de map, só com `qnt > 0`.
- [ ] Editar uma rota reabre a distribuição preenchida.
- [ ] Tirar um bairro de "Bairros" tira ele da distribuição.
- [ ] Baixar o total corta o excesso, sem soma maior que o total.
- [ ] Rota com um bairro só grava a distribuição sozinha, sem UI.
- [ ] "Bairros com insucesso" usa o exato quando existe e rateia o restante.
- [ ] Rota antiga, sem o campo, continua aparecendo rateada.
- [ ] `flutter analyze lib/` sem error/warning novo, e os 123 testes seguem
      passando.

## Decisões

**1. Parcial vale, e o restante é rateado.** Exigir a distribuição completa
transformaria um campo opcional em validação bloqueante — 12 insucessos em 6
bairros viram muito toque obrigatório, e o custo de não preencher passaria a ser
não conseguir salvar. Rateando o resto, o total sempre fecha e o dado só melhora
conforme ele quiser detalhar.

**2. Um bairro atribui sozinho.** Não há escolha a fazer, então não há tela a
mostrar. É a única mudança daqui que melhora o dado **sem custo nenhum** para o
usuário.

**3. Array de map.** Chave de mapa com ponto quebra field path no Firestore.
Nenhum bairro tem hoje, mas o array elimina a classe de bug e combina com
`adress`.

**4. Rateio continua existindo.** Ele deixa de ser a regra e vira o fallback:
todo documento já gravado depende dele, e distribuição parcial também. Removê-lo
esvaziaria o ranking de bairros retroativamente.

**5. As regras saem do widget.** Cortar excesso, descartar bairro removido e
contar o que resta valem no sheet, no save e na leitura. Três cópias divergem no
primeiro ajuste — daí `Utils/insucessoBairro.dart`.

## Dívidas e fora de escopo

- **Rotas já salvas não ficam mais precisas.** Não há de onde tirar a
  informação; elas seguem rateadas para sempre. Uma tela de "revisar rotas
  antigas" resolveria, e está fora daqui.
- **Insucesso por bairro não muda a taxa de insucesso** (empresa e perfil), que
  é sobre pacotes e não sobre bairro.
- Motivo do insucesso (ausente, endereço errado, recusa), pacotes e paradas por
  bairro, e mapa de calor.

## Perguntas em aberto

Nenhuma bloqueante. Parcial, bairro único e redução do total foram confirmados
antes desta spec.

---

# Plano de implementação

```
 (1) Utils/insucessoBairro.dart        ← regras puras, teste primeiro
      ├── (2) model/newRouteModal.dart  ← campo + serialização
      │        └── (3) routeStats.dart  ← ranking usa o exato
      └── (4) widget/selectInsucessoBairro.dart
                └── (5) addIter.dart    ← campo, edição e save
                      └── (6) routeCard.dart ← detalhe mostra a distribuição
```

As regras vêm primeiro porque o modelo, a tela e o gráfico dependem das mesmas
três: descartar bairro removido, cortar excesso do fim, contar o que resta.

`insucessoBairro.dart` **não pode importar** `newRouteModal.dart` — só lida com
`Map`/`List`. O modelo é que importa as regras, e não o contrário; o inverso
fecharia um ciclo.

## Riscos

| Risco | Mitigação |
|---|---|
| Documento antigo parar de carregar | `fromMap` trata campo ausente como distribuição vazia; teste de ida e volta cobre. |
| Distribuição inconsistente sem o usuário mexer (bairro removido, total baixado) | Uma função `reconcile` só, chamada no sheet, no save **e** na leitura do gráfico. Testada isolada. |
| Ranking citando bairro que a rota não tem | O gráfico também reconcilia antes de somar — não confia no que está gravado. |
| Soma por bairro divergir do total de insucessos | O restante não distribuído sempre vai para o rateio; teste verifica que a soma bate. |
| Bairro sumir e voltar ressuscitando valor antigo | A reconciliação é gravada no estado a cada mudança, não só na leitura. |

Checkpoint depois de cada tarefa: `flutter analyze lib/` sem nada novo, mais o
teste da tarefa.

---

# Tarefas

- [x] **1. `insucessoBairro.dart` — regras, com teste primeiro**
  - Aceite: `remainingFailures`, `reconcileDistribution`, `distributionToList` e
    `distributionFromList`, com todos os casos da "Estratégia de teste".
  - Verificar: `flutter test test/unit/insucessoBairro_test.dart`
  - Arquivos: `lib/Utils/insucessoBairro.dart`,
    `test/unit/insucessoBairro_test.dart`

- [x] **2. Campo no modelo**
  - Aceite: `insucessoPorBairro` como `Map<String, int>` (vazio = não
    distribuído), serializando como array de map; documento sem o campo carrega.
  - Verificar: `flutter test test/unit/`
  - Arquivos: `lib/model/newRouteModal.dart`

- [x] **3. Ranking usa o exato**
  - Aceite: `failuresPerBairro` soma o distribuído e rateia só o restante;
    reconcilia antes de somar.
  - Verificar: `flutter test test/unit/routeStats_test.dart`
  - Arquivos: `lib/Utils/routeStats.dart`, `test/unit/routeStats_test.dart`

- [x] **4. O sheet de distribuição**
  - Aceite: lista só os bairros da rota, seletor de quantidade por bairro,
    contador "Restam N de T", `+` travado quando não resta nada.
  - Verificar: `flutter analyze lib/`
  - Arquivos: `lib/widget/selectInsucessoBairro.dart`

- [x] **5. O campo no `addIter`**
  - Aceite: aparece com switch ligado e 2+ bairros; mostra o andamento; salva o
    array; um bairro só grava sozinho; edição reabre preenchida.
  - Verificar: `flutter analyze lib/` e `flutter test`
  - Arquivos: `lib/screens/addIter.dart`

- [x] **6. Detalhe no card da lista**
  - Aceite: card expandido mostra a distribuição quando existe.
  - Verificar: `flutter test test/widget/routeCard_test.dart`
  - Arquivos: `lib/widget/routeCard.dart`

- [ ] **7. Verificação no simulador**
  - Aceite: distribuir, remover bairro, baixar o total, salvar, reabrir e
    conferir o gráfico.
