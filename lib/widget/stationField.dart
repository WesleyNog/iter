import 'package:flutter/material.dart';
import 'package:iter/Utils/stationFlag.dart';
import 'package:iter/screens/stationsScreen.dart';
import 'package:iter/widget/stationCard.dart';

/// O bloco "Posto" do formulário de abastecimento: um campo, não uma lista.
///
/// A lista mora em "Postos da região". Dentro do formulário, 60 cards com
/// preços dariam milhares de pixels de rolagem até o botão de salvar.
///
/// Nada vem escolhido sozinho: em casa, o posto mais próximo é justamente o
/// errado, e seria salvo calado.
class StationField extends StatelessWidget {
  const StationField({super.key, required this.choice, required this.onTap});

  final StationChoice? choice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final station = choice?.station;
    final typed = choice?.typedName;
    final chevron = Icon(Icons.chevron_right, color: Colors.grey.shade500);

    if (station != null) {
      // O card da lista, sem distância — depois de escolhido, "2,8 km" de
      // onde? — e sem preços.
      return StationCard(
        key: const Key('station-field'),
        station: station,
        trailing: chevron,
        onTap: onTap,
      );
    }

    return Material(
      key: const Key('station-field'),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const StationLogo(flag: StationFlag.semBandeira),
              const SizedBox(width: 12),
              Expanded(
                child: typed == null
                    ? const Text(
                        'Escolher posto',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Outro / não listado',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            typed,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
              chevron,
            ],
          ),
        ),
      ),
    );
  }
}
