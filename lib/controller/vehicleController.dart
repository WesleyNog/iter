import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/controller/userController.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/services/firebase.dart';

/// O que uma tela de gasto precisa saber sobre os veículos: todos, para o
/// seletor, e qual está em uso, para o padrão.
///
/// Mora aqui e não numa tela porque as duas — abastecimento e manutenção —
/// precisam do mesmo par, e uma importar a outra seria acoplamento entre telas.
typedef VehiclesSnapshot = ({List<Vehicle> all, Vehicle? active});

/// Veículos do usuário em `iter/{uid}/vehicles` — subcoleção irmã de `routes`.
///
/// Qual deles está em uso mora em `user/{uid}.activeVehicleId`, não aqui: ver
/// [Users.activeVehicleId] para o porquê.
class VehicleController {
  static CollectionReference<Map<String, dynamic>> collectionOf(String uid) =>
      FirestoreService.instance
          .collection('iter')
          .doc(uid)
          .collection('vehicles');

  /// Acompanha os veículos em tempo real, do mais antigo para o mais novo.
  static Stream<List<Vehicle>> watchAll(String uid) {
    return collectionOf(uid).snapshots().map(_parseAll);
  }

  /// Leitura única, para quando não faz sentido manter o listener aberto —
  /// é o caso de gravar a provisão ao salvar uma rota.
  static Future<List<Vehicle>> fetchAll(String uid) async {
    return _parseAll(await collectionOf(uid).get());
  }

  /// O veículo em uso, ou `null` quando o usuário não tem nenhum.
  ///
  /// Uma leitura só: a lista inteira já vem do cache que a tela de veículos
  /// preencheu, e são dois ou três documentos.
  static Future<Vehicle?> fetchActive(String uid) async {
    final user = await UserController.fetch(uid);
    return activeFrom(await fetchAll(uid), user?.activeVehicleId);
  }

  /// Cria ou substitui. Mesmo `id` = edição, `id` novo = cadastro.
  static Future<void> save(String uid, Vehicle vehicle) {
    return collectionOf(uid).doc(vehicle.id).set(vehicle.toMap());
  }

  /// Exclui e, se era o veículo em uso, promove outro.
  ///
  /// Apaga **antes** de reapontar: se o app morrer no meio, sobra um
  /// `activeVehicleId` apontando para documento inexistente, e [activeFrom] já
  /// sabe cair no primeiro da lista. A ordem inversa deixaria o usuário sem
  /// veículo ativo tendo veículos.
  ///
  /// As rotas que já usaram este veículo **mantêm** a provisão gravada: ela é
  /// um valor em reais, não um ponteiro para cá.
  static Future<void> delete(String uid, String vehicleId) async {
    await collectionOf(uid).doc(vehicleId).delete();

    final user = await UserController.fetch(uid);
    if (user?.activeVehicleId != vehicleId) return;

    final remaining = await fetchAll(uid);
    await setActive(uid, remaining.isEmpty ? null : remaining.first.id);
  }

  static Future<void> setActive(String uid, String? vehicleId) {
    return UserController.update(uid, {'activeVehicleId': vehicleId});
  }

  /// Garante que o usuário tenha um veículo em uso, se tiver algum cadastrado.
  ///
  /// Chamado depois de salvar: o primeiro veículo cadastrado vira o ativo
  /// sozinho, porque exigir um segundo toque para usar o único carro que existe
  /// seria cerimônia. Também conserta um `activeVehicleId` órfão.
  static Future<void> ensureActive(String uid) async {
    final vehicles = await fetchAll(uid);
    if (vehicles.isEmpty) return;

    final user = await UserController.fetch(uid);
    final stored = user?.activeVehicleId;
    if (stored != null && vehicles.any((v) => v.id == stored)) return;

    await setActive(uid, vehicles.first.id);
  }

  /// Resolve qual veículo está em uso.
  ///
  /// **É a única resolução do app** — a tela e o cálculo da provisão chamam
  /// esta função, e é isso que garante que o carro desenhado na AppBar seja o
  /// mesmo carro cujo custo entra na conta.
  ///
  /// Um [activeId] que não existe mais (veículo excluído com o app offline)
  /// cai no primeiro da lista em vez de devolver `null`: o usuário tem carro,
  /// e mostrar "nenhum veículo" seria mentira.
  static Vehicle? activeFrom(List<Vehicle> vehicles, String? activeId) {
    if (vehicles.isEmpty) return null;

    for (final vehicle in vehicles) {
      if (vehicle.id == activeId) return vehicle;
    }

    return vehicles.first;
  }

  static List<Vehicle> _parseAll(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final vehicles = <Vehicle>[];

    for (final doc in snapshot.docs) {
      try {
        vehicles.add(Vehicle.fromMap(doc.data()));
      } catch (e) {
        // Um documento fora do formato não pode derrubar a lista inteira.
        debugPrint('Veículo ${doc.id} ignorado: $e');
      }
    }

    return sortByCreation(vehicles);
  }

  /// Do mais antigo para o mais novo.
  ///
  /// Ordem estável importa: [activeFrom] cai em `first` quando o ativo sumiu, e
  /// uma ordem que dançasse entre rebuilds trocaria o carro sozinho.
  static List<Vehicle> sortByCreation(List<Vehicle> vehicles) {
    final sorted = [...vehicles];
    sorted.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      // `createdAt` igual (ou vazio, em documento antigo): o id desempata para
      // a ordem nunca depender de como o Firestore devolveu.
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return sorted;
  }
}
