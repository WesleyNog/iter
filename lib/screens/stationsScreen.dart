import 'package:flutter/material.dart';
import 'package:iter/Utils/stationFilter.dart';
import 'package:iter/controller/stationController.dart';
import 'package:iter/model/stationPrices.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/services/geocoding.dart';
import 'package:iter/services/location.dart';
import 'package:iter/services/overpass.dart';
import 'package:iter/widget/placeSearch.dart';
import 'package:iter/widget/stationCard.dart';

/// Resultado da busca por postos em volta do aparelho: a lista, ou o
/// motivo de não ter dado.
///
/// `failure` é **só** problema de localização. Localização certa com a
/// Overpass fora do ar volta com `failure: null` e `stations: null` — mandar
/// "não foi possível obter sua localização" a quem tem GPS funcionando o faria
/// mexer no lugar errado.
typedef StationsSnapshot = ({
  List<NearbyStation>? stations,
  double? lat,
  double? lng,
  LocationFailure? failure,
});

/// O que "Postos da região" devolve ao formulário.
///
/// [nearMe] diz se a lista estava em volta do GPS. Em "Outra localização" a
/// posição do aparelho é a casa de quem registra, não o lugar do
/// abastecimento, e o formulário deixa `Supply.lat/lng` nulos.
class StationChoice {
  const StationChoice.picked(FuelStation this.station, {required this.nearMe})
    : typedName = null;

  const StationChoice.typed(String this.typedName, {required this.nearMe})
    : station = null;

  /// Posto da lista, com o id do OSM.
  final FuelStation? station;

  /// "Outro / não listado": só o nome, que nunca vai para `gastop`.
  final String? typedName;

  final bool nearMe;
}

/// "Postos da região": a lista de postos com logo, bairro, distância e preços.
///
/// Existe por causa de quem registra **depois**: em casa, a lista em volta do
/// GPS é a lista em volta de casa, e o posto do abastecimento não estava
/// nela. "Outra localização" recentra a busca num bairro ou endereço. Ver
/// `docs/specs/postos-da-regiao.md`.
///
/// Os carregadores são opcionais pelo mesmo motivo de `AddSupply`: em produção
/// ficam `null` e a tela usa os serviços de verdade; no teste, ela inteira roda
/// sem GPS, sem rede e sem Firestore.
class StationsScreen extends StatefulWidget {
  const StationsScreen({
    super.key,
    required this.nearby,
    required this.locate,
    this.current,
    this.stationsAround,
    this.pricesLoader,
    this.placeSearch,
    this.onOpenSettings,
  });

  /// A busca em volta do GPS **já iniciada** pelo formulário: começa quando
  /// ele abre, e ao chegar aqui a lista costuma estar pronta.
  final Future<StationsSnapshot> nearby;

  /// Busca em volta do GPS de novo — o "tentar de novo".
  final Future<StationsSnapshot> Function() locate;

  /// O que já estava escolhido, para marcar o card e preencher o nome digitado.
  final StationChoice? current;

  final Future<List<NearbyStation>?> Function(double lat, double lng)?
  stationsAround;
  final Future<Map<String, StationPrices>?> Function(List<String> ids)?
  pricesLoader;
  final PlaceSearcher? placeSearch;
  final VoidCallback? onOpenSettings;

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  final _filter = TextEditingController();
  final _typed = TextEditingController();

  /// `null` = "Minha localização". Um lugar = "Outra localização", centrada
  /// nele.
  Place? _place;

  /// O último resultado do GPS. Guardado para voltar a "Minha localização"
  /// sem perguntar ao GPS e à Overpass de novo.
  StationsSnapshot? _gps;

  bool _loading = true;
  List<NearbyStation>? _stations;
  LocationFailure? _locationFailure;

  Map<String, StationPrices>? _prices;
  PricesState _pricesState = PricesState.loading;

  bool _typing = false;

  /// Cada busca ganha um número. Resposta de uma busca que não é mais a da
  /// tela — o lugar mudou no meio — é descartada, senão a lista de casa
  /// poderia chegar por cima da lista da Maraponga.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _typed.text = widget.current?.typedName ?? '';
    _typing = widget.current?.typedName != null;
    // Sempre abre em "Minha localização": o caso comum é a bomba, e a busca
    // do GPS já veio pronta do formulário.
    _showGps(widget.nearby);
  }

  @override
  void dispose() {
    _filter.dispose();
    _typed.dispose();
    super.dispose();
  }

  bool get _nearMe => _place == null;

  // ----------------------------------------------------------- Carregar

  /// Põe a tela em "carregando" para [place] e devolve o número da busca.
  int _begin(Place? place) {
    setState(() {
      _place = place;
      _loading = true;
      _locationFailure = null;
    });
    return ++_generation;
  }

  Future<void> _showGps(Future<StationsSnapshot> search) async {
    final generation = _begin(null);

    final snapshot = await search;
    if (!mounted || generation != _generation) return;

    _gps = snapshot;
    _show(generation, snapshot.stations, failure: snapshot.failure);
  }

  Future<void> _showAround(Place place) async {
    final generation = _begin(place);

    final load =
        widget.stationsAround ??
        (lat, lng) => OverpassService.stationsNear(lat, lng);
    final stations = await load(place.lat, place.lng);
    if (!mounted || generation != _generation) return;

    _show(generation, stations);
  }

  void _show(
    int generation,
    List<NearbyStation>? stations, {
    LocationFailure? failure,
  }) {
    setState(() {
      _loading = false;
      _stations = stations;
      _locationFailure = failure;
      _prices = null;
      _pricesState = PricesState.loading;
    });

    if (stations != null && stations.isNotEmpty) {
      _loadPrices(generation, stations);
    }
  }

  Future<void> _loadPrices(int generation, List<NearbyStation> stations) async {
    final load = widget.pricesLoader ?? StationController.pricesFor;
    final prices = await load([for (final s in stations) s.station.id]);
    if (!mounted || generation != _generation) return;

    setState(() {
      _prices = prices;
      _pricesState = prices == null ? PricesState.failed : PricesState.ready;
    });
  }

  // -------------------------------------------------------------- Ações

  void _tapNearMe() {
    final gps = _gps;
    // Já tem resultado bom do GPS: volta a ele sem perguntar de novo. Falhou?
    // Tocar é tentar de novo.
    if (gps != null && gps.failure == null && gps.stations != null) {
      _showGps(Future.value(gps));
    } else {
      _showGps(widget.locate());
    }
  }

  Future<void> _tapOtherPlace() async {
    final place = await showPlaceSearch(
      context,
      // Puxa os resultados para perto da posição do aparelho; sem GPS, o
      // serviço cai em Fortaleza.
      lat: _gps?.lat,
      lng: _gps?.lng,
      search: widget.placeSearch,
    );
    if (place == null || !mounted) return;

    _showAround(place);
  }

  void _retry() {
    final place = _place;
    if (place == null) {
      _showGps(widget.locate());
    } else {
      _showAround(place);
    }
  }

  void _pick(FuelStation station) {
    Navigator.of(context).pop(StationChoice.picked(station, nearMe: _nearMe));
  }

  void _useTyped() {
    final name = _typed.text.trim();
    if (name.isEmpty) return;

    Navigator.of(context).pop(StationChoice.typed(name, nearMe: _nearMe));
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Postos da região')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _filterField(),
          const SizedBox(height: 12),
          _locationButtons(),
          const SizedBox(height: 16),
          ..._body(),
          const SizedBox(height: 12),
          _otherTile(),
        ],
      ),
    );
  }

  Widget _filterField() {
    return TextField(
      key: const Key('stations-filter'),
      controller: _filter,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar por nome, bairro ou bandeira',
        suffixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _locationButtons() {
    return Row(
      children: [
        Expanded(
          child: _LocationButton(
            key: const Key('stations-near-me'),
            label: 'Minha localização',
            icon: Icons.my_location,
            active: _nearMe,
            onTap: _tapNearMe,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LocationButton(
            key: const Key('stations-other'),
            // O lugar escolhido no próprio botão: é dali que as distâncias
            // estão sendo medidas.
            label: _place?.title ?? 'Outra localização',
            icon: Icons.chevron_right,
            active: !_nearMe,
            onTap: _tapOtherPlace,
          ),
        ),
      ],
    );
  }

  List<Widget> _body() {
    if (_loading) {
      return [
        Row(
          key: const Key('stations-loading'),
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              _nearMe
                  ? 'Procurando postos por perto...'
                  : 'Procurando postos em ${_place!.title}...',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ];
    }

    final failure = _locationFailure;
    if (failure != null) {
      return [
        _problem(
          locationFailureMessage(failure),
          icon: Icons.location_off_outlined,
          // Só quando abrir os ajustes é de fato o que resolve — oferecer
          // isso a quem tocou em "agora não" é insistência.
          settings: opensSettings(failure),
          // "Outra localização" não depende do GPS: quem negou a permissão
          // ainda escolhe da lista pelo bairro.
          hint: 'Você ainda pode buscar os postos em outra localização.',
        ),
      ];
    }

    final stations = _stations;
    if (stations == null) {
      return [
        _problem(
          'Não foi possível buscar os postos agora.',
          icon: Icons.cloud_off_outlined,
        ),
      ];
    }

    if (stations.isEmpty) {
      // Zona rural existe: "nenhum posto no raio" é resposta, não falha.
      return [
        Text(
          'Nenhum posto encontrado por aqui.',
          key: const Key('stations-empty'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ];
    }

    final visible = filterStations(stations, _filter.text);
    if (visible.isEmpty) {
      return [
        Text(
          'Nenhum posto com "${_filter.text.trim()}" por aqui.',
          key: const Key('stations-filter-empty'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(_filter.clear),
            child: const Text('Limpar busca'),
          ),
        ),
      ];
    }

    final selectedId = widget.current?.station?.id;

    return [
      for (var i = 0; i < visible.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StationCard(
            key: Key('station-item-$i'),
            station: visible[i].station,
            meters: visible[i].meters,
            selected: visible[i].station.id == selectedId,
            pricesState: _pricesState,
            prices: _prices?[visible[i].station.id],
            onTap: () => _pick(visible[i].station),
          ),
        ),
    ];
  }

  Widget _problem(
    String message, {
    required IconData icon,
    bool settings = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                key: const Key('stations-error'),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
        if (hint != null && _nearMe)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 4),
            child: Text(
              hint,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        Wrap(
          children: [
            TextButton(
              key: const Key('stations-retry'),
              onPressed: _retry,
              child: const Text('Tentar de novo'),
            ),
            if (settings)
              TextButton(
                key: const Key('stations-settings'),
                onPressed: widget.onOpenSettings ?? openLocationSettings,
                child: const Text('Abrir ajustes'),
              ),
          ],
        ),
      ],
    );
  }

  /// "Outro / não listado" — em **todos** os estados.
  ///
  /// A Overpass pode responder certinho e não ter o posto do abastecimento. O
  /// nome digitado é gravado no abastecimento e nunca vai para `gastop`.
  Widget _otherTile() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: const Key('station-other'),
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Outro / não listado'),
            onTap: () => setState(() => _typing = true),
          ),
          if (_typing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('station-typed'),
                      controller: _typed,
                      autofocus: widget.current?.typedName == null,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Nome do posto',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _useTyped(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('station-typed-confirm'),
                    onPressed: _typed.text.trim().isEmpty ? null : _useTyped,
                    child: const Text('Usar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Minha localização" / "Outra localização": o ativo fica destacado.
class _LocationButton extends StatelessWidget {
  const _LocationButton({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.blue.shade800 : Colors.black87;

    return Material(
      color: active ? Colors.blue.shade50 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: active ? Colors.blue.shade300 : Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
