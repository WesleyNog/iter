/// Descobre se a CDN da imagin **tem** o veículo pedido.
///
/// Separado de `Utils/carImage.dart` porque aquilo é montagem de string e este
/// arquivo fala com a rede — a mesma divisão de `Utils/weather.dart` e
/// `services/openWeather.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// `true` quando a CDN tem uma imagem para a URL, `false` quando devolveria o
/// desenho de um carro coberto por uma lona, `null` quando não deu para saber.
///
/// **Isto filtra "não tem imagem", não "tem a imagem errada".** Pedir
/// `honda/cg` responde `found=true` entregando um Honda Pilot: o header sabe
/// que achou *alguma coisa*, não que achou a coisa certa. Quem resolve o
/// segundo caso é a confirmação do usuário na tela — as duas camadas existem
/// porque nenhuma das duas basta sozinha.
Future<bool?> imaginHasImage(String url) async {
  try {
    // `HEAD`: só os headers interessam, e baixar 60 KB de imagem para depois
    // decidir mostrá-la seria pagar duas vezes.
    final response = await http
        .head(Uri.parse(url))
        .timeout(const Duration(seconds: 8));

    final found = response.headers['x-imaginstudio-request-found'];
    if (found == null) return null;

    return found.trim().toLowerCase() == 'true';
  } catch (e) {
    debugPrint('imagin: falha ao checar a imagem: $e');
    return null;
  }
}
