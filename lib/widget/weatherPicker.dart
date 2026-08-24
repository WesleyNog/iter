import 'package:flutter/material.dart';
import 'package:iter/Utils/weather.dart';
import 'package:iter/services/openWeather.dart';

/// O que o usuário escolheu no [showWeatherPicker].
///
/// Existe porque `null` sozinho seria ambíguo: o `Future` devolve `null` quando
/// o usuário fecha sem escolher, e este objeto com [value] nulo quando ele
/// escolhe "Sem informar" — duas intenções bem diferentes.
class WeatherChoice {
  final WeatherType? value;
  const WeatherChoice(this.value);
}

/// Os tempos que dá para escolher à mão — um por ícone desenhado em
/// `assets/images/`.
///
/// As diurnas vêm na ordem do céu mais limpo para o mais fechado; as duas
/// noturnas ficam no fim, e não coladas nas suas versões de dia, para não
/// empurrar as sete de cima de posição.
///
/// Não é a lista inteira do enum de propósito: `mist`, `haze`, `dust` e
/// companhia vêm da API e reaproveitam ícones, então apareceriam aqui como
/// opções repetidas, sem o usuário saber qual escolher.
const List<WeatherType> selectableWeather = [
  WeatherType.clear,
  WeatherType.fewClouds,
  WeatherType.clouds,
  WeatherType.rain,
  WeatherType.heavyRain,
  WeatherType.thunderstorm,
  WeatherType.tornado,
  // As duas noturnas vão no fim, e não junto das suas versões diurnas, para
  // não empurrar as sete de cima de posição: "Nublado" é a terceira célula há
  // meses, e quem cadastra rota todo dia acerta nela sem ler o rótulo.
  WeatherType.clearNight,
  WeatherType.cloudsNight,
];

/// Abre o seletor de tempo. `null` = fechou sem escolher.
Future<WeatherChoice?> showWeatherPicker(
  BuildContext context, {
  WeatherType? selected,
}) {
  return showModalBottomSheet<WeatherChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => WeatherPicker(selected: selected),
  );
}

class WeatherPicker extends StatelessWidget {
  const WeatherPicker({super.key, this.selected});

  final WeatherType? selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        // Rolável: são nove opções, que fecham em três linhas num iPhone e em
        // mais num aparelho estreito. Com a fonte do sistema ampliada — ou num
        // aparelho baixo — elas não cabem na altura que o bottom sheet recebe.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Como estava o tempo?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[850],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A busca automática só sabe o tempo de agora.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final type in selectableWeather) _option(context, type),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const WeatherChoice(null)),
                child: Text(
                  'Sem informar',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(BuildContext context, WeatherType type) {
    final isSelected = type == selected;

    return SizedBox(
      width: 92,
      child: Material(
        color: isSelected ? Colors.blue.shade50 : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.pop(context, WeatherChoice(type)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Colors.blue.shade300 : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 40, child: Image.asset(getWeatherIcon(type))),
                const SizedBox(height: 6),
                Text(
                  weatherLabel(type),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.blue.shade700 : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
