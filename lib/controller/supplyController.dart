import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/Utils/dated.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/services/firebase.dart';

/// Abastecimentos do usuário em `iter/{uid}/supply` — subcoleção irmã de
/// `routes` e `vehicles`.
class SupplyController {
  static CollectionReference<Map<String, dynamic>> collectionOf(String uid) =>
      FirestoreService.instance.collection('iter').doc(uid).collection('supply');

  /// Acompanha os abastecimentos, do mais recente para o mais antigo.
  static Stream<List<Supply>> watchAll(String uid) {
    return collectionOf(uid).snapshots().map(_parseAll);
  }

  /// Leitura única, para quando não faz sentido manter o listener aberto.
  static Future<List<Supply>> fetchAll(String uid) async {
    return _parseAll(await collectionOf(uid).get());
  }

  /// Cria ou substitui. Mesmo `id` = edição, `id` novo = cadastro.
  static Future<void> save(String uid, Supply supply) {
    return collectionOf(uid).doc(supply.id).set(supply.toMap());
  }

  static Future<void> delete(String uid, String supplyId) {
    return collectionOf(uid).doc(supplyId).delete();
  }

  static List<Supply> _parseAll(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final supplies = <Supply>[];

    for (final doc in snapshot.docs) {
      try {
        supplies.add(Supply.fromMap(doc.data()));
      } catch (e) {
        // Um documento fora do formato não pode derrubar a lista inteira.
        debugPrint('Abastecimento ${doc.id} ignorado: $e');
      }
    }

    return sortByDate(supplies);
  }

  /// Do mais recente para o mais antigo.
  ///
  /// A ordenação em si mora em `Utils/dated.dart`, compartilhada com as
  /// manutenções: abastecimento e manutenção são coisas diferentes que o extrato
  /// trata igual, e duas cópias da mesma ordenação uma hora divergiriam.
  static List<Supply> sortByDate(List<Supply> supplies) =>
      sortByDateDesc(supplies);
}
