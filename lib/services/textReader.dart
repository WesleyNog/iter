/// OCR no aparelho, por canal nativo: o Vision da Apple no iOS, o ML Kit no
/// Android.
///
/// **Por que canal, e não o pacote `google_mlkit_text_recognition`.** O pacote
/// foi instalado primeiro e o simulador iOS deixou de compilar: os frameworks
/// do ML Kit para iOS trazem só `x86_64` (simulador em Mac Intel) e `arm64` de
/// aparelho, e nenhuma fatia de simulador para Mac com chip Apple. O contorno
/// — compilar todo simulador como Intel, sob Rosetta — pesaria sobre o app
/// inteiro e tem prazo, porque a Apple está tirando o Rosetta. O Vision vem no
/// iOS, roda no simulador e foi ele que leu as fotos de etiqueta que motivaram
/// a feature. Ver "Desvios" em `docs/specs/leitor-de-pacotes.md`.
///
/// O contrato é um só nas duas pontas (`MainActivity.kt` e `TextReader.swift`):
/// método `read`, argumento `{path}`, resposta uma lista de linhas
/// `{text, left, top, right, bottom, elements: [...]}`, em **pixels da imagem,
/// origem no canto de cima à esquerda** — o espaço dos cantos do QR que o
/// `mobile_scanner` devolve. Cada ponta converte do que o motor dela dá: o
/// Vision mede de 0 a 1 a partir de baixo, o ML Kit já mede em pixels.
///
/// A imagem tem nome e endereço de terceiros: nenhuma das pontas loga texto
/// lido, nem nos erros.
library;

import 'package:flutter/services.dart';
import 'package:iter/Utils/packageLabel.dart';

class TextReader {
  static const channel = MethodChannel('iter/ocr');

  /// As linhas de texto do JPEG em [path].
  ///
  /// Lança [PlatformException] quando o motor falha — quem chama decide; o
  /// leitor de pacotes conta o pacote pelo QR e tenta de novo no quadro
  /// seguinte.
  static Future<List<OcrLine>> read(String path) async {
    final raw = await channel.invokeListMethod<Object?>('read', {'path': path});
    return ocrLinesFrom(raw ?? const []);
  }
}

/// A resposta do canal no tipo do parser.
///
/// Entrada fora do formato é **descartada**, não lança: uma linha estranha que
/// um motor devolvesse num aparelho qualquer não pode derrubar a leitura das
/// outras — e o parser já trata linha que falta como dado que falta.
List<OcrLine> ocrLinesFrom(List<Object?> raw) => [
  for (final item in raw) ?_lineFrom(item),
];

OcrLine? _lineFrom(Object? item) {
  if (item is! Map) return null;

  final text = item['text'];
  final box = _rectFrom(item);
  if (text is! String || box == null) return null;

  final elements = item['elements'];
  return OcrLine(
    text,
    box,
    elements: elements is List ? ocrLinesFrom(elements) : const [],
  );
}

Rect? _rectFrom(Map<Object?, Object?> item) {
  final left = _number(item['left']);
  final top = _number(item['top']);
  final right = _number(item['right']);
  final bottom = _number(item['bottom']);
  if (left == null || top == null || right == null || bottom == null) {
    return null;
  }
  if (right < left || bottom < top) return null;
  return Rect.fromLTRB(left, top, right, bottom);
}

/// O canal entrega `int` ou `double` conforme a plataforma e o valor.
double? _number(Object? raw) => raw is num ? raw.toDouble() : null;
