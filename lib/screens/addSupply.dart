import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/dated.dart';
import 'package:iter/Utils/expenseRules.dart';
import 'package:iter/Utils/fuelEconomy.dart';
import 'package:iter/controller/stationController.dart';
import 'package:iter/controller/supplyController.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/services/location.dart';
import 'package:iter/services/overpass.dart';
import 'package:iter/widget/dataPicker.dart';
import 'package:iter/screens/stationsScreen.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/stationField.dart';
import 'package:uuid/uuid.dart';

/// Registro de abastecimento.
///
/// Os parâmetros opcionais existem para o teste montar a tela sem Firestore,
/// sem GPS e sem rede. Em produção ficam `null` e a tela usa os serviços de
/// verdade — a injeção não muda o caminho real, só o abre para inspeção.
class AddSupply extends StatefulWidget {
  const AddSupply({
    super.key,
    required this.uid,
    this.vehiclesLoader,
    this.stationsLoader,
    this.stationPicker,
    this.suppliesLoader,
    this.saver,
  });

  final String uid;

  final Future<VehiclesSnapshot> Function()? vehiclesLoader;
  final Future<StationsSnapshot> Function()? stationsLoader;

  /// Abre "Postos da região" e devolve a escolha. Em produção, a tela de
  /// verdade; no teste, uma escolha pronta — a tela tem os testes dela.
  final Future<StationChoice?> Function(
    BuildContext context,
    StationChoice? current,
  )?
  stationPicker;

  /// Abastecimentos já gravados, para medir o consumo depois de salvar.
  final Future<List<Supply>> Function()? suppliesLoader;

  /// Grava o abastecimento. Em produção, `SupplyController.save` seguido do
  /// relato em `gastop`; no teste, captura o que seria gravado.
  final Future<void> Function(String uid, Supply supply)? saver;

  @override
  State<AddSupply> createState() => _AddSupplyState();
}

class _AddSupplyState extends State<AddSupply> {
  final _formKey = GlobalKey<FormState>();

  final _value = TextEditingController();
  final _liters = TextEditingController();
  final _odometer = TextEditingController();

  List<Vehicle> _vehicles = const [];
  Vehicle? _vehicle;
  SupplyFuel _fuel = SupplyFuel.gasolina;

  /// O dia do abastecimento. Começa em hoje; quem registra no dia seguinte
  /// volta um dia — e é só o dia, ver [expenseDateFor].
  DateTime _date = DateTime.now();

  /// A busca em volta do GPS, iniciada quando o formulário abre: ao tocar em
  /// "Escolher posto" a lista costuma já estar pronta.
  late Future<StationsSnapshot> _nearby;

  /// Onde o aparelho estava, quando o GPS respondeu.
  double? _gpsLat;
  double? _gpsLng;

  StationChoice? _choice;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    _locate();
  }

  @override
  void dispose() {
    _value.dispose();
    _liters.dispose();
    _odometer.dispose();
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

  /// Começa (ou recomeça) a busca em volta do GPS.
  ///
  /// Devolve a busca para "Postos da região" usar no "tentar de novo", e a
  /// guarda aqui para a próxima abertura da tela já vir com o resultado novo.
  Future<StationsSnapshot> _locate() {
    final loader = widget.stationsLoader ?? _realStations;
    final search = loader();
    _nearby = search;

    search.then((snapshot) {
      if (!mounted || _nearby != search) return;
      _gpsLat = snapshot.lat;
      _gpsLng = snapshot.lng;
    }).ignore();

    return search;
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
      // Overpass fora do ar **não** é falha de localização: o GPS respondeu.
      // `stations: null` com `failure: null` faz a tela dizer "não foi possível
      // buscar os postos" em vez de mandá-lo mexer no GPS que está certo.
      failure: null,
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
    final clock = DateTime.now();
    final now = clock.toIso8601String();

    // Em "Outra localização" o GPS é a casa de quem registra, não o lugar do
    // abastecimento — e o posto escolhido já carrega as próprias coordenadas.
    final nearMe = _choice?.nearMe ?? true;
    final lat = nearMe ? _gpsLat : null;
    final lng = nearMe ? _gpsLng : null;
    final typed = _choice?.typedName;

    return Supply(
      id: const Uuid().v4(),
      vehicleId: _vehicle?.id,
      value: _valueOf ?? 0,
      liters: _litersOf,
      fuel: _fuel,
      odometer: parseKm(_odometer.text),
      // Posto digitado à mão fica sem id, e é isso que impede
      // `StationController` de sujar a coleção global com ele.
      station:
          _choice?.station ??
          (typed == null
              ? null
              : FuelStation(id: '', name: typed, lat: lat ?? 0, lng: lng ?? 0)),
      lat: lat,
      lng: lng,
      // O dia escolhido, não o do registro: o gasto de ontem é de ontem no
      // card de gastos, e o relato de preço leva a idade verdadeira.
      date: expenseDateFor(_date, now: clock),
      createdAt: now,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final supply = _draft();

    setState(() => _saving = true);
    EasyLoading.show(status: 'Salvando abastecimento...').ignore();

    try {
      await (widget.saver ?? _persist)(widget.uid, supply);

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

  static Future<void> _persist(String uid, Supply supply) async {
    await SupplyController.save(uid, supply);
    // Guardado dentro do controller: só relata com posto da fonte, litros e
    // data legível — e o de outro dia não apaga um preço mais novo.
    await StationController.report(supply, uid);
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
            _dateField(),
            const SizedBox(height: 16),
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
            StationField(choice: _choice, onTap: _pickStation),
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

  Future<void> _pickStation() async {
    final pick = widget.stationPicker ?? _openStations;
    final choice = await pick(context, _choice);

    // Voltar sem escolher mantém o que estava.
    if (choice == null || !mounted) return;
    setState(() => _choice = choice);
  }

  Future<StationChoice?> _openStations(
    BuildContext context,
    StationChoice? current,
  ) {
    return Navigator.of(context).push<StationChoice>(
      MaterialPageRoute(
        builder: (_) => StationsScreen(
          nearby: _nearby,
          locate: _locate,
          current: current,
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

  /// O dia, nunca no futuro.
  ///
  /// Só o dia: quem registra depois lembra do dia, raramente da hora — e a
  /// hora que falta é decidida por [expenseDateFor].
  Widget _dateField() {
    return InkWell(
      key: const Key('supply-date'),
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        final now = DateTime.now();
        showCupertinoDatePicker(
          context,
          _date,
          (picked) => setState(() => _date = picked),
          // Hoje, até o último instante: com `now` cru, escolher hoje depois
          // de girar a roleta poderia cair um segundo depois do máximo.
          maximumDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Data',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: Text(_dateLabel(_date, DateTime.now())),
      ),
    );
  }

  /// `06/10/2026 (hoje)`, `05/10/2026 (ontem)` ou só a data.
  static String _dateLabel(DateTime date, DateTime now) {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final text =
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';

    if (day == today) return '$text (hoje)';
    if (day == DateTime(now.year, now.month, now.day - 1)) return '$text (ontem)';
    return text;
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
