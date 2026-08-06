/// O mínimo que um registro precisa para entrar num extrato: uma data e um id.
///
/// Existe porque abastecimento e manutenção são coisas diferentes que o app
/// trata igual em três lugares — ordenar, filtrar por período e listar juntos.
/// Sem isto, cada controller carregaria a própria cópia da mesma ordenação, e
/// uma delas um dia ficaria para trás.
library;

import 'package:flutter/foundation.dart';

abstract interface class Dated {
  String get id;

  /// ISO 8601. É o formato de propósito: ordena como texto na mesma ordem em
  /// que ordena como data, então a lista já sai certa sem o remendo em memória
  /// que `RouteController` precisou fazer com `dd/MM/yyyy`.
  String get date;
}

/// Registros com data dentro do período, **as duas pontas inclusive**.
///
/// A comparação é por **dia**: abastecer ou consertar às 23h do dia 31 é gasto
/// daquele mês, e comparar `DateTime` inteiro cortaria tudo depois da
/// meia-noite do último dia.
///
/// Data ilegível fica de fora — não dá para saber a que período pertence — em
/// vez de derrubar a conta.
List<T> inPeriodByDate<T extends Dated>(
  List<T> items, {
  required DateTime start,
  required DateTime end,
}) {
  final from = DateTime(start.year, start.month, start.day);
  final to = DateTime(end.year, end.month, end.day);

  return items.where((item) {
    final parsed = DateTime.tryParse(item.date);
    if (parsed == null) {
      debugPrint('Registro ${item.id} sem data legível: ${item.date}');
      return false;
    }

    final day = DateTime(parsed.year, parsed.month, parsed.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }).toList();
}

/// Do mais recente para o mais antigo.
///
/// Data vazia — documento corrompido — vai para o fim em vez de lançar. Empate
/// desempata pelo `id`, para a ordem não dançar entre dois rebuilds.
List<T> sortByDateDesc<T extends Dated>(List<T> items) {
  final sorted = [...items];

  sorted.sort((a, b) {
    if (a.date.isEmpty && b.date.isEmpty) return a.id.compareTo(b.id);
    if (a.date.isEmpty) return 1;
    if (b.date.isEmpty) return -1;

    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  });

  return sorted;
}
