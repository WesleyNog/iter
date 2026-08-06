import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/expenseSummary.dart';

/// O extrato do período: abastecimentos e manutenções na mesma lista, por data.
///
/// Recebe as linhas **já montadas e ordenadas** por `expenseRows`, em vez de
/// abrir os próprios streams: são as mesmas linhas que o card somou, então o
/// detalhe nunca discorda do total que levou o usuário até aqui. Dois streams
/// poderiam divergir por um instante e mostrar um valor que não fecha.
///
/// Os dois tipos vêm misturados de propósito. O extrato responde "quanto saiu
/// do bolso e quando"; separar por natureza obrigaria a somar duas listas de
/// cabeça para ter a ordem cronológica.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({
    super.key,
    required this.rows,
    required this.periodLabel,
  });

  final List<ExpenseRow> rows;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              periodLabel,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ),
      ),
      body: rows.isEmpty
          ? Center(
              child: Text(
                'Nenhum gasto no período.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _row(rows[index], index),
            ),
    );
  }

  Widget _row(ExpenseRow row, int index) {
    final isFuel = row.kind == ExpenseKind.abastecimento;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // O ícone distingue as duas naturezas de relance, sem obrigar a ler
          // a linha de baixo.
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (isFuel ? Colors.orange : Colors.blueGrey).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isFuel ? Icons.local_gas_station_outlined : Icons.build_outlined,
              key: Key('expense-icon-$index'),
              size: 20,
              color: isFuel ? Colors.orange.shade700 : Colors.blueGrey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.title,
                        key: Key('expense-title-$index'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      CurrencyFormatterHelper.formatMoney(row.value),
                      key: Key('expense-value-$index'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _detail(row),
                  key: Key('expense-detail-$index'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `06/08/2026 · Substituição · Auto Center do Zé`.
  ///
  /// A data entra aqui e não no `ExpenseRow` porque o record guarda ISO, que
  /// ordena; quem formata para leitura é a tela.
  String _detail(ExpenseRow row) {
    final parsed = DateTime.tryParse(row.date);
    final data = parsed == null
        ? null
        : '${parsed.day.toString().padLeft(2, '0')}/'
              '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';

    return [
      ?data,
      if (row.subtitle.isNotEmpty) row.subtitle,
    ].join(' · ');
  }
}
