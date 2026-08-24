import 'package:flutter_test/flutter_test.dart';
import 'package:iter/services/openWeather.dart';

/// Recorte do que o `/data/2.5/weather` devolveu de verdade para Fortaleza.
///
/// A captura foi **de noite** — é o que o `02n` do `icon` diz —, então ela virou
/// também o caso de teste do mapeamento noturno.
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

/// Só o céu — a maioria destes testes não fala dos horários do sol.
WeatherType? _sky(String body) => parseCurrentWeather(body)?.type;

void main() {
  test('lê weather[0].main da raiz da resposta', () {
    // Era `clouds` antes de o app saber distinguir dia de noite. O `02n` da
    // captura sempre disse "de noite"; o que mudou foi o código passar a ler.
    expect(_sky(_respostaReal), WeatherType.cloudsNight);
  });

  test('resposta do timemachine não é lida como tempo atual', () {
    // Não é o formato deste endpoint: melhor "não sei" do que adivinhar.
    expect(_sky(_respostaTimemachine), isNull);
  });

  test('erro da API não vira sol', () {
    // Exatamente o corpo que a One Call 3.0 devolve sem assinatura.
    const erro =
        '{"cod":401,"message":"Please note that using One Call 3.0 requires '
        'a separate subscription to the One Call by Call plan."}';

    expect(_sky(erro), isNull);
    expect(_sky('{"cod":"404","message":"Internal error"}'), isNull);
  });

  test('resposta ilegível ou vazia devolve null em vez de explodir', () {
    expect(_sky('não é json'), isNull);
    expect(_sky('{"weather":[]}'), isNull);
    expect(_sky('{"weather":"chuva"}'), isNull);
    expect(_sky('[]'), isNull);
  });

  test('main desconhecido cai no padrão em vez de quebrar', () {
    expect(
      _sky('{"weather":[{"main":"Sunshine"}]}'),
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
      expect(_sky('{"weather":[{"main":"$main"}]}'), type);
    }
  });

  group('dia e noite saem do sufixo do icon', () {
    String body(String main, String icon) =>
        '{"weather":[{"main":"$main","icon":"$icon"}]}';

    test('céu limpo de noite é noite limpa', () {
      // O caso que originou tudo: a Amazon tem muita rota depois das 19h, e sem
      // isto a única escolha era "Nublado" num céu limpo.
      expect(_sky(body('Clear', '01n')), WeatherType.clearNight);
    });

    test('céu limpo de dia continua sol', () {
      expect(_sky(body('Clear', '01d')), WeatherType.clear);
    });

    test('nublado de noite é noite nublada', () {
      expect(
        _sky(body('Clouds', '04n')),
        WeatherType.cloudsNight,
      );
    });

    test('nublado de dia continua nublado', () {
      expect(_sky(body('Clouds', '04d')), WeatherType.clouds);
    });

    test('chuva de noite continua chuva', () {
      // Só `clear` e `clouds` têm desenho noturno. Trocar os outros por um tipo
      // sem ícone estouraria o `Image.asset` na lista de rotas.
      expect(_sky(body('Rain', '10n')), WeatherType.rain);
      expect(
        _sky(body('Thunderstorm', '11n')),
        WeatherType.thunderstorm,
      );
      expect(_sky(body('Drizzle', '09n')), WeatherType.drizzle);
    });

    test('sem icon, ninguém vira noite', () {
      // Na dúvida não afirmar, que é a regra do arquivo inteiro: o tempo do dia
      // é a resposta que não inventa informação.
      expect(_sky('{"weather":[{"main":"Clear"}]}'),
          WeatherType.clear);
      expect(_sky('{"weather":[{"main":"Clear","icon":null}]}'),
          WeatherType.clear);
      expect(_sky('{"weather":[{"main":"Clear","icon":42}]}'),
          WeatherType.clear);
      expect(_sky('{"weather":[{"main":"Clear","icon":""}]}'),
          WeatherType.clear);
    });

    test('os dois tipos noturnos sobrevivem à ida e volta do Firestore', () {
      // A rota grava `type.name` — "clearNight" — e o card lê com `fromString`,
      // que compara em minúsculas. Um camelCase novo é exatamente o que já
      // voltou como sol calado uma vez neste arquivo.
      for (final type in [WeatherType.clearNight, WeatherType.cloudsNight]) {
        expect(WeatherType.fromString(type.name), type, reason: type.name);
      }
    });
  });

  group('o céu ajustado ao horário da rota', () {
    // Minutos do dia direto, sem timestamp: assim o teste não muda de resposta
    // conforme o fuso da máquina que o roda.
    const seisDaManha = 6 * 60;
    const seisDaTarde = 18 * 60;

    CurrentWeather comSol(WeatherType type) => CurrentWeather(
      type: type,
      sunrise: seisDaManha,
      sunset: seisDaTarde,
    );

    test('rota de dia não leva o céu noturno da consulta', () {
      // O caso que originou a correção: rota das 08h às 14h cadastrada às 21h.
      // A consulta trouxe "Noite limpa" porque eram 21h — e o card desenhava a
      // lua ao lado do horário que a desmentia.
      final tempo = comSol(WeatherType.clearNight);
      expect(tempo.at(DateTime(2026, 8, 24, 8)), WeatherType.clear);
    });

    test('rota de noite ganha o céu noturno mesmo com consulta de dia', () {
      final tempo = comSol(WeatherType.clouds);
      expect(tempo.at(DateTime(2026, 8, 24, 20)), WeatherType.cloudsNight);
    });

    test('madrugada também é noite', () {
      final tempo = comSol(WeatherType.clear);
      expect(tempo.at(DateTime(2026, 8, 24, 5)), WeatherType.clearNight);
    });

    test('as bordas: nascer já é dia, pôr já é noite', () {
      final tempo = comSol(WeatherType.clear);
      expect(tempo.at(DateTime(2026, 8, 24, 6)), WeatherType.clear);
      expect(tempo.at(DateTime(2026, 8, 24, 5, 59)), WeatherType.clearNight);
      expect(tempo.at(DateTime(2026, 8, 24, 18)), WeatherType.clearNight);
      expect(tempo.at(DateTime(2026, 8, 24, 17, 59)), WeatherType.clear);
    });

    test('quem não tem versão noturna atravessa inteiro', () {
      for (final type in [
        WeatherType.rain,
        WeatherType.thunderstorm,
        WeatherType.tornado,
      ]) {
        final tempo = comSol(type);
        expect(tempo.at(DateTime(2026, 8, 24, 20)), type, reason: type.name);
        expect(tempo.at(DateTime(2026, 8, 24, 8)), type, reason: type.name);
      }
    });

    test('sem os horários do sol, fica o dia', () {
      // Não dá para afirmar nada sobre outro instante: o sufixo do `icon`
      // descreve a hora da consulta, e é justamente promover por ele um
      // horário que não é aquele que dá errado.
      const semSol = CurrentWeather(type: WeatherType.clearNight);
      expect(semSol.at(DateTime(2026, 8, 24, 20)), WeatherType.clear);
      expect(semSol.at(DateTime(2026, 8, 24, 8)), WeatherType.clear);
    });
  });

  group('nascer e pôr do sol saem de sys', () {
    test('a resposta real traz os dois', () {
      const corpo =
          '{"weather":[{"main":"Clear","icon":"01d"}],'
          '"sys":{"sunrise":1787475600,"sunset":1787518800}}';

      final tempo = parseCurrentWeather(corpo)!;
      // Comparado com a mesma conversão: o valor em minutos depende do fuso do
      // aparelho, e é local de propósito — as coordenadas são fixas em
      // Fortaleza e o `startAt` da rota também é local.
      final nascer = DateTime.fromMillisecondsSinceEpoch(1787475600 * 1000);
      expect(tempo.sunrise, nascer.hour * 60 + nascer.minute);
      expect(tempo.sunset, isNotNull);
    });

    test('resposta sem sys não inventa horário', () {
      final tempo = parseCurrentWeather('{"weather":[{"main":"Clear"}]}')!;
      expect(tempo.sunrise, isNull);
      expect(tempo.sunset, isNull);
    });

    test('sys com tipo inesperado não derruba o parse', () {
      final tempo = parseCurrentWeather(
        '{"weather":[{"main":"Clear"}],"sys":{"sunrise":"cedo"}}',
      )!;
      expect(tempo.type, WeatherType.clear);
      expect(tempo.sunrise, isNull);
    });
  });
}
