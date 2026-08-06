import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/services/firebase.dart';
import 'package:uuid/uuid.dart';

/// A coleção **global** `gastop`: o preço que cada posto estava cobrando.
///
/// É a única coleção do app que não é de um usuário só. Existe para, um dia,
/// indicar preços por perto — e por isso guarda tanto o preço atual, para
/// leitura rápida, quanto o histórico de relatos, que é o que permitirá ler a
/// **mediana** em vez do último valor quando houver muita gente escrevendo.
///
/// Risco assumido e registrado em `docs/specs/abastecimento.md`: qualquer
/// usuário autenticado pode relatar qualquer preço. Com um usuário é teórico;
/// a defesa, quando a hora chegar, é a mediana — não uma regra mais apertada.
class StationController {
  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirestoreService.instance.collection('gastop');

  /// Se este abastecimento pode alimentar a coleção global.
  ///
  /// Duas condições, e as duas são sobre **não sujar o dado compartilhado**:
  ///
  /// - **Posto vindo da fonte.** Nome digitado à mão não tem id do OSM, e
  ///   "Posto do Zé" viraria dez documentos que ninguém consegue reconciliar.
  /// - **Preço calculável.** Sem litros não há preço do litro, e não há o que
  ///   relatar.
  static bool canReport(Supply supply) {
    final station = supply.station;
    if (station == null || station.id.isEmpty) return false;

    final price = supply.pricePerLiter;
    return price != null && price > 0;
  }

  /// Grava o posto e o relato, numa escrita só.
  ///
  /// `WriteBatch` porque as duas coisas contam a mesma história: um preço atual
  /// sem o relato que o originou é um número sem procedência.
  ///
  /// Não faz nada quando [canReport] é falso — a guarda fica aqui, e não no
  /// formulário, para que qualquer caminho futuro que grave abastecimento
  /// herde a mesma regra.
  static Future<void> report(Supply supply, String uid) async {
    if (!canReport(supply)) return;

    final station = supply.station!;
    final price = supply.pricePerLiter!;
    final now = DateTime.now().toIso8601String();

    final stationDoc = _collection.doc(station.id);
    final batch = FirestoreService.instance.batch();

    batch.set(stationDoc, {
      'id': station.id,
      'name': station.name,
      'brand': station.brand,
      'lat': station.lat,
      'lng': station.lng,
      // Preço **por combustível**: um posto tem quatro bombas com quatro
      // preços, e um campo único faria o diesel apagar a gasolina. Com
      // `merge: true` o Firestore funde o mapa aninhado em vez de trocá-lo,
      // então relatar etanol não derruba o preço da gasolina de ontem.
      'prices': {supply.fuel.name: price},
      'updatedAt': now,
      // A regra de segurança exige que este campo seja o próprio autor.
      'updatedBy': uid,
    }, SetOptions(merge: true));

    // Relato imutável: as regras liberam `create` e negam `update` e `delete`.
    // Histórico que pode ser reescrito não é histórico — a mesma razão de a
    // provisão da rota ser um valor congelado.
    batch.set(stationDoc.collection('precos').doc(const Uuid().v4()), {
      'price': price,
      'fuel': supply.fuel.name,
      'uid': uid,
      'at': now,
    });

    try {
      await batch.commit();
    } catch (e) {
      // Falhar aqui não pode derrubar o registro do abastecimento: o gasto é
      // dele, a coleção global é conveniência para os outros.
      debugPrint('gastop: não foi possível relatar o preço: $e');
    }
  }
}
