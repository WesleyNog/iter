import Flutter
import UIKit
import Vision

/// O lado iOS do canal de OCR do leitor de pacotes — o contrato está em
/// `lib/services/textReader.dart`, e o lado Android em `MainActivity.kt`.
///
/// É o Vision, que vem no sistema: sem pod, roda no simulador, e foi ele que
/// leu as fotos de etiqueta que motivaram a feature (`docs/specs/
/// leitor-de-pacotes.md`). O pacote do ML Kit foi tentado antes e tirado — os
/// frameworks dele não têm fatia de simulador para Mac com chip Apple.
///
/// O Vision mede de 0 a 1 com a origem **embaixo** à esquerda; o contrato é em
/// pixels com a origem **em cima**, que é o espaço dos cantos do QR que o
/// `mobile_scanner` devolve. A conversão mora em `piece`, e só lá.
///
/// Os erros vão sem mensagem: o texto lido é o endereço de outra pessoa.
enum TextReader {
  static let channelName = "iter/ocr"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

    channel.setMethodCallHandler { call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String
      else {
        result(FlutterError(code: "bad-args", message: "path ausente", details: nil))
        return
      }

      // O reconhecimento `.accurate` leva centenas de milissegundos: fora da
      // thread principal, e a resposta volta para ela.
      DispatchQueue.global(qos: .userInitiated).async {
        let lines = read(path: path)
        DispatchQueue.main.async {
          if let lines {
            result(lines)
          } else {
            result(FlutterError(code: "ocr-failed", message: nil, details: nil))
          }
        }
      }
    }
  }

  private static func read(path: String) -> [[String: Any]]? {
    // `cgImage` ignora a orientação do `UIImage` — e é o certo aqui: o JPEG do
    // `mobile_scanner` já vem em pé e sem EXIF, e é nesse espaço que estão os
    // cantos do QR.
    guard let image = UIImage(contentsOfFile: path)?.cgImage else { return nil }
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["pt-BR"]
    // A correção de idioma "conserta" nome de rua e bairro para palavras do
    // dicionário — e a letra solta da tarja para coisa nenhuma.
    request.usesLanguageCorrection = false

    do {
      try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        .perform([request])
    } catch {
      return nil
    }

    return (request.results ?? []).compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let text = candidate.string

      // As palavras, com a posição de cada uma: a letra do tipo às vezes vem
      // grudada na linha vizinha da mesma altura.
      var elements: [[String: Any]] = []
      text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) {
        word, range, _, _ in
        guard let word, let box = try? candidate.boundingBox(for: range) else { return }
        elements.append(piece(word, box.boundingBox, width, height))
      }

      var line = piece(text, observation.boundingBox, width, height)
      line["elements"] = elements
      return line
    }
  }

  /// De 0–1 com origem embaixo para pixels com origem em cima.
  private static func piece(
    _ text: String, _ box: CGRect, _ width: CGFloat, _ height: CGFloat
  ) -> [String: Any] {
    [
      "text": text,
      "left": Double(box.minX * width),
      "top": Double((1 - box.maxY) * height),
      "right": Double(box.maxX * width),
      "bottom": Double((1 - box.minY) * height),
    ]
  }
}
