import 'package:flutter/material.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/services/overpass.dart';

/// O bloco "Posto" do formulário de abastecimento.
///
/// Widget **controlado**: não busca localização nem consulta a Overpass, só
/// desenha o que recebe. É o que torna cada estado — carregando, sem permissão,
/// API fora do ar, nenhum posto — testável sem aparelho e sem rede.
///
/// "Outro / não listado" existe em **todos** os estados, e não só no de erro: a
/// Overpass pode responder certinho e mesmo assim não ter o posto onde ele
/// parou. O texto livre é a saída sempre disponível.
class StationPicker extends StatelessWidget {
  const StationPicker({
    super.key,
    this.stations,
    this.loading = false,
    this.failureMessage,
    this.canOpenSettings = false,
    this.selected,
    this.otherSelected = false,
    required this.onSelect,
    required this.typedName,
    required this.onTypedName,
    this.onRetry,
    this.onOpenSettings,
  });

  /// `null` = ainda não carregou ou falhou. Lista vazia = não há posto no raio.
  final List<NearbyStation>? stations;

  final bool loading;

  /// Frase do motivo, quando não deu para listar.
  final String? failureMessage;

  /// Só quando a permissão está bloqueada nos ajustes do sistema.
  final bool canOpenSettings;

  final FuelStation? selected;

  /// "Outro / não listado" marcado. Separado de [selected] porque `null` ali
  /// também é o estado "ainda não escolheu nada".
  final bool otherSelected;

  /// `null` significa "Outro / não listado".
  final void Function(FuelStation? station) onSelect;

  final TextEditingController typedName;
  final ValueChanged<String> onTypedName;

  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _body(context),
        const SizedBox(height: 4),
        _otherTile(),
        if (otherSelected)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              key: const Key('station-typed'),
              controller: typedName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Nome do posto',
                border: OutlineInputBorder(),
              ),
              onChanged: onTypedName,
            ),
          ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (loading) {
      return Row(
        key: const Key('station-loading'),
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Procurando postos por perto...',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      );
    }

    final message = failureMessage;
    if (message != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  key: const Key('station-error'),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (onRetry != null)
                TextButton(
                  key: const Key('station-retry'),
                  onPressed: onRetry,
                  child: const Text('Tentar de novo'),
                ),
              // Só aparece quando abrir os ajustes é de fato o que resolve —
              // oferecer isso a quem tocou em "agora não" é insistência.
              if (canOpenSettings && onOpenSettings != null)
                TextButton(
                  key: const Key('station-settings'),
                  onPressed: onOpenSettings,
                  child: const Text('Abrir ajustes'),
                ),
            ],
          ),
        ],
      );
    }

    final list = stations;
    if (list == null) return const SizedBox.shrink();

    if (list.isEmpty) {
      return Text(
        'Nenhum posto encontrado por aqui.',
        key: const Key('station-empty'),
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < list.length; i++) _tile(list[i], i),
      ],
    );
  }

  Widget _tile(NearbyStation nearby, int index) {
    final station = nearby.station;
    final isSelected = !otherSelected && selected?.id == station.id;

    return ListTile(
      key: Key('station-item-$index'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isSelected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: isSelected ? Colors.blue.shade700 : Colors.grey.shade400,
      ),
      title: Text(station.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatDistance(nearby.meters),
        key: Key('station-distance-$index'),
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      onTap: () => onSelect(station),
    );
  }

  Widget _otherTile() {
    return ListTile(
      key: const Key('station-other'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        otherSelected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: otherSelected ? Colors.blue.shade700 : Colors.grey.shade400,
      ),
      title: const Text('Outro / não listado'),
      onTap: () => onSelect(null),
    );
  }
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
