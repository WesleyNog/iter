import 'package:flutter/material.dart';
import 'package:iter/Utils/companySummary.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';

/// Um card do resumo: uma empresa, ou o total do período.
///
/// [company] `null` monta o card de total geral, em destaque no topo — mesma
/// estrutura, outra roupa, para os números ficarem nas mesmas posições e o olho
/// não ter de reaprender o layout entre um card e outro.
class CompanySummaryCard extends StatelessWidget {
  const CompanySummaryCard({
    super.key,
    required this.summary,
    this.company,
    this.totalLabel = 'Total do período',
  });

  final CompanySummary summary;

  /// `null` = card de total geral.
  final Company? company;

  final String totalLabel;

  bool get _isTotal => company == null;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: _isTotal ? null : Colors.white,
        border: _isTotal
            ? null
            : Border.all(color: Colors.grey.shade300),
        gradient: _isTotal
            // O mesmo azul dos cards de gráfico e do rodapé do veículo: o app
            // não ganha uma quarta cor de destaque.
            ? const LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1976D2)])
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 12),
          if (summary.isEmpty)
            Text(
              'Sem rotas no período',
              key: const Key('summary-empty'),
              style: TextStyle(
                fontSize: 13,
                color: _isTotal ? Colors.white70 : Colors.grey.shade600,
              ),
            )
          else ...[
            // "Ganhos" e não "Rotas": desde a Sem Rota este número soma
            // dinheiro que não veio de rota nenhuma, e o rótulo antigo passaria
            // a descrever errado o que está do lado dele.
            _money('Ganhos', summary.value, key: 'summary-value'),
            const SizedBox(height: 6),
            _money(
              'Lucro',
              summary.profit,
              key: 'summary-profit',
              bold: true,
              color: _isTotal ? Colors.white : Colors.green.shade700,
            ),
            if (summary.noRouteCount > 0) _noRouteNote(),
            if (summary.hasUncalculated) _uncalculatedWarning(),
            _divider(),
            _metrics(),
            if (summary.topBairro != null) ...[_divider(), _bairros()],
          ],
        ],
      ),
    );
  }

  /// Quanto dos ganhos veio de ida que não virou rota.
  ///
  /// A parcela aparece porque ela **está dentro** de "Ganhos" e de "Lucro", não
  /// ao lado: sem a linha, um mês com muita ida ao CD pareceria um mês de
  /// rotas. Some sozinha quando não houve nenhuma — e esse silêncio é o caso
  /// normal.
  Widget _noRouteNote() {
    final count = summary.noRouteCount;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.do_not_disturb_on_outlined,
            size: 13,
            color: _isTotal ? Colors.white70 : Colors.blueGrey.shade400,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${CurrencyFormatterHelper.formatMoney(summary.noRouteValue)}'
              ' de ${count == 1 ? '1 ida' : '$count idas'} sem rota',
              key: const Key('summary-no-route'),
              style: TextStyle(
                fontSize: 11,
                color: _isTotal ? Colors.white70 : Colors.blueGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final routes = summary.routes;
    final label = _isTotal
        ? totalLabel
        : companyLabel(company!).toUpperCase();

    return Row(
      children: [
        if (!_isTotal) ...[
          SizedBox(
            width: 26,
            height: 26,
            child: Image.asset(
              companyLogo(company!),
              fit: BoxFit.contain,
              // Logo ausente não pode quebrar o cabeçalho inteiro.
              errorBuilder: (_, _, _) => Icon(
                Icons.local_shipping_outlined,
                size: 20,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            label,
            key: const Key('summary-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _isTotal ? 13 : 14,
              fontWeight: FontWeight.bold,
              letterSpacing: _isTotal ? 1 : 0,
              color: _isTotal ? Colors.white70 : null,
            ),
          ),
        ),
        Text(
          routes == 1 ? '1 rota' : '$routes rotas',
          key: const Key('summary-routes'),
          style: TextStyle(
            fontSize: 12,
            color: _isTotal ? Colors.white70 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  /// A linha que impede o lucro misto de enganar.
  ///
  /// Some sozinha quando toda rota do período tiver custo calculado — e esse
  /// silêncio é o sinal de que o número está inteiro.
  Widget _uncalculatedWarning() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 13,
            color: _isTotal ? Colors.amberAccent : Colors.orange.shade700,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${CurrencyFormatterHelper.formatMoney(summary.uncalculatedValue)}'
              ' ainda sem custo calculado',
              key: const Key('summary-uncalculated'),
              style: TextStyle(
                fontSize: 11,
                color: _isTotal ? Colors.amberAccent : Colors.orange.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metrics() {
    final rate = summary.failureRate;
    final failures = summary.failures;

    return Column(
      children: [
        Row(
          children: [
            _metric(
              'KM',
              summary.km == null
                  ? null
                  : '${formatNumber(summary.km!, decimals: 1)} km',
              key: 'summary-km',
            ),
            _metric(
              'Pacotes',
              summary.packages == null
                  ? null
                  : formatNumber(summary.packages!),
              key: 'summary-packages',
            ),
            _metric(
              'Paradas',
              summary.stops == null ? null : formatNumber(summary.stops!),
              key: 'summary-stops',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _metric(
              'Insucessos',
              // A quantidade sozinha não compara entre empresas: 12 em 500
              // pacotes e 12 em 80 são realidades diferentes.
              rate == null
                  ? formatNumber(failures)
                  : '${formatNumber(failures)}'
                        ' (${formatNumber(rate, decimals: 1)}%)',
              key: 'summary-failures',
            ),
            _metric(
              'Custo por km',
              summary.costPerKm == null ? null : formatRate(summary.costPerKm!),
              key: 'summary-cost',
            ),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _metric(String label, String? value, {required String key}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: _isTotal ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            // `—` e nunca `0`: "ninguém informou" e "foi zero" são coisas
            // diferentes.
            value ?? '—',
            key: Key(key),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _isTotal ? Colors.white : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bairros() {
    final top = summary.topBairro;
    final bottom = summary.bottomBairro;

    return Column(
      children: [
        _bairroRow('Mais rodado', top!, key: 'summary-top'),
        // Com um bairro só os dois seriam o mesmo nome, em duas linhas com
        // rótulos opostos — parece defeito, então a segunda some.
        if (bottom != null && bottom != top) ...[
          const SizedBox(height: 6),
          _bairroRow('Menos rodado', bottom, key: 'summary-bottom'),
        ],
      ],
    );
  }

  Widget _bairroRow(String label, String value, {required String key}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: _isTotal ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
        ),
        Text(
          value,
          key: Key(key),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _isTotal ? Colors.white : null,
          ),
        ),
      ],
    );
  }

  Widget _money(
    String label,
    double value, {
    required String key,
    bool bold = false,
    Color? color,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: _isTotal ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
        ),
        Text(
          CurrencyFormatterHelper.formatMoney(value),
          key: Key(key),
          style: TextStyle(
            fontSize: bold ? 20 : 15,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color ?? (_isTotal ? Colors.white : null),
          ),
        ),
      ],
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Divider(
      height: 1,
      color: _isTotal ? Colors.white24 : Colors.grey.shade200,
    ),
  );
}
