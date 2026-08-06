import 'package:flutter/material.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/widget/vehicleThumb.dart';

/// O botão de veículos da `AppBar`: um carro genérico enquanto não há nenhum
/// cadastrado, a imagem do veículo em uso quando há.
///
/// Recebe [activeVehicleId] em vez de ler o perfil por dentro porque a `AppBar`
/// já mantém um `StreamBuilder` sobre `user/{uid}` para o nome e o apelido —
/// abrir um segundo seria escutar o mesmo documento duas vezes.
class VehicleAvatar extends StatefulWidget {
  const VehicleAvatar({
    super.key,
    required this.uid,
    required this.activeVehicleId,
    required this.onTap,
  });

  final String uid;

  /// De `user/{uid}.activeVehicleId`, entregue por quem monta a `AppBar`.
  final String? activeVehicleId;

  final VoidCallback onTap;

  @override
  State<VehicleAvatar> createState() => _VehicleAvatarState();
}

class _VehicleAvatarState extends State<VehicleAvatar> {
  /// Criado uma única vez: montar o stream dentro do build reinscreveria no
  /// Firestore a cada rebuild.
  ///
  /// É um listener permanente, mas sobre dois ou três documentos, e é o que faz
  /// o ícone trocar sozinho quando o veículo em uso muda na outra tela.
  late final Stream<List<Vehicle>> _vehicles = VehicleController.watchAll(
    widget.uid,
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Vehicle>>(
      stream: _vehicles,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Erro ao ler os veículos: ${snapshot.error}');
        }

        // Mesma resolução da tela de veículos e do cálculo da provisão.
        final active = VehicleController.activeFrom(
          snapshot.data ?? const <Vehicle>[],
          widget.activeVehicleId,
        );

        return IconButton(
          key: const Key('appbar-vehicle'),
          tooltip: active == null
              ? 'Cadastrar veículo'
              : 'Veículos · ${active.displayName}',
          onPressed: widget.onTap,
          icon: active == null
              ? const Icon(Icons.directions_car_outlined)
              : VehicleThumb(vehicle: active, size: 30, circle: true),
        );
      },
    );
  }
}
