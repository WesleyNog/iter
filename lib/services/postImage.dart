/// A foto do post, no Firebase Storage.
///
/// Primeiro uso do Storage no projeto. A foto do **veículo** continua em
/// base64 dentro do documento e não migra: são 1–3 documentos por usuário,
/// lidos só pelo dono. O feed é a única coisa do app que cresce sem teto, e é
/// nele que base64 apertava. Ver `docs/specs/amigos.md`.
library;

import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class PostImage {
  /// `posts/{uid}/{postId}.jpg` — o caminho que a regra do Storage exige e o
  /// que o documento guarda.
  static String pathFor(String uid, String postId) =>
      'posts/$uid/$postId.jpg';

  /// Escolhe e comprime, sem subir nada ainda.
  ///
  /// `maxWidth: 1080` contra os 800 do veículo: aquela foto vira uma miniatura
  /// de lista, esta ocupa a largura da tela. A qualidade continua em 70, que é
  /// onde o `image_picker` entrega ~150 KB.
  ///
  /// Devolve `null` quando o usuário desiste — que é diferente de falhar, e é
  /// por isso que a falha lança em vez de devolver `null` também.
  static Future<XFile?> pick(ImageSource source) {
    return ImagePicker().pickImage(
      source: source,
      maxWidth: 1080,
      imageQuality: 70,
    );
  }

  /// Sobe a foto e devolve o **caminho**, nunca a URL.
  ///
  /// A URL do `getDownloadURL()` carrega um token e é servida sem
  /// autenticação: não passa pelas `storage.rules`, funciona deslogado e fora
  /// do app, e revogar exige rodar o token à mão no console. Guardando o
  /// caminho, quem decide quem vê continua sendo a regra.
  /// Quanto tempo esperar antes de desistir.
  ///
  /// O SDK do Storage **repete sozinho por até 10 minutos** por padrão
  /// (`maxUploadRetryTime`), e sem prazo isso não vira erro: vira um botão
  /// girando para sempre. Quem está publicando uma foto do galpão prefere
  /// saber que falhou em meio minuto a esperar dez sem resposta.
  static const Duration timeout = Duration(seconds: 45);

  static Future<String> upload({
    required String uid,
    required String postId,
    required XFile file,
  }) async {
    final path = pathFor(uid, postId);
    final storage = FirebaseStorage.instance;

    // Sem isto, o `timeout` abaixo dispara mas o SDK continua tentando por
    // dez minutos em segundo plano, gastando a banda de quem já desistiu.
    storage.setMaxUploadRetryTime(timeout);

    await storage
        .ref(path)
        .putFile(File(file.path), SettableMetadata(contentType: 'image/jpeg'))
        .timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'Upload de $path passou de ${timeout.inSeconds}s',
          ),
        );

    return path;
  }

  /// A URL para exibir, resolvida por sessão a partir do caminho.
  ///
  /// `null` é **"não deu para saber"** — foto apagada, sem rede, regra negada.
  /// A tela desenha um espaço vazio em vez de um erro; o post continua
  /// legível pelo texto.
  static Future<String?> urlFor(String path) async {
    try {
      return await FirebaseStorage.instance.ref(path).getDownloadURL();
    } catch (e) {
      debugPrint('feed: imagem $path indisponível: $e');
      return null;
    }
  }

  /// Apaga o objeto. Melhor esforço: o Storage não sabe que o documento virou
  /// tombstone, e falhar aqui não pode impedir o post de ser apagado.
  static Future<void> remove(String path) async {
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (e) {
      debugPrint('feed: não foi possível apagar a imagem $path: $e');
    }
  }
}
