/// Os gastos de um período: o dinheiro que **saiu do bolso**.
///
/// ⚠️ Não se soma nem se subtrai do lucro dos cards de empresa. Aquele lucro já
/// desconta combustível como **provisão** (`km × R$/km`); somar o abastecimento
/// contaria a gasolina duas vezes. Este resumo é um **extrato**, não uma
/// dedução — ver `docs/specs/abastecimento.md`.
///
/// Comparar os dois um dia — "provisionei R$ 628 e gastei R$ 590" — é o valor
/// real que estes dados destravam. Somar não é.
library;

import 'package:flutter/foundation.dart';
import 'package:iter/model/supply.dart';

/// Um `null` aqui significa **"não dá para calcular"**. Zero é resultado
/// legítimo: não gastar nada num período é um fato, e é diferente de não saber.
class ExpenseSummary {
  const ExpenseSummary({
    required this.fuel,
    required this.maintenance,
    required this.supplies,
    this.liters,
    this.averagePricePerLiter,
  });

  /// Soma dos abastecimentos.
  final double fuel;

  /// Manutenções. Zero enquanto a tela não existe — é **reserva de espaço** no
  /// card, não afirmação de que ele não gastou com peça nenhuma.
  final double maintenance;

  /// Quantos abastecimentos entraram.
  final int supplies;

  /// Litros informados. `null` quando ninguém preencheu.
  final double? liters;

  double get total => fuel + maintenance;

  bool get isEmpty => supplies == 0 && maintenance == 0;

  /// Enquanto for falso, o card mostra a linha de manutenção marcada
  /// "em breve" em vez de um R$ 0,00 que pareceria afirmação.
  bool get hasMaintenance => maintenance > 0;

  /// Quanto ele pagou, em média, por litro no período.
  ///
  /// **Ponderado**: soma dos valores ÷ soma dos litros, e não a média dos
  /// preços de cada abastecimento. Quem enche R$ 300 a R$ 6,00 e completa R$ 30
  /// a R$ 7,00 pagou **R$ 6,08** no mês, não R$ 6,50 — a média simples daria a
  /// uma completada de R$ 30 o mesmo peso de um tanque cheio.
  ///
  /// Abastecimento sem litros fica **fora dos dois lados** da divisão: entrar
  /// só no dividendo inflaria o preço médio. O dinheiro dele continua inteiro
  /// em [fuel], que é o que o card mostra.
  final double? averagePricePerLiter;
}

/// Abastecimentos com data dentro do período, **as duas pontas inclusive**.
///
/// A comparação é por **dia**: abastecer às 23h do dia 31 é gasto daquele mês,
/// e comparar `DateTime` inteiro cortaria tudo depois da meia-noite do último
/// dia — a mesma armadilha que `inPeriod` das rotas já contorna.
List<Supply> suppliesInPeriod(
  List<Supply> supplies, {
  required DateTime start,
  required DateTime end,
}) {
  final from = DateTime(start.year, start.month, start.day);
  final to = DateTime(end.year, end.month, end.day);

  return supplies.where((supply) {
    final parsed = DateTime.tryParse(supply.date);
    if (parsed == null) {
      // Data ilegível é documento corrompido: não dá para saber a que período
      // pertence, então fica de fora em vez de derrubar a conta.
      debugPrint('Abastecimento ${supply.id} sem data legível: ${supply.date}');
      return false;
    }

    final day = DateTime(parsed.year, parsed.month, parsed.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }).toList();
}

/// Resume a lista **já filtrada** por período.
ExpenseSummary expenseSummary(List<Supply> supplies) {
  var fuel = 0.0;
  double? liters;

  // Acumulador separado: só o dinheiro dos abastecimentos que informaram
  // litros entra no preço médio. Usar `fuel` no dividendo somaria valor sem o
  // litro correspondente no divisor, e o preço médio subiria sozinho.
  var pricedValue = 0.0;

  for (final supply in supplies) {
    fuel += supply.value;

    final supplyLiters = supply.liters;
    if (supplyLiters != null && supplyLiters > 0) {
      liters = (liters ?? 0) + supplyLiters;
      pricedValue += supply.value;
    }
  }

  return ExpenseSummary(
    fuel: fuel,
    // Reservado: a tela de manutenção é outra spec, e este card a acolhe sem
    // mudança quando ela chegar.
    maintenance: 0,
    supplies: supplies.length,
    liters: liters,
    averagePricePerLiter: (liters != null && liters > 0)
        ? pricedValue / liters
        : null,
  );
}
