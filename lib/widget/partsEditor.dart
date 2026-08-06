import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/vehicleCost.dart';
import 'package:iter/model/vehicle.dart';

/// A tabela de peças do cadastro de veículo — o bloco `V8:Z15` da planilha.
///
/// Cada linha é **preço real ÷ quilômetros que a peça dura**, e a taxa aparece
/// ao lado atualizando enquanto se digita, para dar de conferir com a planilha
/// sem sair da tela.
///
/// A coluna de quantidade é o que faz "pneu de R$ 500" ser verdade na tela e
/// certo na conta: são quatro por troca, e é o `*4` que a planilha esconde
/// dentro da fórmula.
class PartsEditor extends StatefulWidget {
  const PartsEditor({super.key, required this.parts, required this.onChanged});

  final List<MaintenancePart> parts;
  final ValueChanged<List<MaintenancePart>> onChanged;

  @override
  State<PartsEditor> createState() => _PartsEditorState();
}

class _PartsEditorState extends State<PartsEditor> {
  late List<_PartRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.parts.map(_PartRow.new).toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<MaintenancePart> get _current => _rows.map((r) => r.toPart()).toList();

  void _notify() {
    setState(() {});
    widget.onChanged(_current);
  }

  void _add() {
    setState(() {
      _rows.add(_PartRow(const MaintenancePart(name: '')));
    });
    widget.onChanged(_current);
  }

  void _remove(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
    });
    widget.onChanged(_current);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _rowCard(i),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('parts-add'),
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar peça'),
          ),
        ),
      ],
    );
  }

  Widget _rowCard(int index) {
    final row = _rows[index];
    final rate = partRatePerKm(row.toPart());

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: Key('part-name-$index'),
                    controller: row.name,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Peça',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                IconButton(
                  key: Key('part-remove-$index'),
                  tooltip: 'Remover peça',
                  onPressed: () => _remove(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (row.isFixed) _fixedRateField(index, row) else _pricedFields(index, row),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                // `—` e nunca `R$ 0,00`: "não dá para calcular" e "não custa
                // nada" são coisas diferentes, e a segunda não existe em peça.
                key: Key('part-rate-$index'),
                rate == null ? '—' : '${formatRate(rate)} /km',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: rate == null ? Colors.grey : Colors.blue.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A "P. Geral" da planilha: taxa digitada direto, sem preço nem vida útil.
  Widget _fixedRateField(int index, _PartRow row) {
    return TextField(
      key: Key('part-fixed-$index'),
      controller: row.fixedRate,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Taxa direta (R\$/km)',
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => _notify(),
    );
  }

  Widget _pricedFields(int index, _PartRow row) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            key: Key('part-price-$index'),
            controller: row.price,
            keyboardType: TextInputType.number,
            inputFormatters: CurrencyFormatterHelper.getCurrencyFormatter(),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Preço',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _notify(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          child: TextField(
            key: Key('part-life-$index'),
            controller: row.lifeKm,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Dura (km)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _notify(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextField(
            key: Key('part-qty-$index'),
            controller: row.quantity,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Qtd',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _notify(),
          ),
        ),
      ],
    );
  }
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

/// Controllers de uma linha. Fica fora do `State` para o `dispose` de cada
/// linha removida ser explícito.
class _PartRow {
  _PartRow(MaintenancePart part)
    : isFixed = part.fixedRate != null,
      name = TextEditingController(text: part.name),
      price = TextEditingController(
        text: part.price == null
            ? ''
            : CurrencyFormatterHelper.formatDoubleToMoney(part.price!),
      ),
      lifeKm = TextEditingController(text: _plain(part.lifeKm)),
      quantity = TextEditingController(text: part.quantity.toString()),
      fixedRate = TextEditingController(text: _plain(part.fixedRate));

  /// Linha de taxa direta não vira linha de preço no meio da edição: mudar de
  /// forma enquanto se digita embaralharia o que já foi preenchido.
  final bool isFixed;

  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController lifeKm;
  final TextEditingController quantity;
  final TextEditingController fixedRate;

  MaintenancePart toPart() {
    return MaintenancePart(
      name: name.text.trim(),
      price: isFixed
          ? null
          : _positiveOrNull(
              CurrencyFormatterHelper.parseMoneyToDouble(price.text),
            ),
      lifeKm: isFixed ? null : parseKm(lifeKm.text),
      quantity: int.tryParse(quantity.text) ?? 1,
      fixedRate: isFixed ? parseRate(fixedRate.text) : null,
    );
  }

  void dispose() {
    name.dispose();
    price.dispose();
    lifeKm.dispose();
    quantity.dispose();
    fixedRate.dispose();
  }

  static double? _positiveOrNull(double value) => value > 0 ? value : null;

  static String _plain(double? value) {
    if (value == null) return '';
    // 50000.0 vira "50000", 0.03 continua "0,03".
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
    return text.replaceAll('.', ',');
  }
}
