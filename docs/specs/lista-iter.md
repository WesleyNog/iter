# Spec: Tela Lista Iter

Status: **implementada** · Criada em 2026-08-01 · Falta verificar no simulador
(depende do deploy das regras)

## Objetivo

Listar as rotas do usuário logado, lendo `iter/{uid}/routes`. Cada rota vira um
container com: logo da empresa, data em que a rota acontece/aconteceu, valor e
status atual.

É a segunda aba da `HomeScreen` (`GlassNavBar`, índice 1 — "OS"), hoje um
`Center(child: Text('Lista Iter'))`.

Usuário: o entregador, que abre o app para conferir o que tem agendado e quanto
já recebeu. Sucesso = ele bate o olho e entende a agenda sem abrir cada rota.

## Tech Stack

Flutter 3.41.4 / Dart 3.11.1 · cloud_firestore 6.7.1 · firebase_auth 6.5.6.
Sem pacote de gerência de estado — `StreamBuilder`, como no resto do app.

## Comandos

```bash
flutter pub get
flutter run                              # simulador iOS já em uso
flutter analyze lib/                     # precisa ficar sem error/warning novo
flutter test test/widget/routeCard_test.dart
firebase deploy --only firestore:rules --project iter-mn
```

## Estrutura

```
lib/controller/routeController.dart   → leitura de iter/{uid}/routes (novo)
lib/screens/listIterScreen.dart       → a tela (hoje stub)
lib/widget/routeCard.dart             → o container de uma rota (novo)
lib/Utils/routeStyle.dart             → logo/cor/rótulo por company e status (novo)
test/widget/routeCard_test.dart       → teste de widget do card (novo)
```

`routeStyle.dart` existe para não duplicar o que `addIter.dart` já tem em
`_getStatusIcon` e no seletor de empresa — a lista precisa das mesmas cores e
dos mesmos logos.

## Dados

`iter/{uid}/routes/{routeId}` (`NewRouteModal.toMap`), campos usados pela tela:

| campo | tipo | uso na tela |
|---|---|---|
| `company` | `'mercadolivre' \| 'amazon' \| 'shopee'` | logo em `assets/logo/` |
| `dateRoute` | string `dd/MM/yyyy` | data exibida e ordenação |
| `weekday` | int 1–7 | ícone do dia (`Utils/calendar.dart`) |
| `status` | `'agendado' \| 'andamento' \| 'concluido' \| 'pago' \| 'semRota'` | cor + rótulo |
| `noRoutePayment` | `{grossValue, percent, appliedAt}?` | só em `semRota`; ver `sem-rota.md` |
| `value` | double | `CurrencyFormatterHelper.formatDoubleToMoney` |
| `createdAt` | ISO 8601 | desempate na ordenação |

## Estilo de código

Controller estático, igual a `UserController`:

```dart
class RouteController {
  static Stream<List<NewRouteModal>> watchAll(String uid) {
    return _collection(uid).snapshots().map(
      (snap) => snap.docs.map((d) => NewRouteModal.fromMap(d.data())).toList(),
    );
  }
}
```

Stream criado uma única vez (campo `late final`), nunca dentro do `build`.
Texto de interface em pt-BR. Nomes de arquivo em camelCase, como o projeto.

## Estratégia de teste

O projeto não tem teste nenhum hoje (`test/widget_test.dart` é o template do
contador, quebrado). Não vou montar mock de Firebase agora — custo alto para o
retorno.

- **Teste de widget** para `RouteCard`: recebe um `NewRouteModal` montado à mão
  e verifica logo, data, valor formatado e rótulo do status. Não toca em rede.
- **Teste unitário** para o parse de `dateRoute` (ordenação), que é onde erro
  silencioso dói mais.
- Estados de lista (carregando / vazio / erro) ficam em verificação manual.

## Estados da tela

1. **Carregando** — `CircularProgressIndicator` centralizado.
2. **Vazio** — ícone + "Nenhuma rota por aqui ainda" + dica de usar o botão `+`.
3. **Erro** — mensagem amigável; em `kDebugMode`, o erro real. Sempre
   `debugPrint`, porque falha de regra do Firestore já sumiu silenciosamente
   neste projeto antes.
4. **Com dados** — `ListView.builder` de `RouteCard`.

## Fronteiras

- **Sempre:** `flutter analyze` limpo antes de entregar; texto em pt-BR; `User`
  recebido por construtor (nunca `FirebaseAuth.instance.currentUser` dentro da
  tela); tratar erro de stream visivelmente.
- **Perguntar antes:** mudar `NewRouteModal` ou o formato gravado em
  `iter/{uid}/routes`; alterar `firestore.rules`; adicionar dependência;
  mexer em `addIter.dart` além de extrair o que virar `routeStyle.dart`.
- **Nunca:** deploy de regras sem aprovação; apagar/alterar documentos
  existentes; criar índice composto sem avisar do custo.

## Critérios de sucesso

- [ ] Abrir a aba "OS" lista todas as rotas de `iter/{uid}/routes` do usuário logado.
- [ ] Cada card mostra logo da empresa, data, valor em BRL e status com cor.
- [ ] Salvar uma rota nova faz ela aparecer na lista sem precisar reabrir a tela.
- [ ] Lista vazia mostra o estado vazio, não uma tela branca.
- [ ] Falha de permissão mostra mensagem e registra o erro no console.
- [ ] Ordem: rota mais recente primeiro, por `dateRoute` (não por cadastro).
- [ ] Tocar no card expande e mostra KM, pacotes, paradas, bairros e horários.
- [ ] `flutter analyze lib/` sem error/warning novo.
- [ ] `flutter test test/widget/routeCard_test.dart` passa.

## Decisões

**1. Ordenação no cliente, por proximidade com hoje.** A rota mais perto da
data atual primeiro, indo para as mais distantes — nos dois sentidos. Empate de
distância (ontem x amanhã) fica com a do futuro; mesma data desempata por
`createdAt`; data ilegível vai para o fim em vez de lançar exceção.

Ordenar no cliente é obrigatório aqui por dois motivos: `dateRoute` é string
`dd/MM/yyyy`, e `orderBy` compararia texto colocando `02/01/2026` antes de
`31/12/2025`; e "mais perto de hoje" muda todo dia, então nenhum índice do
Firestore expressa esse critério.

Dívida assumida: isso exige baixar a coleção inteira. Quando o volume pedir
paginação, a saída é gravar `dateRouteIso` no `addIter` e ordenar no servidor —
o que também exige preencher os documentos já existentes.

**2. Card expansível.** Tocar no card abre, no próprio card, o que já está
gravado e não cabe no resumo: KM rodado, pacotes, paradas, bairros, horários,
insucesso e clima. Um card aberto por vez. Não há tela de detalhe.

**3. Filtro por empresa** (adicionado depois da primeira entrega). Controle
segmentado acima da lista: "todas" (padrão) + uma opção por `Company`. Fica
**fora** do `StreamBuilder`, para continuar visível durante carregamento, vazio
e erro. Filtra em memória a lista que já veio do stream — nenhuma consulta nova
ao Firestore. Quando existem rotas mas nenhuma da empresa escolhida, a mensagem
é diferente da de lista vazia.

**4. Editar e excluir** (adicionado depois da primeira entrega). Deslizar o
card da direita para a esquerda revela as duas ações (`flutter_slidable` —
o `Dismissible` nativo é swipe-para-remover, não serve para revelar ações).
Excluir pede confirmação em diálogo. Editar reaproveita o formulário do
cadastro: `AddIter` recebe uma `route` opcional, preenche os campos e grava com
o **mesmo id**, então o `set` substitui o documento em vez de criar outro.

## Fora de escopo

Filtro por status, separador por mês e paginação.
