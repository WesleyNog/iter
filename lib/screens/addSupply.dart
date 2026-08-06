import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/expenseRules.dart';
import 'package:iter/Utils/fuelEconomy.dart';
import 'package:iter/controller/stationController.dart';
import 'package:iter/controller/supplyController.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/services/location.dart';
import 'package:iter/services/overpass.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/stationPicker.dart';
import 'package:uuid/uuid.dart';

/// Resultado da busca por postos: a lista, ou o motivo de não ter dado.
typedef StationsSnapshot = ({
  List<NearbyStation>? stations,
  double? lat,
  double? lng,
  LocationFailure? failure,
});

/// Registro de abastecimento.
///
/// Os dois carregadores existem para o teste montar a tela sem Firestore, sem
/// GPS e sem rede. Em produção ficam `null` e a tela usa os serviços de
/// verdade — a injeção não muda o caminho real, só o abre para inspeção.
class AddSupply extends StatefulWidget {
  const AddSupply({
    super.key,
    required this.uid,
    this.vehiclesLoader,
    this.stationsLoader,
    this.suppliesLoader,
  });

  final String uid;

  final Future<VehiclesSnapshot> Function()? vehiclesLoader;
  final Future<StationsSnapshot> Function()? stationsLoader;

  /// Abastecimentos já gravados, para medir o consumo depois de salvar.
  final Future<List<Supply>> Function()? suppliesLoader;

  @override
  State<AddSupply> createState() => _AddSupplyState();
}

class _AddSupplyState extends State<AddSupply> {
  final _formKey = GlobalKey<FormState>();

  final _value = TextEditingController();
  final _liters = TextEditingController();
  final _odometer = TextEditingController();
  final _typedStation = TextEditingController();

  List<Vehicle> _vehicles = const [];
  Vehicle? _vehicle;
  SupplyFuel _fuel = SupplyFuel.gasolina;

  List<NearbyStation>? _stations;
  FuelStation? _station;
  bool _otherStation = false;
  bool _loadingStations = false;
  LocationFailure? _locationFailure;
  double? _lat;
  double? _lng;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    _loadStations();
  }

  @override
  void dispose() {
    _value.dispose();
    _liters.dispose();
    _odometer.dispose();
    _typedStation.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    final loader = widget.vehiclesLoader ?? _realVehicles;

    try {
      final snapshot = await loader();
      if (!mounted) return;

      setState(() {
        _vehicles = snapshot.all;
        _vehicle = snapshot.active;
        // Veículo de combustível único decide sozinho; flex devolve `null` e
        // o seletor aparece.
        _fuel = SupplyFuel.fromVehicle(snapshot.active?.fuel) ?? _fuel;
      });
    } catch (e) {
      debugPrint('Não foi possível ler os veículos: $e');
    }
  }

  Future<VehiclesSnapshot> _realVehicles() async {
    final all = await VehicleController.fetchAll(widget.uid);
    final active = await VehicleController.fetchActive(widget.uid);
    return (all: all, active: active);
  }

  Future<void> _loadStations() async {
    setState(() {
      _loadingStations = true;
      _locationFailure = null;
    });

    final loader = widget.stationsLoader ?? _realStations;
    final snapshot = await loader();
    if (!mounted) return;

    setState(() {
      _loadingStations = false;
      _stations = snapshot.stations;
      _lat = snapshot.lat;
      _lng = snapshot.lng;
      _locationFailure = snapshot.failure;
    });
  }

  Future<StationsSnapshot> _realStations() async {
    final position = await currentLocation();
    final lat = position.lat;
    final lng = position.lng;

    if (lat == null || lng == null) {
      return (
        stations: null,
        lat: null,
        lng: null,
        failure: position.failure ?? LocationFailure.failed,
      );
    }

    final stations = await OverpassService.stationsNear(lat, lng);
    return (
      stations: stations,
      lat: lat,
      lng: lng,
      // A Overpass devolve `null` quando não deu para saber; para a tela isso
      // é a mesma classe de problema que localização falhada.
      failure: stations == null ? LocationFailure.failed : null,
    );
  }

  // ------------------------------------------------------------- Números

  double? get _valueOf {
    final parsed = CurrencyFormatterHelper.parseMoneyToDouble(_value.text);
    return parsed > 0 ? parsed : null;
  }

  /// Litros aceita `39,750` e `39.750`: são valores abaixo de cem, então um
  /// ponto ali é decimal, nunca separador de milhar.
  double? get _litersOf {
    final parsed = parseRate(_liters.text);
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  double? get _pricePerLiter {
    final value = _valueOf;
    final liters = _litersOf;
    if (value == null || liters == null) return null;

    return value / liters;
  }

  bool get _askFuel => _vehicle == null
      ? false
      : SupplyFuel.fromVehicle(_vehicle!.fuel) == null;

  // -------------------------------------------------------------- Salvar

  Supply _draft() {
    final now = DateTime.now().toIso8601String();

    return Supply(
      id: const Uuid().v4(),
      vehicleId: _vehicle?.id,
      value: _valueOf ?? 0,
      liters: _litersOf,
      fuel: _fuel,
      odometer: parseKm(_odometer.text),
      // Posto digitado à mão fica sem id, e é isso que impede
      // `StationController` de sujar a coleção global com ele.
      station: _otherStation
          ? (_typedStation.text.trim().isEmpty
                ? null
                : FuelStation(
                    id: '',
                    name: _typedStation.text.trim(),
                    lat: _lat ?? 0,
                    lng: _lng ?? 0,
                  ))
          : _station,
      lat: _lat,
      lng: _lng,
      date: now,
      createdAt: now,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final supply = _draft();

    setState(() => _saving = true);
    EasyLoading.show(status: 'Salvando abastecimento...').ignore();

    try {
      await SupplyController.save(widget.uid, supply);
      // Guardado dentro do controller: só relata com posto da fonte e litros.
      await StationController.report(supply, widget.uid);

      if (!mounted) return;
      EasyLoading.dismiss().ignore();

      await _offerVehicleUpdate(supply);

      if (!mounted) return;
      showNotification(
        context: context,
        type: 'success',
        msg: 'Abastecimento registrado!',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Erro ao salvar o abastecimento: $e');
      EasyLoading.dismiss().ignore();
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível salvar. Tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// O consumo medido deste veículo com este combustível, depois de salvar.
  Future<EconomyResult?> _economyFor(Vehicle vehicle, SupplyFuel fuel) async {
    try {
      final loader = widget.suppliesLoader ??
          () => SupplyController.fetchAll(widget.uid);

      return measuredEconomy(await loader(), vehicleId: vehicle.id)[fuel];
    } catch (e) {
      debugPrint('Não foi possível medir o consumo: $e');
      return null;
    }
  }

  /// Pergunta — nunca decide — se o cadastro do veículo deve receber os
  /// números medidos.
  ///
  /// **Um diálogo para os dois.** Preço do litro e consumo saem do mesmo
  /// abastecimento e respondem a mesma coisa — "o cadastro está desatualizado?"
  /// —, e dois modais empilhados depois de salvar é atrito onde deveria haver
  /// alívio.
  Future<void> _offerVehicleUpdate(Supply supply) async {
    final vehicle = _vehicle;
    if (vehicle == null) return;

    final price = shouldOfferPriceUpdate(vehicle, supply)
        ? supply.pricePerLiter
        : null;

    final result = await _economyFor(vehicle, supply.fuel);
    final economy = result?.economy;
    final consumption =
        (economy != null && shouldOfferConsumptionUpdate(vehicle, economy))
        ? economy.kmPerLiter
        : null;

    if (!mounted) return;

    // Sem nada a corrigir, o consumo medido ainda é notícia boa: aparece como
    // aviso em vez de sumir.
    if (price == null && consumption == null) {
      _reportEconomy(supply, result);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Atualizar o cadastro?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (price != null)
              _updateLine(
                'Preço do litro',
                '${formatRate(price)}/L',
                vehicle.fuelPrice == null
                    ? null
                    : '${CurrencyFormatterHelper.formatMoney(vehicle.fuelPrice!)}/L',
              ),
            if (consumption != null)
              _updateLine(
                'Consumo (${supply.fuel.label})',
                formatEconomy(consumption),
                vehicle.consumption == null
                    ? null
                    : formatEconomy(vehicle.consumption!),
              ),
            const SizedBox(height: 12),
            Text(
              'Isso muda o custo por km das próximas rotas. '
              'As já concluídas não mudam.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Agora não'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await VehicleController.save(
        widget.uid,
        vehicle.copyWith(
          // `??` mantém o que já estava: aceitar não pode apagar o campo que
          // não foi oferecido.
          fuelPrice: price ?? vehicle.fuelPrice,
          consumption: consumption ?? vehicle.consumption,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );
    } catch (e) {
      debugPrint('Não foi possível atualizar o veículo: $e');
    }
  }

  Widget _updateLine(String label, String medido, String? atual) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text(
            atual == null ? medido : '$atual  →  $medido',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Consumo medido, ou o que falta para medir.
  ///
  /// A dica do que falta só aparece quando ele **informou o KM** desta vez: quem
  /// não usa o campo não precisa ser cobrado a cada abastecimento.
  void _reportEconomy(Supply supply, EconomyResult? result) {
    if (result == null) return;

    final economy = result.economy;
    if (economy != null) {
      showNotification(
        context: context,
        type: 'info',
        msg: 'Consumo medido: ${formatEconomy(economy.kmPerLiter)} '
            '(${supply.fuel.label}).',
      );
      return;
    }

    final gap = result.gap;
    if (gap == null || supply.odometer == null) return;

    showNotification(
      context: context,
      type: 'info',
      msg: economyGapMessage(gap, result.missing),
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abastecimento')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_vehicles.isNotEmpty) ...[_vehiclePicker(), const SizedBox(height: 16)],
            _valueField(),
            const SizedBox(height: 8),
            _litersField(),
            const SizedBox(height: 12),
            _priceCard(),
            if (_askFuel) ...[const SizedBox(height: 16), _fuelSelector()],
            const SizedBox(height: 16),
            _odometerField(),
            const SizedBox(height: 24),
            _sectionTitle('Posto'),
            StationPicker(
              stations: _stations,
              loading: _loadingStations,
              failureMessage: _locationFailure == null
                  ? null
                  : locationFailureMessage(_locationFailure!),
              canOpenSettings:
                  _locationFailure != null && opensSettings(_locationFailure!),
              selected: _station,
              otherSelected: _otherStation,
              onSelect: (station) => setState(() {
                _station = station;
                _otherStation = station == null;
              }),
              typedName: _typedStation,
              onTypedName: (_) => setState(() {}),
              onRetry: _loadStations,
              // Sem isto o `canOpenSettings` acima não valia nada: o botão só
              // aparece quando há para onde ir, e quem bloqueou a permissão de
              // vez ficava sem saída nenhuma.
              onOpenSettings: openLocationSettings,
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              child: FilledButton(
                key: const Key('supply-save'),
                onPressed: _saving ? null : _save,
                child: const Text('REGISTRAR ABASTECIMENTO'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  );

  Widget _vehiclePicker() {
    return DropdownButtonFormField<String>(
      key: const Key('supply-vehicle'),
      initialValue: _vehicle?.id,
      decoration: const InputDecoration(
        labelText: 'Veículo',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final vehicle in _vehicles)
          DropdownMenuItem(value: vehicle.id, child: Text(vehicle.displayName)),
      ],
      onChanged: (id) => setState(() {
        _vehicle = _vehicles.firstWhere((v) => v.id == id);
        _fuel = SupplyFuel.fromVehicle(_vehicle!.fuel) ?? _fuel;
      }),
    );
  }

  Widget _valueField() {
    return TextFormField(
      key: const Key('supply-value'),
      controller: _value,
      keyboardType: TextInputType.number,
      inputFormatters: CurrencyFormatterHelper.getCurrencyFormatter(),
      decoration: const InputDecoration(
        labelText: 'Valor do abastecimento',
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
      validator: (_) => _valueOf == null ? 'Informe o valor' : null,
    );
  }

  Widget _litersField() {
    return TextFormField(
      key: const Key('supply-liters'),
      controller: _liters,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: const InputDecoration(
        labelText: 'Litros (opcional)',
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  /// O número que ele confere com o painel da bomba.
  ///
  /// ReadOnly de propósito: quem calcula é o app. Deixar digitável convidaria a
  /// corrigir o resultado em vez de conferir a conta — e aí o campo deixaria de
  /// servir para o que existe.
  Widget _priceCard() {
    final price = _pricePerLiter;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Preço do litro',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            // `—` sem litros: o app não sabe, e não vai fingir que é zero.
            price == null ? '—' : '${formatRate(price)}/L',
            key: const Key('supply-price'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fuelSelector() {
    // Só aparece em veículo flex: nos outros o combustível vem do cadastro, e
    // perguntar seria pedir para errar.
    return SegmentedButton<SupplyFuel>(
      key: const Key('supply-fuel'),
      segments: const [
        ButtonSegment(value: SupplyFuel.gasolina, label: Text('Gasolina')),
        ButtonSegment(value: SupplyFuel.etanol, label: Text('Etanol')),
      ],
      selected: {_fuel},
      onSelectionChanged: (selection) =>
          setState(() => _fuel = selection.first),
    );
  }

  Widget _odometerField() {
    return TextFormField(
      key: const Key('supply-odometer'),
      controller: _odometer,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: const InputDecoration(
        labelText: 'KM do painel (opcional)',
        helperText: 'Com dois abastecimentos seguidos, sai o consumo real',
        border: OutlineInputBorder(),
      ),
    );
  }
}
