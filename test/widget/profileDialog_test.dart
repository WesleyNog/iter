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
  pacedMinutes: 1950,
  pacedStops: 300,
);

Future<void> _pump(
  WidgetTester tester, {
  Future<ProfileStats>? stats,
  String? nickName = 'wesley-efmg',
  VoidCallback? onAction,
  String? qrPayload,
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
          qrPayload: qrPayload,
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
    // A empresa aparece como logo + fatia, e não como nome em duas linhas: a
    // segunda linha desalinhava o valor desta coluna em relação às vizinhas.
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('Shopee\n62%'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    // O nome não some: fica no leitor de tela e no toque longo. O finder é
    // por ancestral do percentual, e não `byType(Tooltip)` — o X de fechar
    // também tem um, e "o primeiro Tooltip da tela" é asserção que passa a
    // significar outra coisa no dia em que alguém acrescentar um botão.
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: find.text('62%'), matching: find.byType(Tooltip)),
          )
          .message,
      'Shopee',
    );
    // A duração e o ritmo na mesma linha, e não um embaixo do outro: duas
    // linhas nesta coluna a desalinhavam das vizinhas. "6h30" é o dia que o
    // entregador reconhece, "6,5 m/p" é o que o compara com quem pega rota de
    // outro tamanho — e nenhum dos dois substitui o outro.
    expect(find.text('6h30 · 6,5 m/p'), findsOneWidget);
  });

  testWidgets('carreira sem ritmo não desenha um segundo travessão', (
    tester,
  ) async {
    // É o perfil publicado antes de o ritmo existir: tem tempo médio, não tem
    // paradas cronometradas. A linha some — dois "—" empilhados na mesma
    // coluna pareceriam duas métricas quebradas em vez de uma ausente.
    await _pump(
      tester,
      stats: Future.value(
        const ProfileStats(
          routes: 17,
          deliveredPackages: 551,
          stops: 506,
          averageDuration: Duration(hours: 2, minutes: 49),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Só a duração, sem um segundo travessão pendurado depois do separador.
    expect(find.text('2h49'), findsOneWidget);
    expect(find.textContaining('m/p'), findsNothing);
    expect(find.textContaining('·'), findsNothing);
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

  group('o QR do próprio perfil', () {
    /// Tela de celular de verdade.
    ///
    /// O padrão do teste é 800×600 — mais **baixo** que qualquer aparelho —, e
    /// a face do QR é mais alta que a dos números: no viewport padrão a linha
    /// de botões sai da área visível e o toque não chega nela. Isso não é
    /// defeito do dialog (o `SingleChildScrollView` rola), é o teste medindo
    /// numa tela que não existe.
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(390 * 3, 844 * 3);
      view.devicePixelRatio = 3.0;
      addTearDown(view.reset);
    });

    testWidgets('sem payload, não há botão de QR nem face de trás', (
      tester,
    ) async {
      // É o perfil de um **amigo**: o QR é o convite dele, e oferecer daqui
      // deixaria qualquer um distribuir o convite de outra pessoa.
      await _pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('girar-qr')), findsNothing);
      expect(find.byKey(const ValueKey('qr-amigo')), findsNothing);
    });

    testWidgets('o botão vira o cartão e mostra o QR', (tester) async {
      await _pump(tester, qrPayload: 'iter://amigo/wesley-efmg');
      await tester.pumpAndSettle();

      // De frente: os números, nenhum QR.
      expect(find.text('128'), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-amigo')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('girar-qr')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('qr-amigo')), findsOneWidget);
      expect(find.text('128'), findsNothing);
    });

    testWidgets('o mesmo botão volta para os números', (tester) async {
      await _pump(tester, qrPayload: 'iter://amigo/wesley-efmg');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('girar-qr')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('girar-qr')));
      await tester.pumpAndSettle();

      expect(find.text('128'), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-amigo')), findsNothing);
    });

    testWidgets('o apelido continua à vista na face do QR', (tester) async {
      // Quando a câmera do outro não coopera, digitar é a saída — e por isso
      // o cabeçalho fica fora do `Transform` que gira.
      await _pump(tester, qrPayload: 'iter://amigo/wesley-efmg');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('girar-qr')));
      await tester.pumpAndSettle();

      expect(find.text('@wesley-efmg'), findsOneWidget);
      expect(find.text('Wesley Nogueira'), findsOneWidget);
    });

    testWidgets('o compartilhar continua ao alcance nas duas faces', (
      tester,
    ) async {
      var compartilhou = 0;
      await _pump(
        tester,
        qrPayload: 'iter://amigo/wesley-efmg',
        onAction: () => compartilhou++,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('COMPARTILHAR'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('girar-qr')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('COMPARTILHAR'));
      await tester.pump();

      expect(compartilhou, 2);
    });

    testWidgets('girar não derruba o dialog nem levanta exceção', (
      tester,
    ) async {
      // O meio do giro é onde mora o erro: é lá que a face troca e que a
      // altura das duas difere. Bombeia quadro a quadro em vez de assentar.
      await _pump(tester, qrPayload: 'iter://amigo/wesley-efmg');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('girar-qr')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('qr-amigo')), findsOneWidget);
    });
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
