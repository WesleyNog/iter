import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/model/supply.dart';

/// A lista dos abastecimentos de um período.
///
/// Recebe a lista **já filtrada**, em vez de abrir o próprio stream: é a mesma
/// lista que o card somou, então o detalhe nunca discorda do total que levou o
/// usuário até aqui. Dois streams poderiam divergir por um instante e mostrar
/// um valor que não fecha.
class SuppliesScreen extends StatelessWidget {
  const SuppliesScreen({
    super.key,
    required this.supplies,
    required this.periodLabel,
  });

  final List<Supply> supplies;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abastecimentos'),
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
      body: supplies.isEmpty
          ? Center(
              child: Text(
                'Nenhum abastecimento no período.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: supplies.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _row(supplies[index], index),
            ),
    );
  }

  Widget _row(Supply supply, int index) {
    final price = supply.pricePerLiter;
    final station = supply.station;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // Posto é opcional em todos os caminhos: sem GPS, sem rede,
                  // ou simplesmente não informado.
                  station?.label ?? 'Posto não informado',
                  key: Key('supply-station-$index'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                CurrencyFormatterHelper.formatMoney(supply.value),
                key: Key('supply-value-$index'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _detail(supply, price),
            key: Key('supply-detail-$index'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  /// `05/08/2026 · Gasolina · 39,8 L · R$ 6,2893/L`.
  String _detail(Supply supply, double? price) {
    final parsed = DateTime.tryParse(supply.date);

    return [
      if (parsed != null)
        '${parsed.day.toString().padLeft(2, '0')}/'
            '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}',
      supply.fuel.label,
      if (supply.liters != null)
        '${formatNumber(supply.liters!, decimals: 1)} L',
      // Sem litros não há preço — e o campo some em vez de mostrar zero.
      if (price != null) '${formatRate(price)}/L',
    ].join(' · ');
  }
}
