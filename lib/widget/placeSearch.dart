import 'package:flutter/material.dart';
import 'package:iter/services/geocoding.dart';

/// Quem resolve o texto em lugares. Em produção, [GeocodingService.search].
typedef PlaceSearcher =
    Future<List<Place>?> Function(String query, {double? lat, double? lng});

/// "Outra localização": um bairro ou endereço digitado vira o centro da lista
/// de postos.
///
/// Devolve o lugar escolhido, ou `null` ao voltar sem escolher.
///
/// A busca dispara **só na confirmação** — "Buscar" no teclado ou o botão.
/// A política do Nominatim proíbe autocompletar, e uma busca por letra seria
/// exatamente isso.
///
/// [lat]/[lng] puxam os resultados para perto da posição do aparelho; sem
/// GPS, o serviço cai em Fortaleza.
Future<Place?> showPlaceSearch(
  BuildContext context, {
  double? lat,
  double? lng,
  PlaceSearcher? search,
}) {
  return Navigator.of(context).push<Place>(
    MaterialPageRoute(
      builder: (_) => _PlaceSearchPage(
        lat: lat,
        lng: lng,
        search: search ?? GeocodingService.search,
      ),
    ),
  );
}

class _PlaceSearchPage extends StatefulWidget {
  const _PlaceSearchPage({this.lat, this.lng, required this.search});

  final double? lat;
  final double? lng;
  final PlaceSearcher search;

  @override
  State<_PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<_PlaceSearchPage> {
  final _query = TextEditingController();

  bool _loading = false;

  /// `null` antes da primeira busca e quando ela falhou — [_failed] separa os
  /// dois. Lista vazia é "nada com esse nome".
  List<Place>? _results;
  bool _failed = false;

  /// O texto da busca que produziu o resultado na tela, para a frase de "nada
  /// encontrado" citar o que foi buscado, e não o que já começou a ser apagado.
  String _searched = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    // Botão desligado durante a busca: dois toques seguidos seriam duas
    // requisições no mesmo segundo, e a política pede no máximo uma.
    if (query.isEmpty || _loading) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _failed = false;
    });

    final results = await widget.search(
      query,
      lat: widget.lat,
      lng: widget.lng,
    );
    if (!mounted) return;

    setState(() {
      _loading = false;
      _results = results;
      _failed = results == null;
      _searched = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outra localização')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('place-query'),
                    controller: _query,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Bairro, rua ou referência',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    // Só ao confirmar — nunca `onChanged`. Ver o topo do
                    // arquivo.
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('place-search'),
                  onPressed: _loading ? null : _search,
                  child: const Text('Buscar'),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_failed) {
      // Frase diferente de "nada encontrado": aqui o lugar pode existir, só
      // não deu para perguntar.
      return _message(
        'Não foi possível buscar esse endereço agora.',
        key: const Key('place-failed'),
        action: TextButton(
          onPressed: _search,
          child: const Text('Tentar de novo'),
        ),
      );
    }

    final results = _results;
    if (results == null) {
      return _message(
        'Digite o bairro ou o endereço do posto onde você abasteceu.',
        key: const Key('place-hint'),
      );
    }

    if (results.isEmpty) {
      return _message(
        'Nenhum lugar encontrado para "$_searched".',
        key: const Key('place-empty'),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final place = results[index];
        return ListTile(
          key: Key('place-item-$index'),
          leading: Icon(
            Icons.location_on_outlined,
            color: Colors.green.shade600,
          ),
          title: Text(place.title),
          // A cidade, sempre: "Centro" voltou em cinco cidades.
          subtitle: place.detail.isEmpty ? null : Text(place.detail),
          onTap: () => Navigator.of(context).pop(place),
        );
      },
    );
  }

  Widget _message(String text, {required Key key, Widget? action}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            text,
            key: key,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          ?action,
        ],
      ),
    );
  }
}
