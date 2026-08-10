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
  int comments = 0,
  bool isMine = false,
  ValueChanged<bool>? onLike,
  VoidCallback? onComment,
  VoidCallback? onDelete,
  VoidCallback? onReport,
  VoidCallback? onBlock,
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
          comments: comments,
          isMine: isMine,
          onLike: onLike ?? (_) {},
          onComment: onComment ?? () {},
          onDelete: onDelete,
          onReport: onReport,
          onBlock: onBlock,
        ),
      ),
    ),
  );
}

/// Abre o menu do card. Os itens de um `PopupMenuButton` só existem na árvore
/// depois do toque — asserção sobre eles com o menu fechado passa sozinha e não
/// prova nada.
Future<void> _abreMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-p1')));
  await tester.pumpAndSettle();
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

  testWidgets('no post próprio o menu só apaga', (tester) async {
    // Ninguém se denuncia nem se bloqueia.
    await _pump(tester, isMine: true, onDelete: () {});
    await _abreMenu(tester);

    expect(find.text('Apagar publicação'), findsOneWidget);
    expect(find.text('Denunciar publicação'), findsNothing);
    expect(find.text('Bloquear'), findsNothing);
  });

  testWidgets('no post alheio o menu denuncia e bloqueia, e não apaga', (
    tester,
  ) async {
    // Antes desta entrega o post alheio não tinha menu nenhum: num mural
    // global, isso é dizer que ninguém tem o que reclamar.
    await _pump(
      tester,
      isMine: false,
      onDelete: () {},
      onReport: () {},
      onBlock: () {},
    );
    await _abreMenu(tester);

    expect(find.text('Denunciar publicação'), findsOneWidget);
    expect(find.text('Bloquear'), findsOneWidget);
    expect(find.text('Apagar publicação'), findsNothing);
  });

  testWidgets('sem ação nenhuma, o menu não aparece', (tester) async {
    await _pump(tester, isMine: false);
    expect(find.byKey(const ValueKey('menu-p1')), findsNothing);
  });

  testWidgets('denunciar e bloquear avisam quem pediu', (tester) async {
    var denunciou = false;
    var bloqueou = false;
    await _pump(
      tester,
      isMine: false,
      onReport: () => denunciou = true,
      onBlock: () => bloqueou = true,
    );

    await _abreMenu(tester);
    await tester.tap(find.text('Denunciar publicação'));
    await tester.pumpAndSettle();
    expect(denunciou, isTrue);
    expect(bloqueou, isFalse);

    await _abreMenu(tester);
    await tester.tap(find.text('Bloquear'));
    await tester.pumpAndSettle();
    expect(bloqueou, isTrue);
  });

  testWidgets('apagar pergunta antes', (tester) async {
    var apagou = false;
    await _pump(tester, isMine: true, onDelete: () => apagou = true);

    await _abreMenu(tester);
    await tester.tap(find.text('Apagar publicação'));
    await tester.pumpAndSettle();
    expect(find.text('Apagar publicação?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(apagou, isFalse);

    await _abreMenu(tester);
    await tester.tap(find.text('Apagar publicação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    expect(apagou, isTrue);
  });

  testWidgets('comentar avisa, e zero comentário não mostra o número', (
    tester,
  ) async {
    var abriu = false;
    await _pump(tester, comments: 0, onComment: () => abriu = true);

    // "0" ao lado do balão é ruído, exatamente como ao lado do coração.
    expect(find.text('0'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('comentar-p1')));
    await tester.pumpAndSettle();
    expect(abriu, isTrue);

    await _pump(tester, comments: 3);
    expect(find.text('3'), findsOneWidget);
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
