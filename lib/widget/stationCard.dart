import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/relativeTime.dart';
import 'package:iter/Utils/stationFlag.dart';
import 'package:iter/Utils/text.dart';
import 'package:iter/model/stationPrices.dart';
import 'package:iter/model/supply.dart';

/// O que a faixa de preços de um card sabe.
///
/// Três estados que **não podem se confundir**, a regra do `getWeather`:
/// `—` enquanto carrega, ou quando a leitura falhou, diria "ninguém relatou"
/// sobre um posto que pode ter preço.
enum PricesState { loading, failed, ready }

/// Um posto: logo, bairro, nome, distância e — na lista — os preços.
///
/// O mesmo card serve à lista de "Postos da região" e ao campo do formulário.
/// No formulário vai sem [meters] (depois de escolhido, "2,8 km" de onde?) e
/// sem [pricesState], que é quando a faixa nem aparece.
class StationCard extends StatelessWidget {
  const StationCard({
    super.key,
    required this.station,
    this.meters,
    this.selected = false,
    this.pricesState,
    this.prices,
    this.trailing,
    this.onTap,
  });

  final FuelStation station;

  /// Distância do centro da busca. `null` não desenha distância.
  final double? meters;

  final bool selected;

  /// `null` não desenha a faixa de preços.
  final PricesState? pricesState;

  /// Os preços do posto quando [pricesState] é `ready`. `null` aí é posto que
  /// ninguém relatou: a faixa mostra `—` nas três colunas.
  final StationPrices? prices;

  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? Colors.blue.shade700 : Colors.grey.shade300;
    final state = pricesState;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: borderColor, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            if (state != null) _PriceStrip(state: state, prices: prices),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final suburb = station.suburb;
    final distance = meters;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          StationLogo(flag: flagOf(station)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sem bairro, o card fica com uma linha só: metade dos postos
                // do OSM não tem `addr:suburb`, e "Bairro desconhecido" em
                // metade da lista seria ruído.
                if (suburb != null)
                  Text(
                    suburb,
                    key: const Key('station-suburb'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                Text(
                  stationTitle(station),
                  key: const Key('station-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (distance != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.location_on_outlined,
              size: 18,
              color: Colors.green.shade600,
            ),
            const SizedBox(width: 2),
            Text(
              formatDistance(distance),
              key: const Key('station-distance'),
              style: const TextStyle(fontSize: 13),
            ),
          ],
          ?trailing,
        ],
      ),
    );
  }
}

/// O texto do card: o **nome** do posto. O logo já diz a bandeira.
///
/// Em ordem:
///
/// 1. o nome de verdade — sem o "| BR" do `label`, que repetiria o logo;
/// 2. o endereço, quando o OSM não tem nome **ou o "nome" só repete a
///    bandeira** (`name=Shell`, "Posto BR": 42 postos da RMF). Ao lado do logo,
///    "Shell" não diz qual Shell é; "Avenida Antônio Sales, 1340" diz;
/// 3. "Posto sem nome". Nunca a bandeira em texto ao lado do desenho dela.
///
/// Sem logo, vale o `label` de sempre: ali a bandeira em texto ("| SP") é a
/// única que aparece na tela.
///
/// Medido na RMF em 06/10/2026: 232 nomes, 50 endereços, 97 sem nada — o OSM
/// simplesmente não sabe. A rua mais próxima por consulta espacial foi testada
/// e recusada: 27 s por busca, e posto de esquina volta com cinco ruas.
String stationTitle(FuelStation station) {
  final flag = flagOf(station);
  if (flag == StationFlag.semBandeira) {
    return station.name.trim().isEmpty
        ? (station.address ?? station.label)
        : station.label;
  }

  final name = station.name.trim();
  if (name.isNotEmpty && !_onlyNamesFlag(name, station, flag)) return name;

  return station.address ?? 'Posto sem nome';
}

/// Se o nome não diz nada além da bandeira: "Shell", "Posto BR", "Petrobras".
///
/// "Posto" não conta como informação. "Posto Shell | 13 de Maio" diz mais, e é
/// nome.
bool _onlyNamesFlag(String name, FuelStation station, StationFlag flag) {
  final brand = normalizeKey(station.brand ?? '');

  return name
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .map(normalizeKey)
      .where((word) => word.isNotEmpty && word != 'posto')
      .every((word) => flag.aliases.contains(word) || word == brand);
}

/// O logo num círculo branco.
///
/// A BR preenche o círculo, como no print de referência; as outras entram
/// inteiras, com folga, porque cortadas perdem a forma.
class StationLogo extends StatelessWidget {
  const StationLogo({super.key, required this.flag, this.size = 48});

  final StationFlag flag;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('station-logo-${flag.name}'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      padding: flag.fillsCircle ? EdgeInsets.zero : EdgeInsets.all(size / 8),
      child: Image.asset(
        flag.asset,
        fit: flag.fillsCircle ? BoxFit.cover : BoxFit.contain,
        // O teste garante que todo asset existe; isto só impede que um
        // arquivo corrompido derrube a lista inteira.
        errorBuilder: (_, _, _) =>
            Icon(Icons.local_gas_station_outlined, color: Colors.grey.shade500),
      ),
    );
  }
}

class _PriceStrip extends StatelessWidget {
  const _PriceStrip({required this.state, this.prices});

  final PricesState state;
  final StationPrices? prices;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('station-prices'),
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: state == PricesState.failed
          ? Text(
              'Não foi possível carregar os preços',
              key: const Key('station-prices-failed'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final fuel in pumpFuels)
                  Expanded(child: _priceColumn(fuel)),
              ],
            ),
    );
  }

  Widget _priceColumn(SupplyFuel fuel) {
    final reported = prices?.of(fuel);
    final at = reported?.at;

    return Column(
      key: Key('station-price-${fuel.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fuel.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _fuelColor(fuel),
          ),
        ),
        const SizedBox(height: 2),
        if (state == PricesState.loading)
          // Espaço reservado, e **não** `—`: carregando não é "ninguém
          // relatou".
          Container(
            key: const Key('station-price-loading'),
            width: 56,
            height: 18,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          )
        else
          Text(
            reported == null
                ? '—'
                : CurrencyFormatterHelper.formatMoney(reported.price),
            maxLines: 1,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        // A idade de **cada** preço. Documento anterior a `pricedAt` não tem
        // data, e o preço aparece sem idade em vez de com uma emprestada.
        if (at != null)
          Text(
            relativeWhen(at),
            maxLines: 1,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
      ],
    );
  }

  static Color _fuelColor(SupplyFuel fuel) => switch (fuel) {
    SupplyFuel.gasolina => const Color(0xFFB26A00),
    SupplyFuel.etanol => Colors.green.shade800,
    SupplyFuel.diesel => Colors.blue.shade800,
    SupplyFuel.eletrico => Colors.grey.shade700,
  };
}

/// `325 m` até um quilômetro, `1,2 km` acima.
///
/// Metro a metro só importa perto: a diferença entre 3,4 e 3,5 km não muda a
/// decisão de ninguém, e "3417 m" é mais difícil de ler do que "3,4 km".
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';

  final km = meters / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}
