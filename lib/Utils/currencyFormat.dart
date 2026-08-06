import 'package:flutter/services.dart';

/// Taxa em R$/km com quatro casas: `0,0133` some inteira em duas.
///
/// Mora aqui, e não no widget que a usa primeiro, porque três telas precisam
/// dela — o editor de peças, o card do veículo e o resumo por empresa.
String formatRate(double rate) =>
    'R\$ ${rate.toStringAsFixed(4).replaceAll('.', ',')}';

/// `1284.5` → `1.284,5`. Separador de milhar para números grandes de KM,
/// pacotes e paradas, que passam da casa dos milhares em um mês de trabalho.
String formatNumber(num value, {int decimals = 0}) {
  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final integer = parts[0].replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );

  return parts.length == 1 ? integer : '$integer,${parts[1]}';
}

/// Lê quilometragem: `50.000` e `50000` são cinquenta mil.
///
/// Aqui o ponto é **sempre** separador de milhar. São valores na casa dos
/// milhares e ninguém informa vida útil com casa decimal — tratar o ponto como
/// decimal transformaria "50.000 km" em 50 km.
double? parseKm(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null; // vazio é "não preenchi", não "vale zero"

  return double.tryParse(text.replaceAll('.', '').replaceAll(',', '.'));
}

/// Lê uma taxa em R$/km: aceita `0,03` **e** `0.03`.
///
/// Aqui o ponto é decimal, ao contrário de [parseKm]: são valores menores que
/// um, e o teclado numérico do celular oferece ponto. Tratá-lo como separador
/// de milhar faria `0.03` virar `3` — cem vezes a taxa, e num campo em que
/// ninguém confere o resultado de cabeça.
///
/// Só quando há vírgula o ponto volta a ser milhar (`1.234,5`).
double? parseRate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final normalized = text.contains(',')
      ? text.replaceAll('.', '').replaceAll(',', '.')
      : text;

  return double.tryParse(normalized);
}

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

  /// Como [formatDoubleToMoney], mas zero vira `R$ 0,00` em vez de texto
  /// vazio.
  ///
  /// A versão original devolve `''` para zero porque nasceu para preencher
  /// campo de formulário, onde vazio é o certo. Em tela de leitura zero é
  /// resultado legítimo e precisa aparecer.
  static String formatMoney(double value) =>
      value == 0 ? 'R\$ 0,00' : formatDoubleToMoney(value);

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
