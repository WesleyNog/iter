import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/widget/profileDialog.dart';

const _stats = ProfileStats(
  routes: 128,
  deliveredPackages: 3412,
  stops: 2890,
  failureRate: 1.44,
  topCompany: (label: 'Shopee', share: 62.0),
  averageDuration: Duration(hours: 6, minutes: 30),
);

Future<void> _pump(
  WidgetTester tester, {
  Future<ProfileStats>? stats,
  String? nickName = 'wesley-efmg',
  VoidCallback? onAction,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProfileDialog(
          name: 'Wesley Nogueira',
          nickName: nickName,
          stats: stats ?? Future.value(_stats),
          actionLabel: 'Compartilhar',
          onAction: onAction ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra nome, apelido e as seis métricas', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Wesley Nogueira'), findsOneWidget);
    expect(find.text('@wesley-efmg'), findsOneWidget);

    expect(find.text('128'), findsOneWidget);
    expect(find.text('3412'), findsOneWidget);
    expect(find.text('2890'), findsOneWidget);

    expect(find.text('1.4%'), findsOneWidget);
    expect(find.text('Shopee\n62%'), findsOneWidget);
    expect(find.text('6h30'), findsOneWidget);
  });

  testWidgets('métrica sem como calcular mostra travessão, não zero', (
    tester,
  ) async {
    await _pump(
      tester,
      stats: Future.value(
        const ProfileStats(routes: 4, deliveredPackages: 0, stops: 0),
      ),
    );
    await tester.pumpAndSettle();

    // "0%" afirmaria um dado que não foi coletado.
    expect(find.text('—'), findsNWidgets(3));
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets('sem apelido, não sobra um @ solto', (tester) async {
    await _pump(tester, nickName: null);
    await tester.pumpAndSettle();

    expect(find.textContaining('@'), findsNothing);
  });

  testWidgets('enquanto carrega, o nome já aparece', (tester) async {
    // Future que nunca completa: é o estado de carregando.
    await _pump(tester, stats: Completer<ProfileStats>().future);
    await tester.pump();

    expect(find.text('Wesley Nogueira'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('128'), findsNothing);
  });

  testWidgets('erro ao ler as métricas não derruba o perfil', (tester) async {
    // A falha chega depois do dialog aberto, como na vida real: o widget já
    // está escutando quando o Firestore recusa a leitura.
    final reading = Completer<ProfileStats>();
    await _pump(tester, stats: reading.future);

    reading.completeError(Exception('permission-denied'));
    await tester.pumpAndSettle();

    // Nome e foto vêm da AppBar, então continuam de pé sem o Firestore.
    expect(find.text('Wesley Nogueira'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem rota nenhuma, convida a cadastrar a primeira', (
    tester,
  ) async {
    await _pump(
      tester,
      stats: Future.value(
        const ProfileStats(routes: 0, deliveredPackages: 0, stops: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Cadastre sua primeira rota para ver seus números.'),
      findsOneWidget,
    );
  });

  testWidgets('o botão dispara a ação recebida', (tester) async {
    var tapped = false;
    await _pump(tester, onAction: () => tapped = true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('COMPARTILHAR'));

    expect(tapped, isTrue);
  });

  testWidgets('o X fecha o dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProfileDialog(
                context,
                name: 'Wesley Nogueira',
                stats: Future.value(_stats),
                actionLabel: 'Compartilhar',
                onAction: () {},
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Wesley Nogueira'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Wesley Nogueira'), findsNothing);
  });
}
