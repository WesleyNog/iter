import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/model/stationPrices.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/services/firebase.dart';
import 'package:uuid/uuid.dart';

/// O limite do `whereIn` do Firestore.
const _whereInLimit = 30;

/// Os ids em blocos de no máximo 30, sem vazio e sem repetição.
///
/// Id vazio é posto digitado à mão, que nunca está em `gastop`; repetido
/// gastaria uma vaga do bloco à toa.
List<List<String>> idChunks(List<String> ids) {
  final unique = ids.where((id) => id.isNotEmpty).toSet().toList();

  return [
    for (var i = 0; i < unique.length; i += _whereInLimit)
      unique.sublist(i, (i + _whereInLimit).clamp(0, unique.length)),
  ];
}

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

  /// Os preços relatados destes postos, por id.
  ///
  /// Uma consulta por bloco de 30, e não uma leitura por posto: para os 60
  /// postos do Centro são duas consultas, cobradas pelos documentos que
  /// existem. Usa o `list` que as regras de `gastop` liberam — ver a dívida
  /// "`gastop` com `allow read`" em `docs/specs/postos-da-regiao.md`.
  ///
  /// Posto ausente do mapa é posto que ninguém relatou. `null` é **não deu
  /// para saber**, e a tela diz isso em vez de desenhar `—` em tudo.
  static Future<Map<String, StationPrices>?> pricesFor(List<String> ids) async {
    final chunks = idChunks(ids);
    if (chunks.isEmpty) return const {};

    try {
      final snapshots = await Future.wait([
        for (final chunk in chunks)
          _collection.where(FieldPath.documentId, whereIn: chunk).get(),
      ]);

      return {
        for (final snapshot in snapshots)
          for (final doc in snapshot.docs)
            doc.id: StationPrices.fromMap(doc.data()),
      };
    } catch (e) {
      debugPrint('gastop: não foi possível ler os preços: $e');
      return null;
    }
  }

  /// Se este abastecimento pode alimentar a coleção global.
  ///
  /// Três condições, e as três são sobre **não sujar o dado compartilhado**:
  ///
  /// - **Posto vindo da fonte.** Nome digitado à mão não tem id do OSM, e
  ///   "Posto do Zé" viraria dez documentos que ninguém consegue reconciliar.
  /// - **Preço calculável.** Sem litros não há preço do litro, e não há o que
  ///   relatar.
  /// - **Data legível.** A idade do preço sai da data do abastecimento; sem
  ///   ela, a tela mostraria uma idade inventada.
  static bool canReport(Supply supply) {
    final station = supply.station;
    if (station == null || station.id.isEmpty) return false;
    if (DateTime.tryParse(supply.date) == null) return false;

    final price = supply.pricePerLiter;
    return price != null && price > 0;
  }

  /// Se o abastecimento é de outro dia — e o relato tem de comparar antes de
  /// trocar o preço atual.
  ///
  /// Data ilegível conta como outro dia: é o caminho que compara.
  static bool reportsPastDay(Supply supply, {required DateTime now}) {
    final date = DateTime.tryParse(supply.date);
    if (date == null) return true;

    return date.year != now.year ||
        date.month != now.month ||
        date.day != now.day;
  }

  /// Se um relato feito em [reported] deve virar o preço atual, sobre um
  /// guardado em [stored].
  ///
  /// Sem preço guardado — ou guardado antes de `pricedAt` existir — troca.
  /// Mesmo instante não troca: não há o que ganhar reescrevendo.
  static bool shouldReplacePrice({
    required DateTime? stored,
    required DateTime reported,
  }) => stored == null || reported.isAfter(stored);

  /// O documento do posto em `gastop`.
  ///
  /// [withPrice] falso escreve só o posto: é o relato de outro dia que perdeu
  /// para um preço mais novo e vai apenas para o histórico.
  static Map<String, dynamic> stationFields(
    Supply supply,
    String uid, {
    required DateTime now,
    bool withPrice = true,
  }) {
    final station = supply.station!;

    return {
      'id': station.id,
      'name': station.name,
      'brand': station.brand,
      'lat': station.lat,
      'lng': station.lng,
      if (withPrice) ...{
        // Preço **por combustível**: um posto tem quatro bombas com quatro
        // preços, e um campo único faria o diesel apagar a gasolina. Com
        // `merge: true` o Firestore funde o mapa aninhado em vez de trocá-lo,
        // então relatar etanol não derruba o preço da gasolina de ontem.
        'prices': {supply.fuel.name: supply.pricePerLiter},
        // A idade de **cada** preço. `updatedAt` é do posto inteiro e muda com
        // qualquer combustível — daria à gasolina de agosto a idade do etanol
        // de ontem. É a data do abastecimento, não a do registro: quem registra
        // na quarta o abastecimento de segunda relata um preço de segunda.
        'pricedAt': {supply.fuel.name: supply.date},
      },
      'updatedAt': now.toIso8601String(),
      // A regra de segurança exige que este campo seja o próprio autor.
      'updatedBy': uid,
    };
  }

  /// O relato imutável em `gastop/{id}/precos`, com a data do abastecimento.
  static Map<String, dynamic> priceReport(Supply supply, String uid) => {
    'price': supply.pricePerLiter,
    'fuel': supply.fuel.name,
    'uid': uid,
    'at': supply.date,
  };

  /// Grava o posto e o relato.
  ///
  /// Dois caminhos, porque um preço velho não pode apagar um novo:
  ///
  /// - **Hoje**: `WriteBatch`, como sempre. Funciona **sem sinal**, na bomba —
  ///   um batch fica na fila offline e uma transação não.
  /// - **Outro dia**: transação, que lê `pricedAt` e só troca o preço atual se
  ///   este relato for mais novo. Quem registra depois está em casa, com rede.
  ///   O relato entra no histórico de qualquer jeito.
  ///
  /// Não faz nada quando [canReport] é falso — a guarda fica aqui, e não no
  /// formulário, para que qualquer caminho futuro que grave abastecimento
  /// herde a mesma regra.
  static Future<void> report(Supply supply, String uid, {DateTime? now}) async {
    if (!canReport(supply)) return;

    final clock = now ?? DateTime.now();
    final stationDoc = _collection.doc(supply.station!.id);

    // Relato imutável: as regras liberam `create` e negam `update` e `delete`.
    // Histórico que pode ser reescrito não é histórico — a mesma razão de a
    // provisão da rota ser um valor congelado.
    final reportDoc = stationDoc.collection('precos').doc(const Uuid().v4());

    try {
      if (!reportsPastDay(supply, now: clock)) {
        // As duas coisas contam a mesma história: um preço atual sem o relato
        // que o originou é um número sem procedência.
        final batch = FirestoreService.instance.batch();
        batch.set(
          stationDoc,
          stationFields(supply, uid, now: clock),
          SetOptions(merge: true),
        );
        batch.set(reportDoc, priceReport(supply, uid));
        await batch.commit();
        return;
      }

      final reported = DateTime.parse(supply.date);

      await FirestoreService.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(stationDoc);
        final stored = StationPrices.fromMap(
          snapshot.data() ?? const {},
        ).of(supply.fuel)?.at;

        if (shouldReplacePrice(stored: stored, reported: reported)) {
          transaction.set(
            stationDoc,
            stationFields(supply, uid, now: clock),
            SetOptions(merge: true),
          );
        }
        transaction.set(reportDoc, priceReport(supply, uid));
      });
    } catch (e) {
      // Falhar aqui não pode derrubar o registro do abastecimento: o gasto é
      // dele, a coleção global é conveniência para os outros. Sem rede, a
      // transação do relato de outro dia falha e ele se perde — o
      // abastecimento fica.
      debugPrint('gastop: não foi possível relatar o preço: $e');
    }
  }
}
