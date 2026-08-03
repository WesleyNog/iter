import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

enum WeatherType {
  clear,
  clouds,
  rain,
  snow,
  thunderstorm,
  drizzle,
  mist,
  smoke,
  haze,
  dust,
  fog,
  sand,
  ash,
  squall,
  tornado,

  // Os dois abaixo não existem no `main` da OpenWeather — ela diz só "Clouds"
  // ou "Rain", e a intensidade fica no `description`. Existem porque o app tem
  // ícone para eles e o usuário pode escolhê-los à mão.
  fewClouds,
  heavyRain;

  static WeatherType fromString(String value) {
    return WeatherType.values.firstWhere(
      // `toLowerCase()` dos **dois** lados: sem isso um valor camelCase como
      // `fewClouds` nunca voltaria da leitura — viraria sol silenciosamente.
      (type) => type.name.toLowerCase() == value.toLowerCase(),
      orElse: () =>
          WeatherType.clear, // Valor padrão caso venha um tipo desconhecido
    );
  }
}

/// Tempo do momento, endpoint gratuito.
///
/// A One Call (3.0) daria o tempo de uma **data passada** — o caso de quem só
/// cadastra a rota dias depois de rodá-la — mas exige o plano "One Call by
/// Call". Com a chave de hoje ela responde 401, tanto em `/3.0/onecall` quanto
/// no `/timemachine`. Enquanto a assinatura não valer, só dá para saber o tempo
/// de agora, e é isso que este arquivo faz.
const _currentUrl = 'https://api.openweathermap.org/data/2.5/weather';

/// Devolve `null` quando **não deu para saber** — sem chave, sem rede, resposta
/// inesperada.
///
/// A versão anterior devolvia [WeatherType.clear] em todos esses casos, o que
/// tornava "deu erro" indistinguível de "está fazendo sol": o app passou a
/// mostrar sol sempre, e nada na tela denunciava a falha.
Future<WeatherType?> getWeather(double lat, double lon) async {
  final apiKey = dotenv.isInitialized ? dotenv.maybeGet('OPEN-WEATHER') : null;
  if (apiKey == null || apiKey.isEmpty) {
    debugPrint('OpenWeather: OPEN-WEATHER ausente ou .env não carregado.');
    return null;
  }

  final url = Uri.parse('$_currentUrl?lat=$lat&lon=$lon&appid=$apiKey');

  try {
    final response = await http.get(url);

    if (response.statusCode != 200) {
      debugPrint('OpenWeather: HTTP ${response.statusCode} — ${response.body}');
      return null;
    }

    return parseCurrentWeather(response.body);
  } catch (e) {
    debugPrint('OpenWeather: falha ao consultar o tempo: $e');
    return null;
  }
}

/// Lê `weather[0].main` da **raiz** da resposta do `/2.5/weather`.
///
/// A versão anterior procurava em `data[0].weather[0].main`, que é o formato do
/// *timemachine* (histórico da One Call), não o do tempo atual — então, mesmo
/// com a URL certa, não acharia nada.
///
/// Separada de [getWeather] para poder ser testada sem rede.
WeatherType? parseCurrentWeather(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final weather = decoded['weather'];
    if (weather is! List || weather.isEmpty) return null;

    final first = weather.first;
    if (first is! Map) return null;

    final main = first['main'];
    return main is String ? WeatherType.fromString(main) : null;
  } catch (e) {
    debugPrint('OpenWeather: resposta ilegível: $e');
    return null;
  }
}
