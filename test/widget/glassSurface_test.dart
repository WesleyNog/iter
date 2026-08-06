import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/glassSurface.dart';

Future<void> _pump(WidgetTester tester, Widget surface) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: surface))),
  );
}

void main() {
  testWidgets('desenha o filho recebido', (tester) async {
    await _pump(
      tester,
      const GlassSurface(child: Text('conteúdo')),
    );

    expect(find.text('conteúdo'), findsOneWidget);
  });

  testWidgets('aplica exatamente um blur', (tester) async {
    // Duas camadas de BackdropFilter borram o fundo duas vezes: fica leitoso e
    // custa o dobro num widget que repinta a cada frame de scroll.
    await _pump(tester, const GlassSurface(child: SizedBox(width: 80, height: 40)));

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  // O teste de toque abaixo **não** prova que o `IgnorePointer` está fazendo
  // efeito: removendo-o, ele continua passando, porque `DecoratedBox` não faz
  // hit test de si mesmo. Ele guarda o resultado (o toque chega), e quem guarda
  // a intenção é o teste estrutural ao lado. Os dois juntos pegam a edição que
  // realmente quebraria isto: trocar a camada por algo que capture ponteiro.
  group('o brilho especular não pode roubar toque', () {
    testWidgets('a camada de brilho é IgnorePointer', (tester) async {
      await _pump(tester, const GlassSurface(child: SizedBox(width: 80, height: 40)));

      // Dentro da própria superfície: `MaterialApp` traz `IgnorePointer`s
      // próprios, e procurar por tipo solto passaria mesmo sem o nosso.
      expect(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });

    testWidgets('o toque chega ao filho, não à camada de cima', (tester) async {
      // É o defeito mais fácil de introduzir aqui, e numa barra de navegação
      // ele é fatal: a barra fica bonita e não navega.
      var taps = 0;

      await _pump(
        tester,
        GlassSurface(
          child: GestureDetector(
            // `opaque` como a barra de navegação usa: `SizedBox` vazio não
            // participa de hit test, e o `deferToChild` padrão não teria em
            // que se apoiar — falharia por artefato do teste, não por defeito.
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('formato', () {
    testWidgets('circle: false recorta em retângulo arredondado', (
      tester,
    ) async {
      await _pump(tester, const GlassSurface(child: SizedBox(width: 80, height: 40)));

      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(ClipOval), findsNothing);
    });

    testWidgets('circle: true recorta em oval', (tester) async {
      await _pump(
        tester,
        const GlassSurface(
          circle: true,
          child: SizedBox(width: 60, height: 60),
        ),
      );

      expect(find.byType(ClipOval), findsOneWidget);
      expect(find.byType(ClipRRect), findsNothing);
    });
  });

  testWidgets('o padding informado envolve o filho', (tester) async {
    await _pump(
      tester,
      const GlassSurface(
        padding: EdgeInsets.all(20),
        child: SizedBox(width: 40, height: 20),
      ),
    );

    // 40 + 20 + 20 de padding, mais 1 de cada lado da borda em gradiente.
    final size = tester.getSize(find.byType(GlassSurface));
    expect(size.width, 82);
    expect(size.height, 62);
  });

  testWidgets('opacidade do vidro é configurável', (tester) async {
    // O sheet do "+" carrega texto e precisa de mais fundo que uma barra de
    // ícones — a diferença é justificada, então é parâmetro.
    await _pump(
      tester,
      const GlassSurface(
        opacity: 0.9,
        child: SizedBox(width: 80, height: 40),
      ),
    );

    final fill = tester.widget<GlassSurface>(find.byType(GlassSurface));
    expect(fill.opacity, 0.9);
  });
}
