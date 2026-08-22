import 'package:flutter/material.dart';
import 'package:iter/Utils/periodPreset.dart' as period;
import 'package:iter/widget/dataPicker.dart';

/// Seleção do período dos gráficos: uma data de início e uma de fim.
///
/// Fim anterior ao início é **impossível**, não recusado: cada roleta recebe o
/// limite da outra (`minimumDate`/`maximumDate`), então a escolha inválida nem
/// chega a ser feita. Validar depois exigiria avisar o usuário no meio do giro
/// da roleta, que dispara callback a cada tique.
class PeriodFilter extends StatelessWidget {
  const PeriodFilter({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final DateTime start;
  final DateTime end;
  final void Function(DateTime start, DateTime end) onChanged;

  /// Primeiro ao último dia do mês corrente — o recorte que o entregador olha
  /// no dia a dia.
  ///
  /// A conta mudou de casa: ela é um dos cinco atalhos de
  /// `Utils/periodPreset.dart` desde que o seletor de período passou a
  /// oferecê-los prontos. O nome continua aqui porque `periodLabel` do Resumo e
  /// `test/unit/periodLabel_test.dart` apontam para ele — uma implementação,
  /// dois nomes, como `VehicleController.activeFrom`.
  static period.DateRange currentMonth([DateTime? reference]) =>
      period.currentMonth(reference);

  static String formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _dateField(
            context,
            label: 'Início',
            value: start,
            // Não pode passar do fim.
            maximumDate: end,
            onPicked: (picked) => onChanged(picked, end),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: Colors.grey.shade400,
          ),
        ),
        Expanded(
          child: _dateField(
            context,
            label: 'Fim',
            value: end,
            // Não pode vir antes do início.
            minimumDate: start,
            onPicked: (picked) => onChanged(start, picked),
          ),
        ),
      ],
    );
  }

  Widget _dateField(
    BuildContext context, {
    required String label,
    required DateTime value,
    required ValueChanged<DateTime> onPicked,
    DateTime? minimumDate,
    DateTime? maximumDate,
  }) {
    return InkWell(
      onTap: () => showCupertinoDatePicker(
        context,
        value,
        onPicked,
        minimumDate: minimumDate,
        maximumDate: maximumDate,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 16,
              color: Colors.blue.shade600,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    formatDate(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
