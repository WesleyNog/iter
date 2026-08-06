import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/Utils/routeTime.dart';
import 'package:iter/Utils/weather.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/services/openWeather.dart';

/// Container de uma rota na lista.
///
/// A expansão é controlada de fora ([isExpanded] + [onTap]) para a tela poder
/// manter só um card aberto por vez.
class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.route,
    this.isExpanded = false,
    this.onTap,
  });

  final NewRouteModal route;
  final bool isExpanded;
  final VoidCallback? onTap;

  /// `formatDoubleToMoney` devolve string vazia para zero — aqui zero é um
  /// valor legítimo e precisa aparecer.
  String get _formattedValue => route.value == 0
      ? 'R\$ 0,00'
      : CurrencyFormatterHelper.formatDoubleToMoney(route.value);

  double? get _totalKm {
    final initial = route.kmInitial;
    final complete = route.kmFinal;
    if (initial == null || complete == null) return null;
    final total = complete - initial;
    return total > 0 ? total : null;
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor(route.status);

    return Card(
      elevation: 0,
      // Sem margem: o espaçamento entre cards é da lista. Aqui dentro, ele
      // entraria na área do Slidable e deixaria as ações mais altas que o card.
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(color),
              // AnimatedSize e não AnimatedCrossFade: este mantém os dois
              // filhos na árvore, então cada card fechado da lista montaria
              // os detalhes à toa.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topCenter,
                child: isExpanded
                    ? _details()
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Color color) {
    final weekday = weekdayLabel(route.weekday);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(4),
          child: Image.asset(
            companyLogo(route.company),
            fit: BoxFit.contain,
            // Logo ausente não pode quebrar a linha inteira.
            errorBuilder: (_, _, _) =>
                Icon(Icons.local_shipping_outlined, color: Colors.grey.shade500),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekday.isEmpty
                    ? route.dateRoute
                    : '$weekday, ${route.dateRoute}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              _statusChip(color),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formattedValue,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: Colors.grey.shade500,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusChip(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(route.status), size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            statusLabel(route.status),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _details() {
    final km = _totalKm;
    final packages = route.packages;
    final stops = route.stops;
    final start = RouteTime.formatTime(route.startAt);
    final end = route.endAt;
    final duration = RouteTime.formatDuration(route.startAt, end);
    final bairros = route.adress ?? const <String>[];
    final weather = route.weather;

    final rows = <Widget>[
      if (km != null)
        _detailRow(Icons.speed, 'KM rodado', '${km.toStringAsFixed(1)} km'),
      if (packages != null)
        _detailRow(Icons.inventory_2_outlined, 'Pacotes', '$packages'),
      if (stops != null)
        _detailRow(Icons.location_on_outlined, 'Paradas', '$stops'),
      _detailRow(
        Icons.access_time,
        'Horário',
        end == null
            ? 'Início às $start'
            : '$start às ${RouteTime.formatTime(end)}'
                  '${duration == null ? '' : ' ($duration)'}',
      ),
      if (bairros.isNotEmpty)
        _detailRow(Icons.streetview_outlined, 'Bairros', bairros.join(', ')),
      if (route.isInsucesso == true)
        _detailRow(
          Icons.report_gmailerrorred_outlined,
          'Insucessos',
          _insucessoLabel(),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 12),
        // A linha de horário sempre existe (startAt é obrigatório), então não
        // há mais o caso de detalhe nenhum.
        ...rows,
        if (weather != null && weather.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Image.asset(
                getWeatherIcon(WeatherType.fromString(weather)),
                width: 22,
                height: 22,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              Text(
                'Clima no dia',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
        _profitBlock(),
      ],
    );
  }

  /// Gasolina, provisão e lucro — as colunas F, L e O da planilha.
  ///
  /// Só aparece quando há provisão gravada. Rota concluída sem KM ganha a dica
  /// do que falta, em vez de um "Lucro R$ 0,00" que seria falso: sem KM o app
  /// não sabe o custo, e não saber é diferente de não ter custo.
  Widget _profitBlock() {
    final provision = route.provision;

    if (provision == null) {
      final done =
          route.status == StatusRoute.concluido ||
          route.status == StatusRoute.pago;
      if (!done || _totalKm != null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Informe o KM para calcular o lucro.',
          key: const Key('route-profit-hint'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      );
    }

    final profit = route.profit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 10),
        _moneyRow('Gasolina', provision.fuel, key: 'route-fuel'),
        // A gasolina fica fora da provisão, como na planilha: `Total P.` é
        // `=SUM(G3:K3)` e o lucro subtrai as duas separadamente.
        _moneyRow('Provisão', provision.totalParts, key: 'route-provision'),
        if (profit != null)
          _moneyRow(
            'Lucro',
            profit,
            key: 'route-profit',
            color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade600,
            bold: true,
          ),
      ],
    );
  }

  Widget _moneyRow(
    String label,
    double value, {
    required String key,
    Color? color,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color ?? Colors.grey.shade600,
                fontWeight: bold ? FontWeight.bold : null,
              ),
            ),
          ),
          Text(
            CurrencyFormatterHelper.formatMoney(value),
            key: Key(key),
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// `3` quando não se sabe onde foram, `3 (Aldeota 2, Centro 1)` quando sabe.
  ///
  /// Mostra a distribuição parcial como está: o que ficou de fora aparece na
  /// diferença entre o total e a soma dos parênteses, e é o que o gráfico
  /// rateia.
  String _insucessoLabel() {
    final total = route.insucessoQnt ?? 1;
    final distribution = route.insucessoPorBairro;
    if (distribution.isEmpty) return '$total';

    final detail = distribution.entries
        .map((entry) => '${entry.key} ${entry.value}')
        .join(', ');

    return '$total ($detail)';
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
