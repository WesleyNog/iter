import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/expenseSummary.dart';
import 'package:iter/Utils/fuelEconomy.dart';
import 'package:iter/model/supply.dart';

/// O card de **gastos** do período, abaixo dos cards de empresa.
///
/// Fica visualmente diferente deles de propósito: os de cima são receita e
/// lucro, este é dinheiro saindo. Mesma tela, naturezas opostas.
///
/// ⚠️ **Não é dedução.** O lucro dos cards de empresa já desconta combustível
/// como provisão (`km × R$/km`); subtrair estes gastos contaria a gasolina duas
/// vezes. O card traz uma linha dizendo isso, porque ver "Lucro R$ 175,60" logo
/// acima de "Gastos R$ 430,50" convida a fazer a conta de cabeça — e ela estaria
/// errada.
class ExpenseCard extends StatelessWidget {
  const ExpenseCard({
    super.key,
    required this.summary,
    this.onDetail,
    this.economy,
  });

  final ExpenseSummary summary;

  /// Consumo medido **no período**, por combustível.
  ///
  /// `null` quando não dá para atribuir a um carro só — ver [periodEconomy].
  /// Diferente do card do veículo, que mostra o de toda a vida: aqui a pergunta
  /// é "como foi este mês", lá é "quanto meu carro faz".
  final Map<SupplyFuel, EconomyResult>? economy;

  /// `null` esconde o botão — sem gasto no período não há o que detalhar.
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_gas_station_outlined,
                size: 20,
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GASTOS DO PERÍODO',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _line('Abastecimento', CurrencyFormatterHelper.formatMoney(summary.fuel),
              key: 'expense-fuel'),
          const SizedBox(height: 6),
          _line(
            'Manutenção',
            // Antes desta entrega esta linha dizia "em breve", porque o app não
            // tinha como saber. Agora tem: `R$ 0,00` é **afirmação** — não
            // gastou com peça no período —, e não ausência de informação.
            CurrencyFormatterHelper.formatMoney(summary.maintenance),
            key: 'expense-maintenance',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Colors.grey.shade200),
          ),
          _line(
            'Total',
            CurrencyFormatterHelper.formatMoney(summary.total),
            key: 'expense-total',
            bold: true,
          ),
          if (!summary.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _meta(),
              key: const Key('expense-meta'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            // A frase existe para impedir a subtração de cabeça. Agora diz
            // "e peças" também: a provisão cobre as duas frentes, e este card
            // passou a somar as duas.
            'Gasto real do bolso. O lucro acima já desconta a provisão de '
            'combustível e peças — os dois não se somam.',
            key: const Key('expense-note'),
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: Colors.grey.shade500,
            ),
          ),
          if (onDetail != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('expense-detail'),
                onPressed: onDetail,
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('Detalhar'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// `2 abastecimentos · 1 manutenção · 72,5 L · R$ 5,94/L`.
  ///
  /// Contagem zerada não entra: "0 manutenções" seria ruído, e a linha do valor
  /// logo acima já diz que foi zero.
  String _meta() {
    final parts = <String>[
      if (summary.supplies > 0)
        _plural(summary.supplies, 'abastecimento', 'abastecimentos'),
      if (summary.maintenances > 0)
        _plural(summary.maintenances, 'manutenção', 'manutenções'),
      if (summary.liters != null)
        '${formatNumber(summary.liters!, decimals: 1)} L',
      if (summary.averagePricePerLiter != null)
        '${formatRate(summary.averagePricePerLiter!)}/L',
      ..._measured(),
    ];

    return parts.join(' · ');
  }

  /// `10,96 km/l`, ou `gasolina 10,96 · etanol 8,00 km/l` com os dois.
  List<String> _measured() {
    final medidos = <String>[
      for (final entry in (economy ?? const {}).entries)
        if (entry.value.economy case final e?)
          economy!.length == 1
              ? formatEconomy(e.kmPerLiter)
              : '${entry.key.label.toLowerCase()} '
                    '${formatEconomy(e.kmPerLiter)}',
    ];

    // Sem medição não entra nada: a dica de "informe o KM" mora no card do
    // veículo, que é onde ele vai resolver isso. Repetir aqui seria cobrança
    // dobrada.
    return medidos;
  }

  String _plural(int count, String singular, String plural) =>
      '$count ${count == 1 ? singular : plural}';

  Widget _line(
    String label,
    String value, {
    required String key,
    bool bold = false,
    bool muted = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: bold ? FontWeight.bold : null,
            ),
          ),
        ),
        Text(
          value,
          key: Key(key),
          style: TextStyle(
            fontSize: bold ? 18 : 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            fontStyle: muted ? FontStyle.italic : null,
            color: muted ? Colors.grey.shade500 : null,
          ),
        ),
      ],
    );
  }
}
