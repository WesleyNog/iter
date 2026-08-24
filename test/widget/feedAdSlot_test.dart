import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/feedAdSlot.dart';
import 'package:iter/widget/postCard.dart';
import 'package:iter/model/post.dart';

Future<void> _pump(WidgetTester tester, {Widget? child}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: FeedAdSlot(child: child)),
    ),
  );
}

void main() {
  testWidgets('o rótulo aparece mesmo sem anúncio carregado', (tester) async {
    // Sempre visível: é metade do que impede o anúncio de ser confundido com
    // post. A outra metade é a moldura não imitar o card.
    await _pump(tester);

    expect(find.text('PUBLICIDADE'), findsOneWidget);
  });

  testWidgets('o rótulo continua quando o anúncio chega', (tester) async {
    await _pump(tester, child: const SizedBox(height: 50, key: Key('anuncio')));

    expect(find.text('PUBLICIDADE'), findsOneWidget);
    expect(find.byKey(const Key('anuncio')), findsOneWidget);
    // E o placeholder some, para não haver dois fundos empilhados.
    expect(find.text('Espaço reservado para anúncio'), findsNothing);
  });

  testWidgets('não imita o card de post', (tester) async {
    // A **causa**, não o sintoma: formatar anúncio de modo indistinguível do
    // conteúdo é violação escrita da política. O desenho tentador é reusar o
    // `Container` do PostCard (grey.shade50, raio 14) "para combinar com o
    // feed" — este teste fica vermelho se alguém fizer isso.
    await _pump(tester);
    final anuncio = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(FeedAdSlot),
            matching: find.byType(Container),
          )
          .last,
    );
    final decAnuncio = anuncio.decoration as BoxDecoration;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            post: Post(
              id: 'p1',
              uid: 'u1',
              text: 'oi',
              createdAt: DateTime(2026, 8, 24),
            ),
            author: null,
            imageUrl: null,
            imageLoading: false,
            likes: 0,
            liked: false,
            comments: 0,
            isMine: true,
            onLike: (_) {},
            onComment: () {},
          ),
        ),
      ),
    );
    final card = tester.widget<Container>(
      find.byKey(const ValueKey('post-p1')),
    );
    final decCard = card.decoration as BoxDecoration;

    expect(decAnuncio.color, isNot(decCard.color));
    expect(decAnuncio.borderRadius, isNot(decCard.borderRadius));
    // O card não tem borda; o anúncio tem, e com espessura de verdade. A
    // revisão mostrou que a versão anterior deste teste passava com
    // `Border.all(width: 0.0)` e raio 13 contra 14 — diferença de token, não
    // de desenho. Estes dois números são o piso do que se enxerga rolando.
    expect(decCard.border, isNull);
    final borda = decAnuncio.border as Border;
    expect(borda.top.width, greaterThanOrEqualTo(1));

    final raioAnuncio = (decAnuncio.borderRadius as BorderRadius).topLeft.x;
    final raioCard = (decCard.borderRadius as BorderRadius).topLeft.x;
    expect((raioCard - raioAnuncio).abs(), greaterThanOrEqualTo(4));
  });

  testWidgets('a folga é maior que a margem do card', (tester) async {
    // 24 px contra os 12 px do card: o card termina numa fileira de curtir e
    // comentar, e a política nomeia "next to interactive buttons" como uma das
    // maiores causas de clique acidental.
    await _pump(tester);
    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(FeedAdSlot),
            matching: find.byType(Padding),
          )
          .first,
    );

    expect(
      padding.padding.vertical,
      greaterThanOrEqualTo(48),
    ); // 24 em cima e embaixo
  });

  testWidgets('reserva altura antes de o anúncio existir', (tester) async {
    // Sem altura conhecida, a lista salta quando o anúncio carrega. O banner
    // inline adaptativo tem altura derivada da largura da tela, e ela precisa
    // ser reservada antes.
    await _pump(tester);

    final caixa = tester.getSize(
      find
          .descendant(
            of: find.byType(FeedAdSlot),
            matching: find.byType(Container),
          )
          .last,
    );
    expect(caixa.height, FeedAdSlot.reservedHeight);
  });
}
