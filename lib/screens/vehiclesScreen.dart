import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iter/controller/userController.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/users.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/screens/addVehicle.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/vehicleCard.dart';

/// Os veículos do entregador, e qual deles está em uso.
///
/// O veículo em uso é o que entra na conta da provisão de toda rota concluída,
/// então trocar aqui muda o custo das rotas **daqui para a frente** — as já
/// concluídas guardam o valor em reais e não se mexem.
class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key, required this.uid});

  final String uid;

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  /// Criados uma vez: montar o stream dentro do build reinscreveria no
  /// Firestore a cada rebuild.
  late final Stream<List<Vehicle>> _vehicles = VehicleController.watchAll(
    widget.uid,
  );
  late final Stream<Users?> _profile = UserController.watch(widget.uid);

  Future<void> _openForm([Vehicle? vehicle]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddVehicle(uid: widget.uid, vehicle: vehicle),
      ),
    );
  }

  Future<void> _setActive(Vehicle vehicle, String? currentActive) async {
    if (vehicle.id == currentActive) return; // já é o de uso

    try {
      await VehicleController.setActive(widget.uid, vehicle.id);
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'success',
        msg: 'Usando ${vehicle.displayName}.',
      );
    } catch (e) {
      debugPrint('Erro ao trocar o veículo em uso: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível trocar de veículo.',
      );
    }
  }

  Future<void> _confirmDelete(Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir veículo?'),
        content: Text(
          '${vehicle.displayName} será apagado. Não dá para desfazer.\n\n'
          // Vale dizer: o medo natural é "vou perder o lucro que já calculei".
          'As rotas já concluídas mantêm a provisão que foi calculada com ele.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Excluir',
              style: TextStyle(color: Colors.red.shade600),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // O controller promove outro veículo se este era o em uso.
      await VehicleController.delete(widget.uid, vehicle.id);
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'success',
        msg: 'Veículo excluído.',
      );
    } catch (e) {
      debugPrint('Erro ao excluir o veículo: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: kDebugMode
            ? 'Falha ao excluir: $e'
            : 'Não foi possível excluir o veículo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meus veículos')),
      floatingActionButton: FloatingActionButton(
        key: const Key('vehicles-add'),
        onPressed: _openForm,
        tooltip: 'Cadastrar veículo',
        child: const Icon(Icons.add),
      ),
      // Um StreamBuilder para os dois: o card precisa saber qual é o em uso, e
      // o perfil é quem guarda isso.
      body: StreamBuilder<Users?>(
        stream: _profile,
        builder: (context, profileSnapshot) {
          if (profileSnapshot.hasError) {
            debugPrint('Erro ao ler o perfil: ${profileSnapshot.error}');
          }

          return _list(profileSnapshot.data?.activeVehicleId);
        },
      ),
    );
  }

  Widget _list(String? activeId) {
    return StreamBuilder<List<Vehicle>>(
      stream: _vehicles,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Erro ao ler os veículos: ${snapshot.error}');
          return _message(
            icon: Icons.error_outline,
            title: 'Não foi possível carregar seus veículos.',
            subtitle: kDebugMode ? '${snapshot.error}' : 'Tente novamente.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final vehicles = snapshot.data ?? const <Vehicle>[];
        if (vehicles.isEmpty) {
          return _message(
            icon: Icons.directions_car_outlined,
            title: 'Nenhum veículo cadastrado.',
            subtitle:
                'Cadastre o seu para o app calcular o custo e o lucro '
                'de cada rota.',
          );
        }

        // A mesma resolução que a AppBar e o cálculo da provisão usam: sem
        // isso, a tela poderia marcar um carro e a conta usar outro.
        final active = VehicleController.activeFrom(vehicles, activeId);

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          itemCount: vehicles.length,
          itemBuilder: (context, index) {
            final vehicle = vehicles[index];

            // O espaçamento fica fora do Slidable, senão as ações herdam a
            // altura do card + espaço e ficam maiores que ele.
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Slidable(
                key: ValueKey(vehicle.id),
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.45,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _openForm(vehicle),
                      icon: Icons.edit_outlined,
                      label: 'Editar',
                      backgroundColor: Colors.blue.shade400,
                      foregroundColor: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      padding: EdgeInsets.zero,
                    ),
                    SlidableAction(
                      onPressed: (_) => _confirmDelete(vehicle),
                      icon: Icons.delete_outline,
                      label: 'Excluir',
                      backgroundColor: Colors.red.shade400,
                      foregroundColor: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                child: VehicleCard(
                  vehicle: vehicle,
                  isActive: vehicle.id == active?.id,
                  onTap: () => _setActive(vehicle, active?.id),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
