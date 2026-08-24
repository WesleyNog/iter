import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/services/firebase.dart';

/// Leitura das rotas em `iter/{uid}/routes`.
class RouteController {
  static CollectionReference<Map<String, dynamic>> collectionOf(String uid) =>
      FirestoreService.instance.collection('iter').doc(uid).collection('routes');

  /// Acompanha as rotas do usuário, já ordenadas por proximidade com hoje.
  ///
  /// A ordenação é feita aqui e não no Firestore por duas razões: `dateRoute`
  /// está gravado como `dd/MM/yyyy`, e um `orderBy` compararia texto colocando
  /// `02/01/2026` antes de `31/12/2025`; e "mais perto de hoje" depende da
  /// data atual, que nenhum índice do Firestore sabe calcular.
  static Stream<List<NewRouteModal>> watchAll(String uid) {
    return collectionOf(uid).snapshots().map(_parseAll);
  }

  /// Leitura única, para quando não faz sentido manter o listener aberto.
  static Future<List<NewRouteModal>> fetchAll(String uid) async {
    return _parseAll(await collectionOf(uid).get());
  }

  /// Cria ou substitui a rota. Mesmo `id` = edição, `id` novo = cadastro.
  static Future<void> save(String uid, NewRouteModal route) {
    return collectionOf(uid).doc(route.id).set(route.toMap());
  }

  /// Troca **só** o status da rota, sem tocar em mais nenhum campo.
  ///
  /// É `update` e não `set` de propósito, e a diferença é a garantia: o que não
  /// é enviado não pode ser sobrescrito. A provisão congelada, o
  /// `noRoutePayment` e o valor ficam fora do pacote, então nem um erro deste
  /// arquivo consegue reescrevê-los — enquanto um `set` a partir de um objeto
  /// remontado depende de dezoito campos estarem todos certos, que é o ovo e a
  /// galinha que `withProvision` já documenta.
  ///
  /// Por isso mesmo, isto vale **apenas** para a troca que não implica
  /// recálculo: concluído ↔ pago, os dois `hasRun` com a mesma provisão. Quem
  /// precisa de qualquer outra usa o formulário, que recalcula o que tem de
  /// recalcular — ver `RouteSlidable.canMarkPaid`.
  static Future<void> updateStatus(
    String uid,
    String routeId,
    StatusRoute status,
  ) {
    return collectionOf(uid).doc(routeId).update({
      'status': storedStatus(status),
    });
  }

  static Future<void> delete(String uid, String routeId) {
    return collectionOf(uid).doc(routeId).delete();
  }

  static List<NewRouteModal> _parseAll(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final routes = <NewRouteModal>[];

    for (final doc in snapshot.docs) {
      try {
        routes.add(NewRouteModal.fromMap(doc.data()));
      } catch (e) {
        // Um documento fora do formato não pode derrubar a lista inteira.
        debugPrint('Rota ${doc.id} ignorada: $e');
      }
    }

    return sortByDate(routes);
  }

  /// Converte `dd/MM/yyyy`; devolve `null` quando o formato não bate.
  static DateTime? parseDate(String raw) {
    final parts = raw.split('/');
    if (parts.length != 3) return null;

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    return DateTime(year, month, day);
  }

  /// Ordena pela proximidade com o dia de hoje: a rota mais perto da data
  /// atual primeiro, indo para as mais distantes — tanto no futuro quanto no
  /// passado.
  ///
  /// Empate de distância (ontem x amanhã) fica com a do futuro, que é a que
  /// ainda vai ser rodada. Data ilegível vai para o fim em vez de lançar.
  ///
  /// [reference] existe para o teste fixar o "hoje".
  static List<NewRouteModal> sortByDate(
    List<NewRouteModal> routes, {
    DateTime? reference,
  }) {
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sorted = [...routes];

    sorted.sort((a, b) {
      final dateA = parseDate(a.dateRoute);
      final dateB = parseDate(b.dateRoute);

      if (dateA == null && dateB == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (dateA == null) return 1;
      if (dateB == null) return -1;

      final daysA = dateA.difference(today).inDays;
      final daysB = dateB.difference(today).inDays;

      final byDistance = daysA.abs().compareTo(daysB.abs());
      if (byDistance != 0) return byDistance;

      // Mesma distância: o futuro vem antes do passado.
      if (daysA.sign != daysB.sign) return daysB.compareTo(daysA);

      return b.createdAt.compareTo(a.createdAt);
    });

    return sorted;
  }
}
