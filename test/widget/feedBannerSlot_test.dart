import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/services/feedBanners.dart';
import 'package:iter/widget/feedAdSlot.dart';
import 'package:iter/widget/feedBannerSlot.dart';

class _FakeBanner implements LoadedBanner {
  bool disposed = false;

  @override
  Widget get view => const ColoredBox(
    key: Key('banner'),
    color: Colors.orange,
  );

  @override
  double get height => 60;

  @override
  void dispose() => disposed = true;
}

void main() {
  late List<int> widths;
  late Completer<LoadedBanner?> arrival;
  late FeedBanners banners;

  /// A lista tem 16 px de margem de cada lado, como o mural.
  ///
  /// O `Completer` nasce **aqui dentro**, e não num `setUp`: criado fora da
  /// zona de tempo simulado do `testWidgets`, a conclusão dele agenda a
  /// continuação na fila real de microtarefas, que o `pump` não esvazia — e o
  /// banner "nunca chega", com o código certo.
  Future<void> pump(WidgetTester tester) async {
    widths = [];
    arrival = Completer();
    banners = FeedBanners(
      unitId: 'unidade',
      load: ({required unitId, required width, required maxHeight}) {
        widths.add(width);
        return arrival.future;
      },
    );
    addTearDown(banners.dispose);

    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              FeedBannerSlot(anchorId: 'p3', banners: banners),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('pede uma vez, com a largura de DENTRO da moldura', (
    tester,
  ) async {
    await pump(tester);

    // 390 da tela − 32 de margem − 2 de borda. A largura da tela inteira
    // pediria um banner mais largo que o espaço, e a view nativa vazaria da
    // borda.
    expect(widths, [390 - 32 - 2]);

    // Reconstruir não pede de novo.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              FeedBannerSlot(anchorId: 'p3', banners: banners),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(widths, hasLength(1));
  });

  testWidgets('a caminho: rótulo e altura reservada, para a lista não saltar', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('PUBLICIDADE'), findsOneWidget);
    expect(find.byKey(const Key('banner')), findsNothing);
  });

  testWidgets('carregou: o banner aparece dentro da moldura, com o rótulo', (
    tester,
  ) async {
    await pump(tester);

    arrival.complete(_FakeBanner());
    await tester.pumpAndSettle();

    expect(find.text('PUBLICIDADE'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FeedAdSlot),
        matching: find.byKey(const Key('banner')),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(find.byKey(const Key('banner'))).height, 60);
  });

  testWidgets('sem anúncio: o slot some inteiro, rótulo incluído', (
    tester,
  ) async {
    // Um buraco com "PUBLICIDADE" em cima é pior que nenhum anúncio.
    await pump(tester);

    arrival.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('PUBLICIDADE'), findsNothing);
    expect(find.byType(FeedAdSlot), findsNothing);
  });
}
