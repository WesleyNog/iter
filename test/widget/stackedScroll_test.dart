import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/stackedScroll.dart';

const _peek = 12.0;
const _gap = 16.0;

/// Conta quantas vezes o conteúdo foi reconstruído.
///
/// Existe para o teste da Regra 3: o card vai como `child` do `AnimatedBuilder`,
/// então rolar não pode reconstruí-lo. Sem isso, cada pixel de rolagem
/// remontaria os gráficos inteiros e o `PageView` de dentro deles.
class _Contador extends StatelessWidget {
  const _Contador({super.key, required this.builds});

  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return const ColoredBox(color: Colors.blue);
  }
}

Widget _card(int index) => Container(
  key: ValueKey('card-$index'),
  color: Colors.primaries[index % Colors.primaries.length],
);

class _Bouncing extends ScrollBehavior {
  const _Bouncing();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}

late ScrollController _found;

Future<void> _pump(
  WidgetTester tester, {
  List<double> alturas = const [200, 200, 200, 200],
  EdgeInsets padding = EdgeInsets.zero,
  bool bouncing = false,
  List<int>? builds,
}) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final scroll = StackedScroll(
    cards: [
      for (var i = 0; i < alturas.length; i++)
        StackedCard(
          height: alturas[i],
          child: builds == null
              ? _card(i)
              : _Contador(key: ValueKey('card-$i'), builds: builds),
        ),
    ],
    gap: _gap,
    peek: _peek,
    padding: padding,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: bouncing
            ? ScrollConfiguration(behavior: const _Bouncing(), child: scroll)
            : scroll,
      ),
    ),
  );

  // O controller é interno ao widget; o teste chega nele pela árvore.
  _found = tester
      .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
      .controller!;
}

double _topo(WidgetTester tester, int index) =>
    tester.getTopLeft(find.byKey(ValueKey('card-$index'))).dy;

Future<void> _rolar(WidgetTester tester, double offset) async {
  _found.jumpTo(offset);
  await tester.pump();
}

void main() {
  const passo = 200.0 + _gap;

  group('encaixe', () {
    testWidgets('parado no topo, cada card na posição natural', (tester) async {
      await _pump(tester);

      expect(_topo(tester, 0), 0);
      expect(_topo(tester, 1), passo);
      expect(_topo(tester, 2), passo * 2);
    });

    testWidgets('o primeiro card para no topo e não sobe mais', (tester) async {
      await _pump(tester);
      await _rolar(tester, passo);

      // Sem o encaixe ele estaria em -216, fora da tela.
      expect(_topo(tester, 0), 0);
      // E o segundo chega exatamente 12px abaixo: é a faixa.
      expect(_topo(tester, 1), _peek);
    });

    testWidgets('a pilha cresce um degrau por card', (tester) async {
      await _pump(tester);
      await _rolar(tester, passo * 2);

      expect(_topo(tester, 0), 0);
      expect(_topo(tester, 1), _peek);
      expect(_topo(tester, 2), _peek * 2);
      // O quarto ainda rola solto, longe do encaixe.
      expect(_topo(tester, 3), greaterThan(_peek * 3));
    });

    testWidgets('a faixa entre dois encaixados é exatamente o peek', (
      tester,
    ) async {
      await _pump(tester);
      await _rolar(tester, passo * 2);

      expect(_topo(tester, 1) - _topo(tester, 0), _peek);
      expect(_topo(tester, 2) - _topo(tester, 1), _peek);
    });

    testWidgets('alturas diferentes não desalinham o encaixe', (tester) async {
      // Os carrosséis reais medem 290, 340, 340, 340 e 330 — o protótipo usou
      // todos iguais, e uma conta que só some `altura + gap` erraria aqui.
      await _pump(tester, alturas: const [120, 260, 180, 300]);

      expect(_topo(tester, 0), 0);
      expect(_topo(tester, 1), 120 + _gap);
      expect(_topo(tester, 2), 120 + _gap + 260 + _gap);

      await _rolar(tester, 600);
      expect(_topo(tester, 0), 0);
      expect(_topo(tester, 1), _peek);
      expect(_topo(tester, 2), _peek * 2);
    });

    testWidgets('o padding do topo empurra a pilha inteira', (tester) async {
      await _pump(tester, padding: const EdgeInsets.only(top: 30));
      expect(_topo(tester, 0), 30);

      await _rolar(tester, passo * 2);
      expect(_topo(tester, 0), 30);
      expect(_topo(tester, 1), 30 + _peek);
    });
  });

  group('ordem de pintura', () {
    testWidgets('o card seguinte cobre o encaixado, não o contrário', (
      tester,
    ) async {
      await _pump(tester);

      // A ordem no Stack é a ordem de pintura, e é ela que produz o efeito.
      final chaves = tester
          .widgetList<Container>(
            find.byWidgetPredicate((w) => w is Container && w.key is ValueKey),
          )
          .map((c) => (c.key! as ValueKey).value)
          .toList();

      expect(chaves, ['card-0', 'card-1', 'card-2', 'card-3']);
    });
  });

  group('o conteúdo não é reconstruído ao rolar', () {
    testWidgets('rolar move o card sem remontá-lo', (tester) async {
      final builds = <int>[];
      await _pump(tester, builds: builds);

      final depoisDoPrimeiroDesenho = builds.length;
      expect(depoisDoPrimeiroDesenho, greaterThan(0));

      for (var i = 1; i <= 20; i++) {
        await _rolar(tester, i * 10.0);
      }

      // Vinte quadros de rolagem e nenhum rebuild: é o que separa mover um
      // `Transform` de remontar quatro carrosséis de gráfico por quadro.
      expect(builds.length, depoisDoPrimeiroDesenho);
    });
  });

  group('bordas', () {
    testWidgets('overscroll não empurra o primeiro card para dentro', (
      tester,
    ) async {
      await _pump(tester, bouncing: true);
      await _rolar(tester, -50);

      // Com `offset` negativo o encaixe fica acima do natural, e o `max` segura
      // o card na posição natural: ele desce junto com o repique, como o resto
      // do conteúdo, em vez de deslizar sozinho para dentro da tela.
      expect(_topo(tester, 0), 50);
      expect(_topo(tester, 1), 50 + passo);
    });

    testWidgets('lista vazia não desenha nem quebra', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StackedScroll(cards: [])),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('um card só rola sem encaixar em lugar nenhum', (tester) async {
      await _pump(tester, alturas: const [200]);
      expect(_topo(tester, 0), 0);
    });
  });

  group('card coberto não aceita toque', () {
    bool ignorando(WidgetTester tester, int index) {
      final finder = find.ancestor(
        of: find.byKey(ValueKey('card-$index')),
        matching: find.byType(IgnorePointer),
      );
      return tester.widget<IgnorePointer>(finder.first).ignoring;
    }

    testWidgets('solto, todo card aceita toque', (tester) async {
      await _pump(tester);

      for (var i = 0; i < 4; i++) {
        expect(ignorando(tester, i), isFalse, reason: 'card $i');
      }
    });

    testWidgets('encaixado e coberto, o card para de aceitar', (tester) async {
      await _pump(tester);
      await _rolar(tester, passo * 2);

      // 0 e 1 estão encaixados sob o 2; o 2 está encaixado mas ainda visível
      // inteiro, e o 3 rola solto.
      expect(ignorando(tester, 0), isTrue);
      expect(ignorando(tester, 1), isTrue);
      expect(ignorando(tester, 2), isFalse);
      expect(ignorando(tester, 3), isFalse);
    });

    testWidgets('o último card nunca é ignorado', (tester) async {
      await _pump(tester);
      await _rolar(tester, 10000);

      expect(ignorando(tester, 3), isFalse);
    });

    testWidgets('arrastar de lado na faixa não mexe no card escondido', (
      tester,
    ) async {
      // O defeito que isto guarda: a faixa é o topo do card, ninguém a cobre,
      // e ela recebia o arrasto horizontal — trocando a página de um carrossel
      // invisível, que o usuário só descobria ao rolar de volta.
      final controllers = <PageController>[];
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StackedScroll(
              gap: _gap,
              peek: _peek,
              cards: [
                // Cinco, e não três: com três de 200 numa tela de 600 mal dá
                // para rolar, e nenhum card chega a ficar coberto — o cenário
                // que o teste quer examinar nem acontecia.
                for (var i = 0; i < 5; i++)
                  StackedCard(
                    height: 200,
                    child: Builder(
                      builder: (context) {
                        final c = PageController();
                        controllers.add(c);
                        return PageView(
                          key: ValueKey('card-$i'),
                          controller: c,
                          children: const [
                            ColoredBox(color: Colors.red),
                            ColoredBox(color: Colors.green),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final antes = controllers.first.page;
      // Dentro da faixa do card 0, que vai de y=0 a y=12.
      await tester.dragFrom(const Offset(200, 6), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(controllers.first.page, antes);
    });
  });

  group('identidade do card', () {
    testWidgets('a chave preserva o estado quando a lista muda', (
      tester,
    ) async {
      // A chave vai no filho direto do Stack. Um nível abaixo — dentro do
      // Positioned — ela não casa elemento nenhum, e reordenar zera o estado
      // de todos como se não houvesse chave.
      Widget arvore(List<String> nomes) => MaterialApp(
        home: Scaffold(
          body: StackedScroll(
            cards: [
              for (final nome in nomes)
                StackedCard(
                  key: ValueKey(nome),
                  height: 100,
                  child: _Contagem(rotulo: nome),
                ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(arvore(['a', 'b']));
      final estado = tester.state<_ContagemState>(
        find.byWidgetPredicate((w) => w is _Contagem && w.rotulo == 'b'),
      );
      estado.valor = 7;

      // Entra um card na frente: sem chave, 'b' passaria a casar com o
      // elemento de 'a' e perderia o 7.
      await tester.pumpWidget(arvore(['novo', 'a', 'b']));

      final depois = tester.state<_ContagemState>(
        find.byWidgetPredicate((w) => w is _Contagem && w.rotulo == 'b'),
      );
      expect(depois.valor, 7);
    });
  });
}

/// Guarda um número, para o teste ver se o estado sobreviveu.
class _Contagem extends StatefulWidget {
  const _Contagem({required this.rotulo});

  final String rotulo;

  @override
  State<_Contagem> createState() => _ContagemState();
}

class _ContagemState extends State<_Contagem> {
  int valor = 0;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
