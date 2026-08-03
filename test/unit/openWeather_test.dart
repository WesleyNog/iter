import 'package:flutter_test/flutter_test.dart';
import 'package:iter/services/openWeather.dart';

/// Recorte do que o `/data/2.5/weather` devolveu de verdade para Fortaleza.
const _respostaReal = '''
{"coord":{"lon":-38.5434,"lat":-3.7172},
 "weather":[{"id":801,"main":"Clouds","description":"few clouds","icon":"02n"}],
 "base":"stations","main":{"temp":27.25,"humidity":74},"name":"Fortaleza","cod":200}
''';

/// Formato do *timemachine* (histórico da One Call) — era **este** que o código
/// antigo tentava ler na resposta do tempo atual, e por isso nunca achava nada.
const _respostaTimemachine = '''
{"lat":-3.7172,"lon":-38.5434,
 "data":[{"dt":1785726000,"weather":[{"id":500,"main":"Rain"}]}]}
''';

void main() {
  test('lê weather[0].main da raiz da resposta', () {
    expect(parseCurrentWeather(_respostaReal), WeatherType.clouds);
  });

  test('resposta do timemachine não é lida como tempo atual', () {
    // Não é o formato deste endpoint: melhor "não sei" do que adivinhar.
    expect(parseCurrentWeather(_respostaTimemachine), isNull);
  });

  test('erro da API não vira sol', () {
    // Exatamente o corpo que a One Call 3.0 devolve sem assinatura.
    const erro =
        '{"cod":401,"message":"Please note that using One Call 3.0 requires '
        'a separate subscription to the One Call by Call plan."}';

    expect(parseCurrentWeather(erro), isNull);
    expect(parseCurrentWeather('{"cod":"404","message":"Internal error"}'), isNull);
  });

  test('resposta ilegível ou vazia devolve null em vez de explodir', () {
    expect(parseCurrentWeather('não é json'), isNull);
    expect(parseCurrentWeather('{"weather":[]}'), isNull);
    expect(parseCurrentWeather('{"weather":"chuva"}'), isNull);
    expect(parseCurrentWeather('[]'), isNull);
  });

  test('main desconhecido cai no padrão em vez de quebrar', () {
    expect(
      parseCurrentWeather('{"weather":[{"main":"Sunshine"}]}'),
      WeatherType.clear,
    );
  });

  test('todo tipo sobrevive à ida e volta do Firestore', () {
    // A rota grava `type.name` e o card lê com `fromString`. Antes a comparação
    // era `type.name == value.toLowerCase()`, então qualquer valor camelCase
    // — `fewClouds`, `heavyRain` — voltava como sol, calado.
    for (final type in WeatherType.values) {
      expect(WeatherType.fromString(type.name), type, reason: type.name);
    }
  });

  test('cada tipo do OpenWeather vira seu WeatherType', () {
    for (final type in WeatherType.values) {
      // A API manda com inicial maiúscula ("Thunderstorm"); o enum é minúsculo.
      final main = type.name[0].toUpperCase() + type.name.substring(1);
      expect(parseCurrentWeather('{"weather":[{"main":"$main"}]}'), type);
    }
  });
}
