# Spec: Menu de criação e barra de navegação flutuante

Status: **implementada** · Criada e implementada em 2026-08-02

Duas mudanças na `HomeScreen`, independentes entre si:

1. O "+" deixa de abrir direto o cadastro de rota e passa a abrir um menu com
   três opções — **Nova rota** (funciona), **Abastecimento** e **Manutenção**
   (ainda em desenvolvimento).
2. A `GlassNavBar` para de ocupar espaço no layout e passa a flutuar **por
   cima** do conteúdo, sem escondê-lo.

## Objetivo

Usuário: o entregador, na tela inicial do app.

**Menu de criação.** Hoje o "+" só cadastra rota. O app vai passar a registrar
também abastecimento e manutenção do veículo. Colocar as três entradas no menu
agora — com as duas futuras visíveis mas inertes — informa o que vem por aí sem
precisar redesenhar o botão depois. Sucesso = o entregador toca no "+", vê as
três opções, e chega no cadastro de rota com um toque a mais que hoje.

**Barra flutuante.** A `GlassNavBar` foi escrita para flutuar sobre o conteúdo
(o efeito de vidro só existe se houver conteúdo passando atrás para borrar), mas
na Home ela está montada como barra sólida comum: reserva a própria altura no
layout e o conteúdo termina rente à borda dela, parecendo cortado. Sucesso = a
barra flutua, o blur mostra o conteúdo real por trás, e nada fica escondido nem
sem alcance de toque embaixo dela.

### Diagnóstico do item 2

`lib/widget/glassNavBar.dart:60` já documenta o requisito:

> Para o blur captar o conteúdo, o `Scaffold` que a usa deve ter
> `extendBody: true`.

`lib/screens/home.dart:99` monta o `Scaffold` **sem** `extendBody`. Com isso:

- o `bottomNavigationBar` reserva `64` (pílula) + `12` (padding) + inset inferior
  do aparelho (≈ 34 no iPhone com barra de gestos) ≈ **110px** de layout;
- o `body` é espremido nos pixels restantes e encosta na barra;
- o `BackdropFilter` não tem conteúdo atrás para borrar — ele borra o fundo do
  `Scaffold`, e o "vidro" fica leitoso e sem graça.

É o mesmo `Scaffold` do outro app (`meu_negocio`), que usa `extendBody: true`.

Ligar `extendBody: true` sozinho **não** resolve: o `body` passa a ir até o fim
da tela e os últimos cards ficam embaixo da barra, sem alcance de toque. Por isso
o spec inclui o respiro nas telas roláveis.

## Tech Stack

Flutter 3.41.4 / Dart SDK `^3.11.1`. Sem pacote novo — `showModalBottomSheet` e
`BackdropFilter` são do próprio Flutter. Sem gerência de estado: `setState`, como
no resto do app.

## Comandos

```bash
flutter pub get
flutter analyze lib/ test/                          # sem error/warning novo
flutter test test/widget/createActionSheet_test.dart
flutter test                                        # widget_test.dart já falha antes desta mudança
flutter run                                         # conferir no simulador iOS
```

## Estrutura

```
lib/widget/createActionSheet.dart      → o menu do "+" (novo)
lib/screens/home.dart                  → extendBody + abre o menu (edição)
lib/screens/graficsScreen.dart         → respiro no fim do scroll (edição)
lib/screens/listIterScreen.dart        → respiro no fim da lista (edição)
test/widget/createActionSheet_test.dart → teste de widget do menu (novo)
```

`FriendsScreen` e `SocialScreen` são `Center(child: Text(...))` — não rolam e não
precisam de respiro. Quando ganharem conteúdo rolável, aplicam o mesmo padrão.

## Comportamento — menu de criação

Bottom sheet de vidro, mesmo material da `GlassNavBar` (blur 18, branco
translúcido, borda branca, sombra), com puxador no topo e uma linha por ação.

| Ação | Ícone | Cor | Título | Subtítulo | Toque |
|---|---|---|---|---|---|
| Rota | `Icons.local_shipping_outlined` | verde | Nova rota | Cadastrar uma rota | abre `/addIter` |
| Abastecimento | `Icons.local_gas_station_outlined` | laranja | Abastecimento | Registrar combustível | inerte |
| Manutenção | `Icons.build_outlined` | azul-cinza | Manutenção | Registrar manutenção | inerte |

**Ações em desenvolvimento** (decisão do usuário, 2026-08-02): aparecem na lista
com opacidade reduzida e o selo `Em breve` no lugar da seta `›`. Não são
clicáveis — não fecham o sheet, não mostram toast, não fazem nada. O selo já
comunica o estado; um toast em cima disso é ruído.

**Ordem do pop e do `onTap`.** A linha escolhida faz `Navigator.pop(context,
action)` e o `onTap` roda **depois** que o sheet fecha:

```dart
final chosen = await showModalBottomSheet<CreateAction>(...);
chosen?.onTap?.call();
```

Se o `onTap` navegasse de dentro do sheet, o Navigator empilharia o sheet junto
com a tela nova. É o mesmo cuidado do `createActionSheet.dart` do `meu_negocio`.

**Navegação da rota** continua idêntica à de hoje —
`Navigator.pushNamed('/addIter', arguments: widget.user)` — só que agora chamada
de dentro do menu. `AddIter` volta com `popUntil((route) => route.isFirst)`, o
que preserva o `AuthGate` (ver `CLAUDE.md`).

## Comportamento — barra flutuante

1. `Scaffold` da Home ganha `extendBody: true`. A `AppBar` **não** muda (decisão
   do usuário: escopo mínimo, sem `extendBodyBehindAppBar` nem `GlassPill`).
2. Com `extendBody: true`, o `Scaffold` entrega ao `body` um `MediaQuery` cujo
   `padding.bottom` é exatamente a altura ocupada pela barra. As telas roláveis
   somam esse valor ao próprio respiro:

```dart
// graficsScreen.dart / listIterScreen.dart
padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
```

Ler do `MediaQuery` em vez de cravar uma constante mantém o respiro correto se a
altura da pílula, o padding dela ou o aparelho mudarem — nenhum número da
`GlassNavBar` fica duplicado nas telas.

3. Os estados vazios (`_message`) das duas telas são `Center` e recebem o mesmo
   respiro no `Padding`, senão o subtítulo pode nascer atrás da barra em tela
   curta.

## Estilo de código

`withValues(alpha:)`, nunca `withOpacity` — depreciado no Flutter 3.41. O código
mais novo do repo (`graficsScreen.dart:420`) já usa a forma nova; `glassNavBar.dart`
ainda usa a antiga e **não** entra no escopo desta mudança.

Widget novo segue a convenção do repo: arquivo camelCase, função de topo que
mostra algo + classe do widget, como `profileDialog.dart`.

```dart
/// Uma ação do menu do "+". Sem [onTap] a linha aparece inerte, com o selo
/// "Em breve" — é assim que uma função ainda não pronta se anuncia.
class CreateAction {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const CreateAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  bool get comingSoon => onTap == null;
}
```

`onTap` opcional em vez de um `bool comingSoon` separado: assim é impossível
escrever a linha inconsistente (marcada como pronta sem ação, ou com ação e selo
de "em breve"). O tipo já não deixa.

Textos em pt-BR, como o resto do app.

## Testes

`test/widget/createActionSheet_test.dart`, no padrão dos testes de widget que já
existem (`profileDialog_test.dart`, `routeCard_test.dart`) — sem Firebase, o
widget recebe tudo por parâmetro:

- [ ] desenha as três linhas com título e subtítulo
- [ ] linha com `onTap` fecha o sheet e chama a ação **uma** vez
- [ ] linha sem `onTap` não fecha o sheet e não chama nada
- [ ] linha sem `onTap` mostra o selo "Em breve" e nenhuma seta `›`

O respiro da barra e o `extendBody` são verificados no simulador: a Home precisa
de um `User` do Firebase e não sobe em teste de widget.

## Critérios de sucesso

Verificado no simulador (iPhone 16 Plus, iOS 18.6):

- [x] Tocar no "+" abre o sheet com Nova rota, Abastecimento e Manutenção.
- [x] Abastecimento e Manutenção aparecem apagadas, com o selo "Em breve"; só a
      linha pronta tem a seta `›`.
- [x] O conteúdo aparece borrado atrás da barra — prova de que o `extendBody`
      está valendo, e que a barra flutua em vez de reservar espaço.
- [x] "Nova rota" fecha o sheet e abre o `AddIter`.

Verificado por teste automatizado:

- [x] `createActionSheet_test.dart`: as três linhas aparecem; a ação pronta
      fecha o sheet e roda **uma** vez (ordem pop → `onTap`); a ação em
      desenvolvimento não fecha o sheet e não chama nada; o selo só aparece nas
      duas de "em breve".
- [x] `glassNavBar_test.dart`: com `extendBody: true` o body recebe no
      `MediaQuery` exatamente a altura da barra — a conta de onde sai o respiro.
      O segundo caso reproduz o estado antigo (sem `extendBody`, o body recebe
      `0`) e explica o corte.
- [x] `flutter analyze lib/ test/` sem error/warning novo — só os `info`
      `file_names` da convenção camelCase do repo.
- [x] `flutter test test/widget/ test/unit/`: 156 passando.

Falta conferir na mão (a automação de toque do simulador não é confiável neste
ambiente; o respiro está coberto pelo `glassNavBar_test`, mas o olho é melhor):

- [ ] Salvar/voltar do `AddIter` cai na Home com o `AuthGate` intacto (o botão
      de logout ainda funciona).
- [ ] Na aba Gráfico, rolar até o fim mostra o último carrossel inteiro acima da
      barra, e dá para tocar nele.
- [ ] Na aba Lista, rolar até o fim mostra o último card inteiro e o *slide* de
      editar/excluir funciona nele.

## Limites

- **Sempre:** rodar `flutter analyze` e os testes de widget antes de commitar;
  textos novos em pt-BR; `withValues(alpha:)` no código novo.
- **Perguntar antes:** mexer na `AppBar` da Home; mudar a `GlassNavBar` em si;
  adicionar dependência; criar as telas de abastecimento/manutenção de verdade.
- **Nunca:** trocar `pushNamed('/addIter')` por algo que remova a primeira rota
  (derruba o `AuthGate`); cravar a altura da barra como número mágico nas telas;
  apagar teste que falha.

## Questões em aberto

- Abastecimento e Manutenção vão gravar em coleções próprias
  (`iter/{uid}/refuels`, `iter/{uid}/maintenances`) ou virar tipos dentro de
  `routes`? Não bloqueia esta mudança — o menu só precisa da entrada.
- O selo "Em breve" some sozinho quando cada tela ficar pronta (basta passar o
  `onTap`), então não há dívida de layout a pagar depois.
