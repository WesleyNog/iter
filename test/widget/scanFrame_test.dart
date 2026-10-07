import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/scanFrame.dart';

void main() {
  group('ScanFrame', () {
    test('a janela fica centrada', () {
      final window = ScanFrame.windowIn(
        const Size(400, 800),
        const Size(300, 260),
      );

      expect(window, const Rect.fromLTWH(50, 270, 300, 260));
    });

    test('o fosco cobre o lado de fora e não a janela', () {
      final hole = RRect.fromRectAndRadius(
        const Rect.fromLTWH(50, 270, 300, 260),
        ScanFrame.radius,
      );
      final path = OutsideWindowClipper(hole).getClip(const Size(400, 800));

      expect(path.contains(const Offset(10, 10)), isTrue);
      expect(path.contains(const Offset(200, 790)), isTrue);
      expect(path.contains(const Offset(200, 400)), isFalse);
    });

    testWidgets('não intercepta toque', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ScanFrame(window: Size(300, 260))),
      );

      expect(
        find.descendant(
          of: find.byType(ScanFrame),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });
  });

  group('ScanMark', () {
    Future<void> pump(WidgetTester tester, ScanMarkKind kind, int serial) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: ScanMark(kind: kind, serial: serial),
            ),
          ),
        );

    testWidgets('contou é ✓, não contou é ✗', (tester) async {
      await pump(tester, ScanMarkKind.counted, 1);
      expect(find.byKey(const ValueKey('marca-contou')), findsOneWidget);

      await pump(tester, ScanMarkKind.notCounted, 2);
      expect(find.byKey(const ValueKey('marca-nao-contou')), findsOneWidget);
    });

    testWidgets('aparece e some sozinho', (tester) async {
      await pump(tester, ScanMarkKind.counted, 1);
      await tester.pump(ScanMark.duration * 0.4);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);

      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    });

    testWidgets('outro serial faz aparecer de novo', (tester) async {
      // Dois pacotes novos seguidos: o mesmo ✓, outro serial.
      await pump(tester, ScanMarkKind.counted, 1);
      await tester.pumpAndSettle();

      await pump(tester, ScanMarkKind.counted, 2);
      await tester.pump(ScanMark.duration * 0.4);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    });
  });
}
