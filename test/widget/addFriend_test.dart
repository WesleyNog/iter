import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/screens/addFriend.dart';

/// A tela sobe sem Firebase porque só recebe o `uid` — o Firestore só é
/// tocado *dentro* da busca. Os casos aqui são exatamente os que **não**
/// chegam à rede, e é de propósito: são eles que decidem se a rede é chamada.
Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    const MaterialApp(home: AddFriend(uid: 'meu-uid')),
  );
}

Future<void> _buscar(WidgetTester tester, String texto) async {
  await tester.enterText(find.byType(TextField), texto);
  await tester.tap(find.byKey(const ValueKey('buscar-amigo')));
  await tester.pump();
}

void main() {
  testWidgets('abre com o campo vazio e sem resultado', (tester) async {
    await _pump(tester);

    expect(find.text('Adicionar amigo'), findsOneWidget);
    expect(find.byKey(const ValueKey('resultado-amigo')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('campo vazio não busca nem reclama', (tester) async {
    await _pump(tester);
    await _buscar(tester, '   ');

    // Nada de "ninguém usa esse apelido" para quem não digitou nada.
    expect(find.textContaining('Ninguém usa'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('apelido curto demais não vai à rede', (tester) async {
    await _pump(tester);
    await _buscar(tester, 'ab');

    // Se tivesse ido à rede, o Firestore não inicializado teria estourado.
    expect(find.textContaining('Apelido inválido'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('apelido longo demais não vai à rede', (tester) async {
    await _pump(tester);
    await _buscar(tester, 'a' * 21);

    expect(find.textContaining('Apelido inválido'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('só símbolo normaliza para vazio e não vai à rede', (
    tester,
  ) async {
    await _pump(tester);
    await _buscar(tester, '!!!');

    expect(find.textContaining('Apelido inválido'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrigir a entrada limpa a mensagem anterior', (tester) async {
    await _pump(tester);
    await _buscar(tester, 'ab');
    expect(find.textContaining('Apelido inválido'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byKey(const ValueKey('buscar-amigo')));
    await tester.pump();

    expect(find.textContaining('Apelido inválido'), findsNothing);
  });

  testWidgets('o campo mostra o @ e o teclado de busca', (tester) async {
    await _pump(tester);

    final campo = tester.widget<TextField>(find.byType(TextField));
    expect(campo.decoration?.prefixText, '@');
    // Enter no teclado busca, sem obrigar a mirar no botão.
    expect(campo.textInputAction, TextInputAction.search);
    expect(campo.onSubmitted, isNotNull);
  });
}
