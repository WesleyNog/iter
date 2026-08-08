import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/post.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/postCard.dart';

/// Só posts **sem imagem**: com foto o card chama o Storage, e o padrão da
/// casa é não subir Firebase em teste. O que sobra — autor, curtida, tempo,
/// dono — é justamente o que tem regra.
Post _post({String text = 'Dia puxado no galpão', Company? company}) {
  return Post(
    id: 'p1',
    uid: 'uid-ana',
    text: text,
    company: company,
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  );
}

const _ana = PublicProfile(
  uid: 'uid-ana',
  name: 'Ana Souza',
  nickName: 'ana.a1',
  updatedAt: '2026-08-07T10:00:00.000',
);

Future<void> _pump(
  WidgetTester tester, {
  Post? post,
  PublicProfile? author = _ana,
  String? imageUrl,
  bool imageLoading = false,
  int likes = 0,
  bool liked = false,
  bool isMine = false,
  ValueChanged<bool>? onLike,
  VoidCallback? onDelete,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PostCard(
          post: post ?? _post(),
          author: author,
          imageUrl: imageUrl,
          imageLoading: imageLoading,
          likes: likes,
          liked: liked,
          isMine: isMine,
          onLike: onLike ?? (_) {},
          onDelete: onDelete,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra autor, texto e quando foi', (tester) async {
    await _pump(tester);

    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Dia puxado no galpão'), findsOneWidget);
    expect(find.text('há 3h'), findsOneWidget);
  });

  testWidgets('sem projeção publicada, o @apelido vira o nome', (tester) async {
    await _pump(
      tester,
      author: const PublicProfile(
        uid: 'uid-ana',
        name: '',
        nickName: 'ana.a1',
        updatedAt: '',
      ),
    );

    expect(find.text('@ana.a1'), findsOneWidget);
  });

  testWidgets('sem autor nenhum, ainda desenha alguma coisa', (tester) async {
    await _pump(tester, author: null);

    expect(find.text('Entregador'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('curtir avisa o valor novo, não o atual', (tester) async {
    final toques = <bool>[];
    await _pump(tester, liked: false, onLike: toques.add);

    await tester.tap(find.byKey(const ValueKey('curtir-p1')));
    expect(toques, [true]);
  });

  testWidgets('descurtir avisa false', (tester) async {
    final toques = <bool>[];
    await _pump(tester, liked: true, onLike: toques.add);

    await tester.tap(find.byKey(const ValueKey('curtir-p1')));
    expect(toques, [false]);
  });

  testWidgets('curtido desenha o coração cheio', (tester) async {
    await _pump(tester, liked: true);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await _pump(tester, liked: false);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('zero curtida não mostra o número', (tester) async {
    // "0" ao lado do coração é ruído: o vazio já diz.
    await _pump(tester, likes: 0);
    expect(find.text('0'), findsNothing);

    await _pump(tester, likes: 4);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('só o dono vê a ação de apagar', (tester) async {
    await _pump(tester, isMine: false, onDelete: () {});
    expect(find.byKey(const ValueKey('apagar-p1')), findsNothing);

    await _pump(tester, isMine: true, onDelete: () {});
    expect(find.byKey(const ValueKey('apagar-p1')), findsOneWidget);
  });

  testWidgets('apagar pergunta antes', (tester) async {
    var apagou = false;
    await _pump(tester, isMine: true, onDelete: () => apagou = true);

    await tester.tap(find.byKey(const ValueKey('apagar-p1')));
    await tester.pumpAndSettle();
    expect(find.text('Apagar publicação?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(apagou, isFalse);

    await tester.tap(find.byKey(const ValueKey('apagar-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    expect(apagou, isTrue);
  });

  testWidgets('post sem texto não desenha texto vazio', (tester) async {
    await _pump(tester, post: _post(text: ''));

    expect(find.text(''), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o nome do autor não quebra linha', (tester) async {
    await _pump(
      tester,
      author: const PublicProfile(
        uid: 'uid-ana',
        name: 'Ana Souza de Albuquerque Cavalcanti Nogueira Filha',
        nickName: 'ana.a1',
        updatedAt: '2026-08-07T10:00:00.000',
      ),
    );

    final nome = tester.widget<Text>(
      find.text('Ana Souza de Albuquerque Cavalcanti Nogueira Filha'),
    );
    expect(nome.maxLines, 1);
    expect(nome.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}
