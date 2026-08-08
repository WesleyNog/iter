import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/friendTile.dart';

Future<void> _pump(
  WidgetTester tester, {
  PublicProfile? profile,
  String? nickNameFallback,
  Widget? trailing,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FriendTile(
          uid: 'abc123',
          profile: profile,
          nickNameFallback: nickNameFallback,
          trailing: trailing,
        ),
      ),
    ),
  );
}

const _completo = PublicProfile(
  uid: 'abc123',
  name: 'João Pedro',
  nickName: 'joao.p3',
  updatedAt: '2026-08-07T10:00:00.000',
);

void main() {
  testWidgets('com perfil, mostra nome e @apelido', (tester) async {
    await _pump(tester, profile: _completo);

    expect(find.text('João Pedro'), findsOneWidget);
    expect(find.text('@joao.p3'), findsOneWidget);
  });

  testWidgets('sem perfil publicado, o @apelido vira o título', (tester) async {
    // O estado de quem já usava o app antes desta entrega e não reabriu.
    // Linha em branco seria pior que um apelido.
    await _pump(tester, nickNameFallback: 'maria.s7');

    expect(find.text('@maria.s7'), findsOneWidget);
    // Sem nome, o apelido não se repete embaixo.
    expect(find.text('@maria.s7'), findsOneWidget);
  });

  testWidgets('sem perfil e sem apelido, ainda desenha alguma coisa', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Entregador'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem foto, mostra a inicial do nome', (tester) async {
    await _pump(tester, profile: _completo);

    expect(find.text('J'), findsOneWidget);
  });

  testWidgets('a inicial ignora o @ do apelido', (tester) async {
    // Sem isto, todo mundo sem perfil publicado teria a mesma inicial: "@".
    await _pump(tester, nickNameFallback: 'maria.s7');

    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('o nome não quebra linha', (tester) async {
    await _pump(
      tester,
      profile: const PublicProfile(
        uid: 'abc123',
        name: 'João Pedro da Silva Nogueira Albuquerque Cavalcanti',
        nickName: 'joao.p3',
        updatedAt: '2026-08-07T10:00:00.000',
      ),
    );

    // Testar a causa, não "o texto cabe": a fonte do teste mede outra coisa
    // que a do aparelho.
    final titulo = tester.widget<Text>(
      find.text('João Pedro da Silva Nogueira Albuquerque Cavalcanti'),
    );
    expect(titulo.maxLines, 1);
    expect(titulo.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o trailing recebido aparece', (tester) async {
    await _pump(
      tester,
      profile: _completo,
      trailing: const Icon(Icons.chevron_right),
    );

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
