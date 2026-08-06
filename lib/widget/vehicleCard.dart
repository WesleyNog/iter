import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/vehicleCost.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/widget/vehicleThumb.dart';

/// Um veículo na lista: imagem, nome, ficha e quanto ele custa por quilômetro.
///
/// A taxa aparece aqui e não só no formulário porque é o número que decide o
/// lucro de cada rota — quem troca de veículo precisa ver o que está trocando.
class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.vehicle,
    this.isActive = false,
    this.onTap,
  });

  final Vehicle vehicle;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rate = totalRatePerKm(vehicle);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          // A borda azul é o que diferencia o ativo de longe, sem depender de
          // ler o selo.
          color: isActive ? Colors.blue : Colors.grey.shade300,
          width: isActive ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              VehicleThumb(vehicle: vehicle),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vehicle.displayName,
                            key: const Key('vehicle-card-name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isActive) const _ActiveBadge(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicle.subtitle,
                      key: const Key('vehicle-card-subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // `—` quando falta o consumo: dizer "R$ 0,1193" seria
                      // anunciar um sétimo do custo real do carro.
                      rate == null ? '—' : '${formatRate(rate)} /km',
                      key: const Key('vehicle-card-rate'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: rate == null
                            ? Colors.grey
                            : Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('vehicle-card-active'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'EM USO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.blue.shade700,
        ),
      ),
    );
  }
}
