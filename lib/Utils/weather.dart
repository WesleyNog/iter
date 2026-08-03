import 'package:flutter/material.dart';
import 'package:iter/services/openWeather.dart';

/// Nome do tempo em pt-BR, para rótulo e leitor de tela.
String weatherLabel(WeatherType type) {
  switch (type) {
    case WeatherType.clear:
      return 'Sol';
    case WeatherType.fewClouds:
      return 'Poucas nuvens';
    case WeatherType.clouds:
      return 'Nublado';
    case WeatherType.rain:
      return 'Chuva';
    case WeatherType.heavyRain:
      return 'Chuva forte';
    case WeatherType.drizzle:
      return 'Garoa';
    case WeatherType.thunderstorm:
      return 'Trovoada';
    case WeatherType.snow:
      return 'Neve';
    case WeatherType.mist:
    case WeatherType.fog:
      return 'Neblina';
    case WeatherType.haze:
    case WeatherType.smoke:
      return 'Céu encoberto';
    case WeatherType.dust:
    case WeatherType.sand:
      return 'Poeira';
    case WeatherType.ash:
      return 'Cinzas';
    case WeatherType.squall:
      return 'Rajada';
    case WeatherType.tornado:
      return 'Vento forte';
  }
}

/// Ícone do tempo, aceitando o "não sei" que [getWeather] passou a devolver.
///
/// `null` desenha um ícone neutro em vez do sol: era justamente a confusão entre
/// "falhou" e "céu limpo" que escondia o clima quebrado.
Widget weatherImage(WeatherType? weatherType) {
  if (weatherType == null) {
    return Icon(Icons.cloud_off_outlined, color: Colors.grey.shade400);
  }

  return Image.asset(getWeatherIcon(weatherType));
}

String getWeatherIcon(WeatherType weatherType) {
  String iconPath;

  switch (weatherType) {
    case WeatherType.clear:
      iconPath = 'assets/images/SOL.png';
      break;
    case WeatherType.clouds:
      iconPath = 'assets/images/NUBLADO.png';
      break;
    case WeatherType.rain:
      iconPath = 'assets/images/CHOVENDO.png';
      break;
    case WeatherType.snow:
      // Não existe NEVANDO.png em assets/images — apontar para ele estouraria
      // o Image.asset. Nublado é o menos errado até alguém desenhar o ícone
      // (e neve em Fortaleza não é o caso mais urgente).
      iconPath = 'assets/images/NUBLADO.png';
      break;
    case WeatherType.fewClouds:
      iconPath = 'assets/images/POUCAS-NUVENS.png';
      break;
    case WeatherType.heavyRain:
      iconPath = 'assets/images/CHUVA-FORTE.png';
      break;
    case WeatherType.thunderstorm:
      iconPath = 'assets/images/TROVEJANDO.png';
      break;
    case WeatherType.drizzle:
      iconPath = 'assets/images/CHOVENDO.png';
      break;
    case WeatherType.mist:
      iconPath = 'assets/images/NUBLADO.png';
      break;
    case WeatherType.smoke:
      iconPath = 'assets/images/POUCAS-NUVENS.png';
      break;
    case WeatherType.haze:
      iconPath = 'assets/images/POUCAS-NUVENS.png';
      break;
    case WeatherType.dust:
      iconPath = 'assets/images/POUCAS-NUVENS.png';
      break;
    case WeatherType.fog:
      iconPath = 'assets/images/NUBLADO.png';
      break;
    case WeatherType.sand:
      iconPath = 'assets/images/POUCAS-NUVENS.png';
      break;
    case WeatherType.ash:
      iconPath = 'assets/images/POUCAS-NUVENS.png';
      break;
    case WeatherType.squall:
      iconPath = 'assets/images/SOL.png';
      break;
    case WeatherType.tornado:
      iconPath = 'assets/images/VENTO-FORTE.png';
      break;
  }

  return iconPath;
}
