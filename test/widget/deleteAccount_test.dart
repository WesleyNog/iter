import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/screens/deleteAccount.dart';

/// Empilha a tela por cima de uma "Home", como `home.dart` faz com `push` —
/// é o que deixa o teste ver o `popUntil` do sucesso.
Future<void> _pump(
  WidgetTester tester, {
  required Future<bool> Function() onDelete,
}) async {
  tester.view.physicalSize = const Size(411, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeleteAccountScreen(
                    email: 'zeca@exemplo.com',
                    onDelete: onDelete,
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

FilledButton _deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('excluir-conta')),
);

void main() {
  testWidgets('o botão só acende depois de marcar que entendeu', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      onDelete: () async {
        calls++;
        return false;
      },
    );

    expect(_deleteButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('excluir-conta')));
    await tester.pump();
    expect(calls, 0);

    await tester.tap(find.byKey(const ValueKey('entendo-exclusao')));
    await tester.pump();

    expect(_deleteButton(tester).onPressed, isNotNull);
  });

  testWidgets('diz o que fica, e qual conta o Google vai pedir', (
    tester,
  ) async {
    await _pump(tester, onDelete: () async => false);

    expect(find.text('O que continua, sem identificar você'), findsOneWidget);
    expect(find.textContaining('zeca@exemplo.com'), findsOneWidget);
  });

  testWidgets('desistir no seletor do Google não fecha a tela nem mostra erro', (
    tester,
  ) async {
    await _pump(tester, onDelete: () async => false);

    await tester.tap(find.byKey(const ValueKey('entendo-exclusao')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('excluir-conta')));
    await tester.pumpAndSettle();

    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.textContaining('não foi excluída'), findsNothing);
    // E dá para tentar de novo.
    expect(_deleteButton(tester).onPressed, isNotNull);
  });

  testWidgets('excluir tira a tela da pilha: o login aparece embaixo dela', (
    tester,
  ) async {
    await _pump(tester, onDelete: () async => true);

    await tester.tap(find.byKey(const ValueKey('entendo-exclusao')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('excluir-conta')));
    await tester.pumpAndSettle();

    expect(find.byType(DeleteAccountScreen), findsNothing);
    expect(find.text('abrir'), findsOneWidget);

    // O toast de sucesso se dispensa sozinho em 3 s; sem esperar, o teste
    // termina com timer pendente.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  group('a frase de cada falha', () {
    test('toda falha diz que a conta NÃO foi excluída', () {
      for (final error in [
        FirebaseAuthException(code: 'user-mismatch'),
        FirebaseAuthException(code: 'network-request-failed'),
        FirebaseAuthException(code: 'requires-recent-login'),
        FirebaseAuthException(code: 'algo-novo'),
        Exception('qualquer coisa'),
      ]) {
        expect(
          deleteAccountErrorMessage(error, email: 'zeca@exemplo.com'),
          contains('Sua conta não foi excluída.'),
        );
      }
    });

    test('outra conta Google: nomeia a conta certa', () {
      expect(
        deleteAccountErrorMessage(
          FirebaseAuthException(code: 'user-mismatch'),
          email: 'zeca@exemplo.com',
        ),
        contains('zeca@exemplo.com'),
      );
    });
  });
}
