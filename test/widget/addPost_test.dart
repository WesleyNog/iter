import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/screens/addPost.dart';
import 'package:iter/widget/slidingIndicator.dart';

const _ana = PublicProfile(
  uid: 'uid-ana',
  name: 'Ana Souza',
  nickName: 'ana.a1',
  updatedAt: '2026-08-07T10:00:00.000',
);

/// A tela só chama o Firebase ao enviar de fato. Até o aviso de empresa —
/// que é o que se testa aqui — nada sai do aparelho.
Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    const MaterialApp(
      home: AddPost(uid: 'uid-ana', me: _ana),
    ),
  );
}

FilledButton _publicar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('publicar')));

void main() {
  testWidgets('mostra quem publica e para quem aparece', (tester) async {
    await _pump(tester);

    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Aparece no mural para todos'), findsOneWidget);
    expect(find.text('Como foi o dia, Ana?'), findsOneWidget);
  });

  testWidgets('publicar só liga com algo para publicar', (tester) async {
    await _pump(tester);
    expect(_publicar(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('texto-post')), 'Oi');
    await tester.pump();
    expect(_publicar(tester).onPressed, isNotNull);
  });

  testWidgets('as empresas são logos, e tocar de novo desmarca', (
    tester,
  ) async {
    await _pump(tester);

    for (final empresa in ['mercadolivre', 'amazon', 'shopee']) {
      expect(find.byKey(ValueKey('empresa-$empresa')), findsOneWidget);
    }
    // Logos, não nomes: o nome só vive no tooltip.
    expect(find.text('Amazon'), findsNothing);
    expect(find.byType(SlidingIndicator), findsNothing);

    await tester.tap(find.byKey(const ValueKey('empresa-amazon')));
    await tester.pumpAndSettle();
    expect(find.byType(SlidingIndicator), findsOneWidget);

    // Opcional: sem desmarcar, não haveria como voltar atrás.
    await tester.tap(find.byKey(const ValueKey('empresa-amazon')));
    await tester.pumpAndSettle();
    expect(find.byType(SlidingIndicator), findsNothing);
  });

  testWidgets('sem empresa, publicar pergunta antes', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('texto-post')), 'Oi');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('publicar')));
    await tester.pumpAndSettle();

    expect(find.text('Publicar sem a empresa?'), findsOneWidget);
    expect(find.byKey(const ValueKey('marcar-empresa')), findsOneWidget);
    expect(find.byKey(const ValueKey('publicar-sem-empresa')), findsOneWidget);
  });

  testWidgets('"Marcar empresa" volta com o trilho em destaque', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('texto-post')), 'Oi');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('publicar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('marcar-empresa')));
    await tester.pumpAndSettle();

    // O aviso fechou, nada foi publicado, e a tela aponta onde tocar.
    expect(find.text('Publicar sem a empresa?'), findsNothing);
    expect(find.text('TOQUE NA EMPRESA DA ROTA'), findsOneWidget);

    // Escolher uma empresa apaga o destaque.
    await tester.tap(find.byKey(const ValueKey('empresa-shopee')));
    await tester.pumpAndSettle();
    expect(find.text('TOQUE NA EMPRESA DA ROTA'), findsNothing);
    expect(find.text('EMPRESA DA ROTA'), findsOneWidget);
  });

  testWidgets('o aviso devolve a escolha de quem respondeu', (tester) async {
    final respostas = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                respostas.add(await askPublishWithoutCompany(context)),
            child: const Text('abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publicar-sem-empresa')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('marcar-empresa')));
    await tester.pumpAndSettle();

    expect(respostas, [true, false]);
  });
}
