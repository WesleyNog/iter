import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/services/textReader.dart';

/// O lado Dart do contrato do canal de OCR. O lado nativo (`MainActivity.kt`,
/// `TextReader.swift`) só se verifica no aparelho; o que dá para fixar aqui é o
/// nome do método, o argumento e a leitura defensiva da resposta.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ocrLinesFrom', () {
    test('linha com posição e palavras', () {
      final lines = ocrLinesFrom([
        {
          'text': 'CEP: 60175045',
          'left': 65,
          'top': 934.5,
          'right': 216,
          'bottom': 960,
          'elements': [
            {
              'text': 'CEP:',
              'left': 65,
              'top': 934,
              'right': 110,
              'bottom': 960,
            },
          ],
        },
      ]);

      expect(lines, hasLength(1));
      expect(lines.single.text, 'CEP: 60175045');
      expect(lines.single.box, const Rect.fromLTRB(65, 934.5, 216, 960));
      expect(lines.single.elements.single.text, 'CEP:');
    });

    test('entrada fora do formato é descartada, sem derrubar as outras', () {
      final lines = ocrLinesFrom([
        'lixo',
        {'text': 'sem posição'},
        {'text': 'invertida', 'left': 10, 'top': 0, 'right': 5, 'bottom': 5},
        {'text': 7, 'left': 0, 'top': 0, 'right': 5, 'bottom': 5},
        {'text': 'Papicu', 'left': 72, 'top': 883, 'right': 130, 'bottom': 909},
      ]);

      expect(lines.map((line) => line.text), ['Papicu']);
    });

    test('sem elementos, lista vazia', () {
      final lines = ocrLinesFrom([
        {'text': 'R', 'left': 554, 'top': 1088, 'right': 576, 'bottom': 1114},
      ]);

      expect(lines.single.elements, isEmpty);
    });
  });

  group('TextReader.read', () {
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TextReader.channel, null),
    );

    test('chama "read" com o caminho do arquivo', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TextReader.channel, (call) async {
            received = call;
            return [
              {'text': 'R', 'left': 1, 'top': 2, 'right': 3, 'bottom': 4},
            ];
          });

      final lines = await TextReader.read('/tmp/quadro.jpg');

      expect(received!.method, 'read');
      expect(received!.arguments, {'path': '/tmp/quadro.jpg'});
      expect(lines.single.box, const Rect.fromLTRB(1, 2, 3, 4));
    });

    test('readRegion manda o recorte, a inversão e a ampliação', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TextReader.channel, (call) async {
            received = call;
            return [
              {'text': 'R', 'left': 10, 'top': 4, 'right': 60, 'bottom': 70},
            ];
          });

      final lines = await TextReader.readRegion(
        '/tmp/quadro.jpg',
        const Rect.fromLTRB(500, 1170, 700, 1230),
      );

      expect(received!.method, 'readRegion');
      expect(received!.arguments, {
        'path': '/tmp/quadro.jpg',
        'left': 500.0,
        'top': 1170.0,
        'right': 700.0,
        'bottom': 1230.0,
        'invert': true,
        'scale': 4,
        'binarize': false,
        'fast': false,
      });
      expect(lines.single.text, 'R');
    });

    test('falha do motor chega como PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            TextReader.channel,
            (call) async => throw PlatformException(code: 'ocr-failed'),
          );

      expect(
        TextReader.read('/tmp/quadro.jpg'),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
