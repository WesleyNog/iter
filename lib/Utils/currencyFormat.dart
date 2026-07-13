import 'package:flutter/services.dart';

/// Helper para formatação de moeda em tempo real
class CurrencyFormatterHelper {
  /// Retorna uma lista de formatadores para campos de moeda
  /// Formata automaticamente enquanto o usuário digita
  /// Exemplo: 12345 -> R$ 123,45
  /// Limite máximo: R$ 100.000.000,00
  static List<TextInputFormatter> getCurrencyFormatter() {
    return [
      FilteringTextInputFormatter.digitsOnly,
      TextInputFormatter.withFunction((oldValue, newValue) {
        if (newValue.text.isEmpty) {
          return newValue.copyWith(text: '');
        }

        // Remove zeros à esquerda, exceto se for o único dígito
        String digitsOnly = newValue.text;
        if (digitsOnly.length > 1) {
          digitsOnly = digitsOnly.replaceFirst(RegExp(r'^0+'), '');
        }
        if (digitsOnly.isEmpty) {
          digitsOnly = '0';
        }

        // Limita para 100 milhões (10000000000 centavos = R$ 100.000.000,00)
        final value = int.tryParse(digitsOnly);
        if (value == null || value > 10000000000) {
          return oldValue;
        }

        // Converte para double e formata
        final double amount = value / 100;

        // Formata o valor
        final formatted = amount.toStringAsFixed(2);
        final parts = formatted.split('.');
        final intPart = parts[0].replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
        final decimalPart = parts[1];

        final newText = 'R\$ $intPart,$decimalPart';

        return TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }),
    ];
  }

  /// Converte texto formatado em double
  /// Exemplo: "R$ 123,45" -> 123.45
  static double parseMoneyToDouble(String value) {
    String cleanValue = value
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .trim();
    return double.tryParse(cleanValue) ?? 0.0;
  }

  /// Formata double em texto com moeda
  /// Exemplo: 123.45 -> "R$ 123,45"
  static String formatDoubleToMoney(double value) {
    if (value == 0.0) return '';
    String formatted = value.toStringAsFixed(2).replaceAll('.', ',');

    // Adiciona separador de milhares
    final parts = formatted.split(',');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );

    return 'R\$ $intPart,${parts[1]}';
  }
}
