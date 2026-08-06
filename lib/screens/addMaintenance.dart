import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/expenseRules.dart';
import 'package:iter/controller/maintenanceController.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:uuid/uuid.dart';

/// Registro de manutenção.
///
/// Sem API e sem coleção global, ao contrário do abastecimento: tudo é entrada
/// manual e nada sai do documento do usuário.
///
/// O carregador de veículos é injetável para o teste montar a tela sem
/// Firestore — mesma costura de `AddSupply`.
class AddMaintenance extends StatefulWidget {
  const AddMaintenance({super.key, required this.uid, this.vehiclesLoader});

  final String uid;
  final Future<VehiclesSnapshot> Function()? vehiclesLoader;

  @override
  State<AddMaintenance> createState() => _AddMaintenanceState();
}

class _AddMaintenanceState extends State<AddMaintenance> {
  final _formKey = GlobalKey<FormState>();

  final _value = TextEditingController();
  final _workshop = TextEditingController();
  final _description = TextEditingController();
  final _odometer = TextEditingController();

  List<Vehicle> _vehicles = const [];
  Vehicle? _vehicle;

  MaintenanceItem _item = MaintenanceItem.pneu;
  MaintenanceAction _action = MaintenanceAction.substituicao;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  @override
  void dispose() {
    _value.dispose();
    _workshop.dispose();
    _description.dispose();
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

  double? get _valueOf {
    final parsed = CurrencyFormatterHelper.parseMoneyToDouble(_value.text);
    return parsed > 0 ? parsed : null;
  }

  Maintenance _draft() {
    final now = DateTime.now().toIso8601String();
    String? trimmed(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    return Maintenance(
      id: const Uuid().v4(),
      vehicleId: _vehicle?.id,
      item: _item,
      action: _action,
      value: _valueOf ?? 0,
      workshop: trimmed(_workshop),
      description: trimmed(_description),
      odometer: parseKm(_odometer.text),
      date: now,
      createdAt: now,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final maintenance = _draft();

    setState(() => _saving = true);
    EasyLoading.show(status: 'Salvando manutenção...').ignore();

    try {
      await MaintenanceController.save(widget.uid, maintenance);

      if (!mounted) return;
      EasyLoading.dismiss().ignore();

      await _offerPartUpdate(maintenance);

      if (!mounted) return;
      showNotification(
        context: context,
        type: 'success',
        msg: 'Manutenção registrada!',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Erro ao salvar a manutenção: $e');
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

  /// Pergunta — nunca decide — se o preço da peça no cadastro deve virar o que
  /// ele acabou de pagar.
  ///
  /// A divisão aparece por extenso porque a conta assume que ele trocou o jogo
  /// inteiro. Quem trocou dois dos quatro pneus vê `÷ 4` e recusa.
  Future<void> _offerPartUpdate(Maintenance maintenance) async {
    final vehicle = _vehicle;
    if (!shouldOfferPartUpdate(vehicle, maintenance)) return;

    final unit = unitPriceFor(vehicle!, maintenance)!;
    final part = matchingPart(vehicle, maintenance.item)!;
    final current = part.price;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${maintenance.item.label} — '
            '${CurrencyFormatterHelper.formatMoney(maintenance.value)}'),
        content: Text(
          [
            if (part.quantity > 1)
              '${CurrencyFormatterHelper.formatMoney(maintenance.value)} ÷ '
                  '${part.quantity} = '
                  '${CurrencyFormatterHelper.formatMoney(unit)} cada',
            if (current == null)
              'A peça "${part.name}" do ${vehicle.displayName} está sem preço. '
                  'Usar este?'
            else
              'A peça "${part.name}" do ${vehicle.displayName} está com '
                  '${CurrencyFormatterHelper.formatMoney(current)}. Atualizar?',
            'Isso muda o custo por km das próximas rotas.',
          ].join('\n\n'),
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
        withPartPrice(vehicle, maintenance.item, unit).copyWith(
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );
    } catch (e) {
      debugPrint('Não foi possível atualizar o preço da peça: $e');
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manutenção')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_vehicles.isNotEmpty) ...[
              _vehiclePicker(),
              const SizedBox(height: 16),
            ],
            _itemPicker(),
            const SizedBox(height: 16),
            _actionAndValue(),
            const SizedBox(height: 16),
            _workshopField(),
            const SizedBox(height: 8),
            _descriptionField(),
            const SizedBox(height: 8),
            _odometerField(),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              child: FilledButton(
                key: const Key('maintenance-save'),
                onPressed: _saving ? null : _save,
                child: const Text('REGISTRAR MANUTENÇÃO'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehiclePicker() {
    return DropdownButtonFormField<String>(
      key: const Key('maintenance-vehicle'),
      initialValue: _vehicle?.id,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Veículo',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final vehicle in _vehicles)
          DropdownMenuItem(value: vehicle.id, child: Text(vehicle.displayName)),
      ],
      onChanged: (id) =>
          setState(() => _vehicle = _vehicles.firstWhere((v) => v.id == id)),
    );
  }

  Widget _itemPicker() {
    return DropdownButtonFormField<MaintenanceItem>(
      key: const Key('maintenance-item'),
      initialValue: _item,
      // Sem isto o dropdown se dimensiona pelo maior item ("Pastilha de freio")
      // e estoura para a direita em tela estreita — o mesmo defeito que o
      // Status da tela de rota tinha.
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'O que passou pela manutenção',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final item in MaintenanceItem.values)
          DropdownMenuItem(value: item, child: Text(item.label)),
      ],
      onChanged: (item) => setState(() => _item = item ?? _item),
    );
  }

  /// Toggle e valor na mesma linha, como pedido.
  ///
  /// Os dois em `Expanded` para caber em tela estreita: o `SegmentedButton`
  /// encolhe em vez de estourar, e há teste em 360 px de largura garantindo.
  Widget _actionAndValue() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 5,
          child: SegmentedButton<MaintenanceAction>(
            key: const Key('maintenance-action'),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            showSelectedIcon: false,
            segments: [
              for (final action in MaintenanceAction.values)
                ButtonSegment(value: action, label: Text(action.label)),
            ],
            selected: {_action},
            onSelectionChanged: (selection) =>
                setState(() => _action = selection.first),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: TextFormField(
            key: const Key('maintenance-value'),
            controller: _value,
            keyboardType: TextInputType.number,
            inputFormatters: CurrencyFormatterHelper.getCurrencyFormatter(),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Valor',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (_) => _valueOf == null ? 'Informe o valor' : null,
          ),
        ),
      ],
    );
  }

  Widget _workshopField() {
    return TextFormField(
      key: const Key('maintenance-workshop'),
      controller: _workshop,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Oficina (opcional)',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _descriptionField() {
    return TextFormField(
      key: const Key('maintenance-description'),
      controller: _description,
      textCapitalization: TextCapitalization.sentences,
      maxLines: 3,
      minLines: 2,
      decoration: const InputDecoration(
        labelText: 'Descrição (opcional)',
        alignLabelWithHint: true,
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _odometerField() {
    return TextFormField(
      key: const Key('maintenance-odometer'),
      controller: _odometer,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: const InputDecoration(
        labelText: 'KM do painel (opcional)',
        helperText: 'Serve para o lembrete da próxima troca',
        border: OutlineInputBorder(),
      ),
    );
  }
}
