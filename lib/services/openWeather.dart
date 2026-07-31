import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  tornado;

  static WeatherType fromString(String value) {
    return WeatherType.values.firstWhere(
      (type) => type.name == value.toLowerCase(),
      orElse: () =>
          WeatherType.clear, // Valor padrão caso venha um tipo desconhecido
    );
  }
}

String _URL = 'https://api.openweathermap.org/data/4.0/onecall/';
String _hystoryURL = 'https://history.openweathermap.org/data/2.5/history/city';

Future<WeatherType> getWeather(double lat, double lon) async {
  final apiKey = '0a79844a8ddfc1a2ff862effb2962460';
  final url = Uri.parse('$_URL?lat=$lat&lon=$lon&appid=$apiKey');
  final response = await http.get(url);

  if (response.statusCode == 200) {
    final Map<String, dynamic> data = jsonDecode(response.body);

    if (data['data'] != null && (data['data'] as List).isNotEmpty) {
      final firstData = data['data'][0];

      if (firstData['weather'] != null &&
          (firstData['weather'] as List).isNotEmpty) {
        final String mainString = firstData['weather'][0]['main'];

        print(
          'Weather main string: $mainString',
        ); // Adicione esta linha para depuração
        return WeatherType.fromString(mainString);
      }
    }
  }
  return WeatherType.clear;
}

Future<WeatherType> getWeatherHistory(
  double lat,
  double lon,
  int start,
  int end,
) async {
  final apiKey = '0a79844a8ddfc1a2ff862effb2962460';
  final url = Uri.parse(
    '$_hystoryURL?lat=$lat&lon=$lon&type=hour&start=$start&end=$end&appid=$apiKey',
  );
  final response = await http.get(url);

  if (response.statusCode == 200) {
    final Map<String, dynamic> data = jsonDecode(response.body);

    if (data['data'] != null && (data['data'] as List).isNotEmpty) {
      final firstData = data['data'][0];

      if (firstData['weather'] != null &&
          (firstData['weather'] as List).isNotEmpty) {
        final String mainString = firstData['weather'][0]['main'];

        print(
          'Weather history main string: $mainString',
        ); // Adicione esta linha para depuração
        return WeatherType.fromString(mainString);
      }
    }
  }
  return WeatherType.clear;
}
