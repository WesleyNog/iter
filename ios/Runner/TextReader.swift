import CoreImage
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
      guard call.method == "read" || call.method == "readRegion" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String
      else {
        result(FlutterError(code: "bad-args", message: "path ausente", details: nil))
        return
      }

      var region: CGRect?
      if call.method == "readRegion" {
        guard let left = (args["left"] as? NSNumber)?.doubleValue,
              let top = (args["top"] as? NSNumber)?.doubleValue,
              let right = (args["right"] as? NSNumber)?.doubleValue,
              let bottom = (args["bottom"] as? NSNumber)?.doubleValue
        else {
          result(FlutterError(code: "bad-args", message: "recorte ausente", details: nil))
          return
        }
        region = CGRect(x: left, y: top, width: right - left, height: bottom - top)
      }
      let invert = args["invert"] as? Bool ?? false
      let scale = max(1, (args["scale"] as? NSNumber)?.intValue ?? 1)

      // O reconhecimento `.accurate` leva centenas de milissegundos: fora da
      // thread principal, e a resposta volta para ela.
      DispatchQueue.global(qos: .userInitiated).async {
        let lines = read(path: path, region: region, invert: invert, scale: scale)
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

  private static func read(
    path: String, region: CGRect?, invert: Bool, scale: Int
  ) -> [[String: Any]]? {
    // `cgImage` ignora a orientação do `UIImage` — e é o certo aqui: o JPEG do
    // `mobile_scanner` já vem em pé e sem EXIF, e é nesse espaço que estão os
    // cantos do QR.
    guard let full = UIImage(contentsOfFile: path)?.cgImage else { return nil }

    guard let region else { return recognize(full) }

    // O recorte da tarja da letra: branco sobre preto, ~12 px de altura no
    // quadro inteiro. Invertido e ampliado, vira uma letra preta de ~50 px,
    // que é o tamanho em que o Vision lê letra solta.
    let bounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
    let crop = region.integral.intersection(bounds)
    guard !crop.isNull, crop.width >= 4, crop.height >= 4,
          let cropped = full.cropping(to: crop)
    else { return [] }

    var image = CIImage(cgImage: cropped)
    if invert { image = image.applyingFilter("CIColorInvert") }
    if scale > 1 {
      image = image.applyingFilter(
        "CILanczosScaleTransform",
        parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
    }
    guard let prepared = CIContext().createCGImage(image, from: image.extent)
    else { return nil }

    return recognize(prepared)
  }

  private static func recognize(_ image: CGImage) -> [[String: Any]]? {
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
