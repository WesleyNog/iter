/// Os gastos de um período: o dinheiro que **saiu do bolso**.
///
/// ⚠️ Não se soma nem se subtrai do lucro dos cards de empresa. Aquele lucro já
/// desconta combustível **e peças** como provisão (`km × R$/km`); somar o
/// abastecimento e a manutenção contaria tudo duas vezes. Este resumo é um
/// **extrato**, não uma dedução — ver `docs/specs/abastecimento.md` e
/// `docs/specs/manutencao.md`.
///
/// Comparar os dois um dia — "provisionei R$ 628 e gastei R$ 590" — é o valor
/// real que estes dados destravam. Somar não é.
library;

import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/supply.dart';

/// Um `null` aqui significa **"não dá para calcular"**. Zero é resultado
/// legítimo: não gastar nada num período é um fato, e é diferente de não saber.
class ExpenseSummary {
  const ExpenseSummary({
    required this.fuel,
    required this.maintenance,
    required this.supplies,
    required this.maintenances,
    this.liters,
    this.averagePricePerLiter,
  });

  /// Soma dos abastecimentos.
  final double fuel;

  /// Soma das manutenções.
  final double maintenance;

  /// Quantos abastecimentos entraram.
  final int supplies;

  /// Quantas manutenções entraram.
  final int maintenances;

  /// Litros informados. `null` quando ninguém preencheu.
  final double? liters;

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

  double get total => fuel + maintenance;

  bool get isEmpty => supplies == 0 && maintenances == 0;
}

/// Resume as listas **já filtradas** por período.
ExpenseSummary expenseSummary(
  List<Supply> supplies,
  List<Maintenance> maintenances,
) {
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

  var maintenanceTotal = 0.0;
  for (final item in maintenances) {
    maintenanceTotal += item.value;
  }

  return ExpenseSummary(
    fuel: fuel,
    maintenance: maintenanceTotal,
    supplies: supplies.length,
    maintenances: maintenances.length,
    liters: liters,
    averagePricePerLiter: (liters != null && liters > 0)
        ? pricedValue / liters
        : null,
  );
}

/// De que natureza é a linha do extrato.
enum ExpenseKind { abastecimento, manutencao }

/// Uma linha do extrato, pronta para desenhar.
///
/// A junção dos dois tipos vive aqui, e não no widget, porque ordenar e rotular
/// é decisão — e decisão testável. A tela só desenha.
typedef ExpenseRow = ({
  String id,
  String date,
  String title,
  String subtitle,
  double value,
  ExpenseKind kind,
});

/// Abastecimentos e manutenções na **mesma lista**, do mais recente para o mais
/// antigo.
///
/// Recebe as listas já filtradas por período. Os dois tipos entram misturados
/// de propósito: o extrato responde "quanto saiu do bolso e quando", e separar
/// por natureza obrigaria a somar duas listas de cabeça para ter a ordem
/// cronológica.
List<ExpenseRow> expenseRows(
  List<Supply> supplies,
  List<Maintenance> maintenances,
) {
  final rows = <ExpenseRow>[
    for (final supply in supplies)
      (
        id: supply.id,
        date: supply.date,
        // Posto é opcional em todos os caminhos: sem GPS, sem rede, ou
        // simplesmente não informado.
        title: supply.station?.label ?? 'Posto não informado',
        subtitle: _supplySubtitle(supply),
        value: supply.value,
        kind: ExpenseKind.abastecimento,
      ),
    for (final item in maintenances)
      (
        id: item.id,
        date: item.date,
        title: item.item.label,
        subtitle: _maintenanceSubtitle(item),
        value: item.value,
        kind: ExpenseKind.manutencao,
      ),
  ];

  // A ordenação é a mesma de sempre; aqui só não dá para usar
  // `sortByDateDesc` porque `ExpenseRow` é um record, não um `Dated`.
  rows.sort((a, b) {
    if (a.date.isEmpty && b.date.isEmpty) return a.id.compareTo(b.id);
    if (a.date.isEmpty) return 1;
    if (b.date.isEmpty) return -1;

    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  });

  return rows;
}

/// `Gasolina · 39,8 L · R$ 6,2893/L`.
String _supplySubtitle(Supply supply) {
  final price = supply.pricePerLiter;

  return [
    supply.fuel.label,
    if (supply.liters != null)
      '${formatNumber(supply.liters!, decimals: 1)} L',
    // Sem litros não há preço — o campo some em vez de mostrar zero.
    if (price != null) '${formatRate(price)}/L',
  ].join(' · ');
}

/// `Substituição · Auto Center do Zé`.
String _maintenanceSubtitle(Maintenance maintenance) {
  final workshop = maintenance.workshop?.trim() ?? '';

  return [
    maintenance.action.label,
    if (workshop.isNotEmpty) workshop,
  ].join(' · ');
}
