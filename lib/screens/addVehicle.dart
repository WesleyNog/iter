import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iter/Utils/carImage.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/vehicleCost.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/services/fipe.dart';
import 'package:iter/services/imagin.dart';
import 'package:iter/widget/fipePicker.dart';
import 'package:iter/widget/partsEditor.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/vehicleThumb.dart' show decodePhoto;
import 'package:uuid/uuid.dart';

/// Cadastro e edição de veículo — os dois na mesma tela, como `AddIter` faz.
///
/// Passar um [vehicle] preenche os campos e salva com o **mesmo id**, então o
/// `set` do controller substitui o documento em vez de criar outro.
class AddVehicle extends StatefulWidget {
  const AddVehicle({super.key, required this.uid, this.vehicle});

  final String uid;

  /// Veículo existente = modo edição. `null` = cadastro novo.
  final Vehicle? vehicle;

  bool get isEditing => vehicle != null;

  @override
  State<AddVehicle> createState() => _AddVehicleState();
}

class _AddVehicleState extends State<AddVehicle> {
  final _formKey = GlobalKey<FormState>();

  final _nickname = TextEditingController();
  final _fuelPrice = TextEditingController();
  final _consumption = TextEditingController();

  VehicleType _type = VehicleType.carro;
  FuelType _fuel = FuelType.flex;

  FipeItem? _brand;
  FipeItem? _model;
  FipeItem? _year;

  /// Imagem já valendo — o que vai para o documento.
  String? _imageUrl;
  String? _photoBase64;

  /// Render que a CDN devolveu e o usuário **ainda não confirmou**.
  ///
  /// Fica separado de [_imageUrl] de propósito: enquanto ninguém disse que é
  /// esse o carro, nada é gravado. A CDN responde "achei" até quando entrega o
  /// veículo errado, então a confirmação é o único filtro que sobra.
  String? _pendingImageUrl;

  bool _checkingImage = false;
  bool _saving = false;

  late List<MaintenancePart> _parts;

  @override
  void initState() {
    super.initState();

    final existing = widget.vehicle;
    if (existing != null) {
      _fillFrom(existing);
    } else {
      // Abre com os números da planilha: cadastrar sem tocar em nada já
      // reproduz o que ele usa hoje.
      _parts = Vehicle.defaultParts(VehicleType.carro);
      _fuelPrice.text = CurrencyFormatterHelper.formatDoubleToMoney(7.0);
      _consumption.text = '10';
    }
  }

  void _fillFrom(Vehicle v) {
    _type = v.type;
    _fuel = v.fuel;
    _brand = FipeItem(code: v.brandCode, name: v.brandName);
    _model = FipeItem(code: v.modelCode, name: v.modelName);
    _year = v.yearCode == null
        ? null
        : FipeItem(code: v.yearCode!, name: v.year?.toString() ?? v.yearCode!);
    _nickname.text = v.nickname ?? '';
    _fuelPrice.text = v.fuelPrice == null
        ? ''
        : CurrencyFormatterHelper.formatDoubleToMoney(v.fuelPrice!);
    _consumption.text = v.consumption?.toString().replaceAll('.', ',') ?? '';
    // Editando, a imagem já foi confirmada uma vez: não perguntar de novo.
    _imageUrl = v.imageUrl;
    _photoBase64 = v.photoBase64;
    _parts = v.parts;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _fuelPrice.dispose();
    _consumption.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- FIPE

  Future<void> _pickBrand() async {
    final chosen = await showFipePicker(
      context,
      title: 'Marca',
      hint: 'Buscar marca...',
      load: () => FipeService.brands(_type),
    );
    if (chosen == null) return;

    setState(() {
      _brand = chosen;
      // Modelo e ano pertencem à marca anterior; manter seria oferecer um
      // Fiorino dentro de uma Honda.
      _model = null;
      _year = null;
      _clearSuggestedImage();
    });
  }

  Future<void> _pickModel() async {
    final brand = _brand;
    if (brand == null) return;

    final chosen = await showFipePicker(
      context,
      title: 'Modelo',
      hint: 'Buscar modelo...',
      // Marca digitada à mão não tem código: sem ele a FIPE não lista modelos,
      // e o picker cai direto no campo de texto livre.
      load: () => brand.code.isEmpty
          ? Future.value(null)
          : FipeService.models(_type, brand.code),
    );
    if (chosen == null) return;

    setState(() {
      _model = chosen;
      _year = null;
    });

    await _suggestImage();
  }

  Future<void> _pickYear() async {
    final brand = _brand;
    final model = _model;
    if (brand == null || model == null) return;

    final chosen = await showFipePicker(
      context,
      title: 'Ano',
      hint: 'Buscar ano...',
      load: () => brand.code.isEmpty || model.code.isEmpty
          ? Future.value(null)
          : FipeService.years(_type, brand.code, model.code),
    );
    if (chosen == null) return;

    setState(() => _year = chosen);
  }

  // --------------------------------------------------------------- Imagem

  void _clearSuggestedImage() {
    _pendingImageUrl = null;
    if (_photoBase64 == null) _imageUrl = null;
  }

  /// Busca um render e **propõe** — nunca grava sozinho.
  Future<void> _suggestImage() async {
    // Foto do dono ganha do render: quem já escolheu a própria foto não quer
    // ser interrompido com um desenho genérico.
    if (_photoBase64 != null) return;

    final url = carImageUrl(
      type: _type,
      brandName: _brand?.name ?? '',
      modelName: _model?.name ?? '',
    );
    if (url == null) return; // moto, ou nome de onde não sai família

    setState(() => _checkingImage = true);
    final has = await imaginHasImage(url);
    if (!mounted) return;

    setState(() {
      _checkingImage = false;
      // `true` só diz que existe **alguma** imagem. Se nem isso, não há o que
      // perguntar.
      _pendingImageUrl = has == true ? url : null;
    });
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      // O próprio image_picker redimensiona: sem `maxWidth` uma foto de celular
      // moderno passa de 5 MB e não caberia no documento.
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 70,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      // Limite do documento do Firestore é 1 MB e o veículo tem outros campos.
      if (bytes.lengthInBytes > 700 * 1024) {
        showNotification(
          context: context,
          type: 'error',
          msg: 'Foto muito grande. Tente outra.',
        );
        return;
      }

      setState(() {
        _photoBase64 = base64Encode(bytes);
        // A foto do dono vence: guardar as duas deixaria ambíguo o que mostrar.
        _imageUrl = null;
        _pendingImageUrl = null;
      });
    } catch (e) {
      debugPrint('Erro ao escolher a foto: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível abrir a foto.',
      );
    }
  }

  // --------------------------------------------------------------- Salvar

  double? get _fuelPriceValue {
    final value = CurrencyFormatterHelper.parseMoneyToDouble(_fuelPrice.text);
    return value > 0 ? value : null;
  }

  double? get _consumptionValue => parseRate(_consumption.text);

  /// O veículo como está na tela agora — usado pelo rodapé e pelo salvamento,
  /// para os dois nunca discordarem.
  Vehicle get _draft => Vehicle(
    id: widget.vehicle?.id ?? '',
    type: _type,
    brandCode: _brand?.code ?? '',
    brandName: _brand?.name ?? '',
    modelCode: _model?.code ?? '',
    modelName: _model?.name ?? '',
    yearCode: _year?.code,
    year: int.tryParse(_year?.name.split(' ').first ?? ''),
    nickname: _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
    fuel: _fuel,
    fuelPrice: _fuelPriceValue,
    consumption: _consumptionValue,
    imageUrl: _imageUrl,
    photoBase64: _photoBase64,
    parts: _parts,
    createdAt: widget.vehicle?.createdAt ?? '',
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_brand == null || _model == null) {
      showNotification(
        context: context,
        type: 'error',
        msg: 'Escolha a marca e o modelo do veículo.',
      );
      return;
    }

    final now = DateTime.now().toIso8601String();
    final vehicle = Vehicle(
      id: widget.vehicle?.id ?? const Uuid().v4(),
      type: _type,
      brandCode: _brand!.code,
      brandName: _brand!.name,
      modelCode: _model!.code,
      modelName: _model!.name,
      yearCode: _year?.code,
      year: int.tryParse(_year?.name.split(' ').first ?? ''),
      nickname: _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
      fuel: _fuel,
      fuelPrice: _fuelPriceValue,
      consumption: _consumptionValue,
      imageUrl: _imageUrl,
      photoBase64: _photoBase64,
      parts: _parts,
      createdAt: widget.vehicle?.createdAt ?? now,
      updatedAt: now,
    );

    setState(() => _saving = true);
    EasyLoading.show(status: 'Salvando veículo...').ignore();

    try {
      await VehicleController.save(widget.uid, vehicle);
      // O primeiro veículo vira o ativo sozinho: pedir mais um toque para usar
      // o único carro que existe seria cerimônia.
      await VehicleController.ensureActive(widget.uid);

      if (!mounted) return;
      showNotification(
        context: context,
        type: 'success',
        msg: widget.isEditing
            ? 'Veículo atualizado!'
            : 'Veículo cadastrado!',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Erro ao salvar o veículo: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível salvar. Tente novamente.',
      );
    } finally {
      EasyLoading.dismiss().ignore();
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar veículo' : 'Novo veículo'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _imageHeader(),
            const SizedBox(height: 16),
            _typeSelector(),
            const SizedBox(height: 16),
            _pickerTile(
              key: const Key('vehicle-brand'),
              label: 'Marca',
              value: _brand?.name,
              onTap: _pickBrand,
            ),
            _pickerTile(
              key: const Key('vehicle-model'),
              label: 'Modelo',
              value: _model?.name,
              enabled: _brand != null,
              onTap: _pickModel,
            ),
            _pickerTile(
              key: const Key('vehicle-year'),
              label: 'Ano',
              value: _year?.name,
              enabled: _model != null,
              onTap: _pickYear,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('vehicle-nickname'),
              controller: _nickname,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Apelido (opcional)',
                hintText: 'Fiorino do trabalho',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Combustível'),
            _fuelBlock(),
            const SizedBox(height: 24),
            _sectionTitle('Provisão de peças'),
            Text(
              'Preço da peça dividido pelos quilômetros que ela dura.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            PartsEditor(
              parts: _parts,
              onChanged: (parts) => setState(() => _parts = parts),
            ),
            const SizedBox(height: 16),
            _totalCard(),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton(
                key: const Key('vehicle-save'),
                onPressed: _saving ? null : _save,
                child: Text(
                  widget.isEditing ? 'SALVAR ALTERAÇÕES' : 'SALVAR VEÍCULO',
                ),
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

  Widget _imageHeader() {
    final pending = _pendingImageUrl;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 170,
            width: double.infinity,
            color: Colors.grey.shade100,
            child: _imageContent(pending),
          ),
        ),
        if (pending != null) ...[
          const SizedBox(height: 8),
          const Text('É esse o seu carro?'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                key: const Key('vehicle-image-confirm'),
                onPressed: () => setState(() {
                  _imageUrl = pending;
                  _pendingImageUrl = null;
                }),
                child: const Text('Sim'),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('vehicle-image-photo'),
                onPressed: _pickPhoto,
                child: const Text('Usar minha foto'),
              ),
            ],
          ),
        ] else
          TextButton.icon(
            key: const Key('vehicle-photo'),
            onPressed: _pickPhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(
              _photoBase64 == null ? 'Usar minha foto' : 'Trocar a foto',
            ),
          ),
      ],
    );
  }

  Widget _imageContent(String? pending) {
    if (_checkingImage) {
      return const Center(child: CircularProgressIndicator());
    }

    // `decodePhoto` e não `base64Decode` direto: editar um veículo cujo campo
    // esteja corrompido derrubaria a tela antes de qualquer errorBuilder.
    final photo = decodePhoto(_photoBase64);
    if (photo != null) {
      return Image.memory(
        photo,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _silhouette(),
      );
    }

    final url = pending ?? _imageUrl;
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        // Rede caindo no meio não pode deixar um quadrado quebrado na tela.
        errorBuilder: (_, _, _) => _silhouette(),
      );
    }

    return _silhouette();
  }

  Widget _silhouette() => Center(
    child: Icon(
      _type == VehicleType.moto
          ? Icons.two_wheeler_outlined
          : Icons.directions_car_outlined,
      size: 64,
      color: Colors.grey.shade400,
    ),
  );

  Widget _typeSelector() {
    return SegmentedButton<VehicleType>(
      segments: const [
        ButtonSegment(
          value: VehicleType.carro,
          label: Text('Carro'),
          icon: Icon(Icons.directions_car_outlined),
        ),
        ButtonSegment(
          value: VehicleType.moto,
          label: Text('Moto'),
          icon: Icon(Icons.two_wheeler_outlined),
        ),
      ],
      selected: {_type},
      onSelectionChanged: (selection) {
        final type = selection.first;
        if (type == _type) return;

        setState(() {
          _type = type;
          // Marca e modelo vêm de coleções diferentes na FIPE: um Fiorino não
          // existe na lista de motos.
          _brand = null;
          _model = null;
          _year = null;
          _clearSuggestedImage();
          // Moto troca 2 pneus por vez, carro troca 4.
          _parts = Vehicle.defaultParts(type);
        });
      },
    );
  }

  Widget _pickerTile({
    required Key key,
    required String label,
    required String? value,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: key,
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            enabled: enabled,
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            value ?? 'Escolher',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: value == null ? Colors.grey.shade600 : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fuelBlock() {
    final rate = fuelRatePerKm(_draft);

    return Column(
      children: [
        DropdownButtonFormField<FuelType>(
          initialValue: _fuel,
          decoration: const InputDecoration(
            labelText: 'Tipo',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final fuel in FuelType.values)
              DropdownMenuItem(value: fuel, child: Text(_fuelLabel(fuel))),
          ],
          onChanged: (value) => setState(() => _fuel = value ?? _fuel),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('vehicle-fuel-price'),
                controller: _fuelPrice,
                keyboardType: TextInputType.number,
                inputFormatters:
                    CurrencyFormatterHelper.getCurrencyFormatter(),
                decoration: InputDecoration(
                  labelText: _fuel == FuelType.eletrico
                      ? 'Preço do kWh'
                      : 'Preço do litro',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (_) =>
                    _fuelPriceValue == null ? 'Informe o preço' : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const Key('vehicle-consumption'),
                controller: _consumption,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: _fuel == FuelType.eletrico
                      ? 'Consumo (km/kWh)'
                      : 'Consumo (km/l)',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (_) {
                  final value = _consumptionValue;
                  // Zero não é consumo baixo, é divisão por zero — e sem este
                  // número não existe provisão nenhuma.
                  if (value == null || value <= 0) return 'Informe o consumo';
                  return null;
                },
              ),
            ),
          ],
        ),
        if (rate != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${formatRate(rate)} /km',
                key: const Key('vehicle-fuel-rate'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _fuelLabel(FuelType fuel) => switch (fuel) {
    FuelType.flex => 'Flex',
    FuelType.gasolina => 'Gasolina',
    FuelType.etanol => 'Etanol',
    FuelType.diesel => 'Diesel',
    FuelType.eletrico => 'Elétrico',
  };

  Widget _totalCard() {
    final draft = _draft;
    final total = totalRatePerKm(draft);
    final missing = unpricedParts(draft);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Custo total',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            // Sem consumo o total é `null`, e mostrar só as peças diria
            // R$ 0,119/km de um carro que gasta R$ 0,819.
            total == null ? '—' : '${formatRate(total)} / km',
            key: const Key('vehicle-total-rate'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (total != null)
            Text(
              'Numa rota de 50 km → '
              '${CurrencyFormatterHelper.formatMoney(total * 50)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              // Peça descartada em silêncio é custo que ele acha que
              // provisionou e não provisionou.
              'Fora da conta, faltam dados: ${missing.join(', ')}',
              key: const Key('vehicle-missing-parts'),
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
