import 'package:flutter/material.dart';
import 'package:iter/services/openWeather.dart';

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
      iconPath = 'assets/images/NEVANDO.png';
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
