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
  heavyRain,

  /// Céu limpo e nublado **de noite**.
  ///
  /// Também não saem do `main`, que não distingue dia de noite: quem distingue
  /// é o sufixo do `weather[0].icon` (`01d` / `01n`), calculado pela própria
  /// OpenWeather a partir do nascer e do pôr do sol daquele ponto. Decidir isso
  /// aqui por uma hora de corte seria errar duas vezes por ano, quando o dia
  /// encolhe — e errar sempre para quem rodar fora de Fortaleza.
  ///
  /// Existem porque a Amazon tem muita rota depois das 19h e o app não tinha
  /// como registrar isso: a única escolha honesta num céu limpo à noite era
  /// "Nublado", que é o oposto do que o céu estava.
  ///
  /// **Só estes dois.** Chuva à noite continua sendo `rain`: não há ícone de
  /// chuva noturna, e inventar um tipo sem desenho quebraria o `Image.asset`.
  clearNight,
  cloudsNight;

  static WeatherType fromString(String value) =>
      tryFromString(value) ?? WeatherType.clear;

  /// O tipo, ou `null` quando [value] não é nenhum deles.
  ///
  /// Separado de [fromString] porque os dois chamadores querem coisas
  /// diferentes do desconhecido. A leitura de um documento quer um tipo
  /// qualquer para desenhar, e o sol serve. Já o parse da resposta da API
  /// precisa saber que **não reconheceu**: sem isso, um `main` novo somado a um
  /// `icon` noturno viraria "Noite limpa" — uma afirmação específica sobre um
  /// céu que a API nunca reportou, no arquivo cuja regra é justamente não
  /// afirmar na dúvida.
  static WeatherType? tryFromString(String value) {
    final wanted = value.toLowerCase();
    for (final type in WeatherType.values) {
      // `toLowerCase()` dos **dois** lados: sem isso um valor camelCase como
      // `fewClouds` nunca voltaria da leitura — viraria sol silenciosamente.
      if (type.name.toLowerCase() == wanted) return type;
    }
    return null;
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
Future<CurrentWeather?> getWeather(double lat, double lon) async {
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
CurrentWeather? parseCurrentWeather(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final weather = decoded['weather'];
    if (weather is! List || weather.isEmpty) return null;

    final first = weather.first;
    if (first is! Map) return null;

    final main = first['main'];
    if (main is! String) return null;

    final type = WeatherType.tryFromString(main);
    // `main` que o app não conhece continua caindo no sol, como sempre caiu —
    // mas **não** passa pela versão noturna: promover um palpite a "Noite
    // limpa" seria inventar o céu junto com a hora.
    final sky = type == null
        ? WeatherType.clear
        : _atNight(type, first['icon']);

    final sys = decoded['sys'];
    return CurrentWeather(
      type: sky,
      sunrise: sys is Map ? _minutesOfDay(sys['sunrise']) : null,
      sunset: sys is Map ? _minutesOfDay(sys['sunset']) : null,
    );
  } catch (e) {
    debugPrint('OpenWeather: resposta ilegível: $e');
    return null;
  }
}

/// O tempo de agora, mais o que é preciso para responder sobre **outro**
/// horário do mesmo dia.
///
/// Os dois nascem juntos porque a busca roda ao abrir o cadastro, quando a rota
/// ainda não tem hora: o usuário escolhe data e horário depois. Sem o par de
/// nascer e pôr do sol, a única coisa que a resposta sabe dizer é sobre o
/// instante da consulta — e foi assim que uma rota das 08h às 14h, cadastrada
/// às 21h, ganhou um ícone de lua ao lado do próprio horário que o desmentia.
class CurrentWeather {
  const CurrentWeather({required this.type, this.sunrise, this.sunset});

  /// O céu no instante da consulta, já noturno se era de noite.
  final WeatherType type;

  /// Nascer e pôr do sol daquele ponto, em **minutos desde a meia-noite
  /// local**. `null` quando a resposta não trouxe.
  ///
  /// Em minutos do dia, e não como instante: a rota pode ser de ontem ou de
  /// amanhã, e o que interessa é a que horas o sol nasce ali — que muda meia
  /// hora ao longo do ano em Fortaleza, contra as horas que um corte fixo
  /// erraria.
  final int? sunrise;
  final int? sunset;

  /// O mesmo céu, ajustado para [moment].
  ///
  /// Sem o par de horários não dá para afirmar nada sobre outro instante — o
  /// sufixo do `icon` descreve a hora da consulta, e promover por ele um
  /// horário que não é aquele é exatamente o erro. Aí fica o dia, que é a
  /// versão que não inventa.
  WeatherType at(DateTime moment) {
    final base = daytimeOf(type);
    final rise = sunrise;
    final set = sunset;
    if (rise == null || set == null) return base;

    final minutes = moment.hour * 60 + moment.minute;
    final isNight = minutes < rise || minutes >= set;
    return isNight ? (nightVariantOf(base) ?? base) : base;
  }
}

/// O horário de um `unix timestamp` da OpenWeather, em minutos do dia.
///
/// `fromMillisecondsSinceEpoch` devolve hora **local do aparelho**, que é o que
/// se quer: as coordenadas são fixas em Fortaleza e o entregador está lá. Num
/// fuso diferente do das coordenadas isto erraria — e erraria junto com o resto
/// do app, que já compara `startAt` local com tudo.
int? _minutesOfDay(Object? unixSeconds) {
  if (unixSeconds is! int) return null;
  final moment = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return moment.hour * 60 + moment.minute;
}

/// O mesmo tempo, na versão noturna, quando [icon] diz que é de noite.
///
/// `weather[0].icon` é `01d` de dia e `01n` de noite — o único campo desta
/// resposta que separa os dois, e a OpenWeather o calcula do nascer e do pôr do
/// sol das coordenadas pedidas. Ler o sufixo sai de graça e não depende de
/// fuso, de estação nem de onde o entregador está.
///
/// Um `icon` ausente ou estranho **não** vira noite: o tempo do dia é a
/// resposta mais provável e a única que não inventa informação. É a mesma
/// escolha do resto do arquivo — na dúvida, não afirme.
WeatherType _atNight(WeatherType type, Object? icon) {
  if (icon is! String || !icon.endsWith('n')) return type;
  return nightVariantOf(type) ?? type;
}

/// Os pares dia → noite, e a **única** lista deles.
///
/// Só estes dois têm desenho noturno. Os demais não entram de propósito: chuva
/// à noite é chuva, e criar um tipo sem ícone estouraria o `Image.asset` na
/// lista de rotas.
const Map<WeatherType, WeatherType> _nightVariants = {
  WeatherType.clear: WeatherType.clearNight,
  WeatherType.clouds: WeatherType.cloudsNight,
};

/// O mesmo mapa ao contrário, **derivado** e não escrito de novo: um par que
/// existisse só de um lado é exatamente o bug que promoveria um céu na ida e
/// não o desfaria na volta.
final Map<WeatherType, WeatherType> _daytimeVariants = {
  for (final entry in _nightVariants.entries) entry.value: entry.key,
};

/// A versão noturna de [type], ou `null` quando ele não tem uma.
WeatherType? nightVariantOf(WeatherType type) => _nightVariants[type];

/// A versão diurna de [type] — o mesmo céu, sem a hora.
///
/// Existe para os gráficos: "Nublado" e "Noite nublada" são a mesma condição
/// física, e mantê-los separados no ranking de insucesso partiria uma
/// população em dois degraus menores só porque metade dela foi cadastrada
/// antes de o app saber distinguir noite. Com `maxBars: 4` no gráfico e só o
/// primeiro colocado no card de índice, o clima que de fato lidera podia sumir
/// da tela por causa dessa divisão.
///
/// O card da rota continua desenhando a lua: lá a hora é informação, aqui é
/// ruído.
WeatherType daytimeOf(WeatherType type) => _daytimeVariants[type] ?? type;
