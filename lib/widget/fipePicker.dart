import 'package:flutter/material.dart';
import 'package:iter/services/fipe.dart';

/// Sheet de escolha de marca, modelo ou ano da FIPE.
///
/// Existe para o entregador **escolher** o carro em vez de digitar o nome dele.
/// A lista de modelos de uma marca grande passa de 500 itens, então busca não é
/// enfeite: é o que torna a tela usável.
///
/// Devolve `null` quando o usuário fecha sem escolher.
Future<FipeItem?> showFipePicker(
  BuildContext context, {
  required String title,
  required String hint,
  required Future<List<FipeItem>?> Function() load,
}) {
  return showModalBottomSheet<FipeItem>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _FipePickerSheet(title: title, hint: hint, load: load),
  );
}

class _FipePickerSheet extends StatefulWidget {
  const _FipePickerSheet({
    required this.title,
    required this.hint,
    required this.load,
  });

  final String title;
  final String hint;
  final Future<List<FipeItem>?> Function() load;

  @override
  State<_FipePickerSheet> createState() => _FipePickerSheetState();
}

class _FipePickerSheetState extends State<_FipePickerSheet> {
  final _search = TextEditingController();
  final _manual = TextEditingController();

  /// `null` enquanto carrega **e** quando falhou — [_failed] separa os dois.
  List<FipeItem>? _items;
  bool _failed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });

    final result = await widget.load();
    if (!mounted) return;

    setState(() {
      _loading = false;
      // `null` do serviço é "não deu para saber", não "não tem nada".
      _failed = result == null;
      _items = result;
    });
  }

  List<FipeItem> get _filtered {
    final all = _items ?? const <FipeItem>[];
    final term = _search.text.trim().toLowerCase();
    if (term.isEmpty) return all;

    return all.where((i) => i.name.toLowerCase().contains(term)).toList();
  }

  /// Escapa para o texto livre: a FIPE fora do ar — ou um veículo que ela não
  /// lista — não pode impedir alguém de cadastrar o próprio carro.
  void _useTyped() {
    final typed = _manual.text.trim();
    if (typed.isEmpty) return;

    Navigator.of(context).pop(FipeItem(code: '', name: typed));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (!_failed) ...[
                TextField(
                  key: const Key('fipe-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(child: _body()),
              const Divider(),
              _manualEntry(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível carregar a lista.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('fipe-retry'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('Nada encontrado.'));
    }

    // `builder` e não uma Column: são centenas de itens.
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.name),
          onTap: () => Navigator.of(context).pop(item),
        );
      },
    );
  }

  Widget _manualEntry() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('fipe-manual'),
            controller: _manual,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Não encontrou? Digite',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _useTyped(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('fipe-manual-use'),
          onPressed: _useTyped,
          child: const Text('Usar'),
        ),
      ],
    );
  }
}
