import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/Utils/dated.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/services/firebase.dart';

/// Manutenções do usuário em `iter/{uid}/maintenance` — subcoleção irmã de
/// `routes`, `vehicles` e `supply`.
///
/// Sem coleção global, ao contrário do abastecimento: oficina é texto livre e
/// nada sai do documento do usuário. Parceria com oficina é ideia de futuro.
class MaintenanceController {
  static CollectionReference<Map<String, dynamic>> collectionOf(String uid) =>
      FirestoreService.instance
          .collection('iter')
          .doc(uid)
          .collection('maintenance');

  /// Acompanha as manutenções, da mais recente para a mais antiga.
  static Stream<List<Maintenance>> watchAll(String uid) {
    return collectionOf(uid).snapshots().map(_parseAll);
  }

  /// Leitura única, para quando não faz sentido manter o listener aberto.
  static Future<List<Maintenance>> fetchAll(String uid) async {
    return _parseAll(await collectionOf(uid).get());
  }

  /// Cria ou substitui. Mesmo `id` = edição, `id` novo = cadastro.
  static Future<void> save(String uid, Maintenance maintenance) {
    return collectionOf(uid).doc(maintenance.id).set(maintenance.toMap());
  }

  static Future<void> delete(String uid, String maintenanceId) {
    return collectionOf(uid).doc(maintenanceId).delete();
  }

  static List<Maintenance> _parseAll(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final maintenances = <Maintenance>[];

    for (final doc in snapshot.docs) {
      try {
        maintenances.add(Maintenance.fromMap(doc.data()));
      } catch (e) {
        // Um documento fora do formato não pode derrubar a lista inteira.
        debugPrint('Manutenção ${doc.id} ignorada: $e');
      }
    }

    return sortByDateDesc(maintenances);
  }
}
