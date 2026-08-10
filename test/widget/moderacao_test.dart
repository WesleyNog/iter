import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/report.dart';
import 'package:iter/widget/blockDialog.dart';
import 'package:iter/widget/reportSheet.dart';

/// As duas telas de moderação que não tocam o Firestore: a folha que escolhe o
/// motivo e o dialog que confirma o bloqueio. O que grava está coberto pelos
/// testes de regra no emulador (`firestore-tests`).
Future<void> _pump(
  WidgetTester tester,
  Future<void> Function(BuildContext) go,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => go(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('folha de denúncia', () {
    testWidgets('oferece todos os motivos da lista fechada', (tester) async {
      await _pump(tester, (c) => showReportSheet(c, isComment: false));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      for (final reason in ReportReason.values) {
        expect(
          find.byKey(ValueKey('motivo-${reason.name}')),
          findsOneWidget,
          reason: 'faltou ${reason.name}',
        );
      }
    });

    testWidgets('o título diz se é post ou comentário', (tester) async {
      await _pump(tester, (c) => showReportSheet(c, isComment: false));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Denunciar publicação'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await _pump(tester, (c) => showReportSheet(c, isComment: true));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Denunciar comentário'), findsOneWidget);
    });

    testWidgets('devolve o motivo escolhido, e null se desistir', (
      tester,
    ) async {
      ReportReason? escolhido;
      var respondeu = false;

      await _pump(tester, (c) async {
        escolhido = await showReportSheet(c, isComment: false);
        respondeu = true;
      });

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('motivo-golpe')));
      await tester.pumpAndSettle();
      expect(escolhido, ReportReason.golpe);

      // Fechar sem escolher tem de devolver null: mandar denúncia de quem
      // desistiu é pior do que não mandar nenhuma.
      respondeu = false;
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(respondeu, isTrue);
      expect(escolhido, isNull);
    });
  });

  group('confirmação do bloqueio', () {
    testWidgets('avisa que a amizade e os convites somem', (tester) async {
      // Bloquear apaga as duas arestas e os quatro marcadores. Confirmar sem
      // dizer isso é pedir uma decisão que a pessoa não tomou.
      await _pump(tester, (c) => confirmBlock(c, name: 'Ana Souza'));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Bloquear Ana Souza?'), findsOneWidget);
      expect(find.textContaining('deixam de ser amigos'), findsOneWidget);
    });

    testWidgets('cancelar devolve false, bloquear devolve true', (
      tester,
    ) async {
      bool? resposta;
      await _pump(tester, (c) async {
        resposta = await confirmBlock(c, name: 'Ana Souza');
      });

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(resposta, isFalse);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmar-bloqueio')));
      await tester.pumpAndSettle();
      expect(resposta, isTrue);
    });
  });
}
