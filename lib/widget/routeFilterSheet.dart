import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/periodPreset.dart';
import 'package:iter/Utils/routeFilter.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/widget/filterPill.dart';
import 'package:iter/widget/periodPresetFilter.dart';

/// A folha com os filtros que não cabem no trilho de empresa: status, período,
/// veículo, faixa de valor e ordenação.
///
/// Devolve `null` quando é **descartada** — arrastada para baixo ou fechada por
/// um toque fora — e `null` quer dizer que nada muda na lista. Um [RouteFilter]
/// é sempre o "Aplicar", e é o rascunho inteiro, nunca um eixo só.
///
/// Nada é aplicado enquanto ela está aberta. A folha cobre a lista, então filtro
/// que aplica a cada toque muda algo que o usuário não está vendo — ele fecha e
/// descobre o resultado por eliminação. É também o que a torna testável como
/// função de ida e volta, sem bombear a tela inteira.
///
/// [routes] são **todas** as rotas, sem filtro nenhum: é de lá que saem os
/// limites da faixa de valor e os veículos que já rodaram. Com a lista já
/// filtrada, o trilho da faixa encolheria a cada aplicação e a alça que o
/// usuário acabou de arrastar sairia dele.
///
/// [vehicles] em `null` quer dizer **não deu para saber** — a leitura ainda não
/// chegou, ou falhou —, nunca "não tem veículo". A distinção é a mesma que
/// `getWeather` faz com o clima, pelo mesmo motivo: colapsar as duas desenharia
/// a ausência da seção para um entregador sem sinal que **tem** carro
/// cadastrado, e ele procuraria o filtro que sumiu.
Future<RouteFilter?> showRouteFilterSheet(
  BuildContext context, {
  required RouteFilter current,
  required List<NewRouteModal> routes,
  required List<Vehicle>? vehicles,
}) {
  return showModalBottomSheet<RouteFilter>(
    context: context,
    // São cinco seções, e uma folha comum é limitada a 9/16 da altura da tela:
    // sem isto a ordenação fica fora do alcance num aparelho baixo. O conteúdo
    // rola; seção nenhuma é cortada.
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _RouteFilterSheet(current: current, routes: routes, vehicles: vehicles),
  );
}

class _RouteFilterSheet extends StatefulWidget {
  const _RouteFilterSheet({
    required this.current,
    required this.routes,
    required this.vehicles,
  });

  final RouteFilter current;
  final List<NewRouteModal> routes;
  final List<Vehicle>? vehicles;

  @override
  State<_RouteFilterSheet> createState() => _RouteFilterSheetState();
}

class _RouteFilterSheetState extends State<_RouteFilterSheet> {
  /// O rascunho. Só vira filtro de verdade no "Aplicar".
  ///
  /// Entra **reconciliado** — ver [_reconciled].
  late RouteFilter _draft = _reconciled(widget.current);

  /// O atalho de período aceso.
  ///
  /// Mora aqui porque [RouteFilter] guarda o **recorte**, não o atalho — e é o
  /// recorte que os filtros precisam. Sem esta cópia, o chip aceso se perderia
  /// no primeiro `setState` de qualquer outra seção.
  late PeriodPreset? _preset = _presetOf(widget.current.period);

  /// As datas que o Personalizado edita. Fora dele são as que o atalho implica.
  late DateRange _dates = widget.current.period ?? currentMonth();

  /// Os limites do trilho de valor, calculados **uma vez**.
  ///
  /// `null` quer dizer "não dá para desenhar a faixa" — uma rota só, ou todas do
  /// mesmo valor. `RangeSlider` lança com `min == max`, então a seção some antes
  /// de o widget existir. Recalcular a cada rebuild só gastaria a lista inteira
  /// por toque, já que [widget.routes] não muda enquanto a folha está aberta.
  late final ValueRange? _bounds = valueBounds(widget.routes);

  /// O filtro que chegou, com a faixa de valor conferida contra os limites de
  /// **agora**.
  ///
  /// O filtro guarda a faixa em reais e os limites são recalculados a cada
  /// abertura — e a lista muda entre uma e outra pela própria tela que abre esta
  /// folha, que apaga rota deslizando o card e edita valor no formulário.
  /// Apagar a rota de R$ 500 de uma lista de 100/250/500 derruba o teto para
  /// R$ 250 com a faixa 300–500 ainda gravada, e `RangeSlider` **lança**
  /// (`assert(values.start >= min)`): tela vermelha no debug, alça fora do
  /// trilho no release.
  ///
  /// A faixa é **descartada**, não espremida: uma faixa 300–500 encolhida à
  /// força para 100–250 não é o que o usuário escolheu, e filtro que se
  /// reescreve sozinho engana mais do que filtro que se desliga. Sai do badge
  /// junto, porque deixou mesmo de cortar.
  ///
  /// Com [_bounds] em `null` — rota única, ou todas do mesmo valor — a faixa
  /// também cai. Esconder a seção e manter o eixo ligado deixaria o badge
  /// contando um filtro cujo botão de limpar mora dentro da seção que sumiu.
  RouteFilter _reconciled(RouteFilter filter) {
    final range = filter.valueRange;
    if (range == null) return filter;

    final bounds = _bounds;
    if (bounds == null) return filter.copyWith(valueRange: null);

    // Um centavo de folga: as pontas vêm do próprio trilho, e a divisão em
    // passos devolve 249.99999999999997 onde o limite é 250.
    const slack = 0.01;
    if (range.min < bounds.min - slack || range.max > bounds.max + slack) {
      return filter.copyWith(valueRange: null);
    }
    return filter;
  }

  /// Os veículos que **alguma rota já rodou**, na ordem do cadastro.
  ///
  /// Interseção, e não a lista de veículos: carro recém-cadastrado não filtra
  /// nada e viraria um chip que devolve lista vazia. E um id órfão — veículo
  /// apagado depois da rota — cai fora por não ter nome, em vez de virar um chip
  /// rotulado com um id cru.
  late final List<Vehicle> _usedVehicles = _intersect();

  List<Vehicle> _intersect() {
    final vehicles = widget.vehicles;
    if (vehicles == null) return const [];
    final ids = vehicleIdsInUse(widget.routes);
    return vehicles.where((vehicle) => ids.contains(vehicle.id)).toList();
  }

  /// Alguma rota guarda veículo.
  ///
  /// É o que separa "não deu para saber quais são" de "não há nada para
  /// filtrar": sem rota com provisão, a seção não tem por que existir nem
  /// quando a leitura falha.
  late final bool _hasVehicleRoutes = vehicleIdsInUse(widget.routes).isNotEmpty;

  bool get _vehiclesUnknown => widget.vehicles == null;

  /// Qual atalho descreve [period] — `null` é "todo o período".
  ///
  /// Reconhecer o recorte em vez de assumir Personalizado é o que faz o chip
  /// voltar aceso na segunda vez que a folha abre: o filtro guardou 01/08–31/08,
  /// e sem isto o "Este Mês" que o usuário escolheu reabriria como
  /// "Personalizado", com duas roletas na tela que ele não pediu. Só é seguro
  /// porque a comparação confere o recorte inteiro — o chip nunca acende sobre
  /// datas que não são as dele.
  PeriodPreset? _presetOf(DateRange? period) {
    if (period == null) return null;

    for (final preset in PeriodPreset.values) {
      final range = rangeOf(preset);
      if (range != null &&
          _sameDay(range.start, period.start) &&
          _sameDay(range.end, period.end)) {
        return preset;
      }
    }
    return PeriodPreset.personalizado;
  }

  /// Compara por **dia**, como `inPeriod` já faz: as datas do atalho nascem à
  /// meia-noite e as da roleta carregam a hora em que o usuário parou de girar.
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _update(RouteFilter next) => setState(() => _draft = next);

  /// Volta o rascunho inteiro ao [RouteFilter.none] — **sem fechar**.
  ///
  /// Inclui as empresas, que estão no trilho atrás da folha: é o mesmo destino
  /// do "Limpar filtros" do estado vazio da lista, e um botão de limpar que
  /// deixa um eixo ligado é exatamente o que faz o entregador jurar que sumiu
  /// rota. Não fecha porque limpar quase nunca é o fim do gesto — quem limpa
  /// está prestes a marcar outra coisa.
  void _clearAll() => setState(() {
    _draft = RouteFilter.none;
    _preset = null;
    _dates = currentMonth();
  });

  @override
  Widget build(BuildContext context) {
    final bounds = _bounds;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Text(
                    'Filtros',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            // O rodapé fica **fora** do scroll: com ele dentro, "Aplicar" seria
            // a única ação da folha que exige rolar até o fim para existir.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statusSection(),
                    _periodSection(),
                    if (_usedVehicles.isNotEmpty ||
                        (_vehiclesUnknown && _hasVehicleRoutes))
                      _vehicleSection(),
                    if (bounds != null) _valueSection(bounds),
                    _orderSection(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _statusSection() {
    return _section(
      title: 'Status',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final status in StatusRoute.values)
            _chip(
              keyName: 'status-${status.name}',
              label: statusLabel(status),
              icon: statusIcon(status),
              accent: statusColor(status),
              // Nenhum marcado e os cinco marcados são a mesma resposta —
              // "mostre tudo" —, e quem sabe disso é `_passes`, uma vez só. Aqui
              // o chip só desenha o que está no conjunto.
              selected: _draft.statuses.contains(status),
              onTap: () => _update(_draft.toggleStatus(status)),
            ),
        ],
      ),
    );
  }

  Widget _periodSection() {
    return _section(
      title: 'Período',
      child: PeriodPresetFilter(
        preset: _preset,
        start: _dates.start,
        end: _dates.end,
        // "Todo o período" é o padrão desta folha: a lista sempre mostrou tudo,
        // e abrir já recortada por mês esconderia rota sem o usuário pedir.
        allowAll: true,
        onChanged: (preset, start, end) => setState(() {
          _preset = preset;
          _dates = (start: start, end: end);
          _draft = _draft.copyWith(
            period: preset == null ? null : (start: start, end: end),
          );
        }),
      ),
    );
  }

  Widget _vehicleSection() {
    return _section(
      title: 'Veículo',
      // A frase não é enfeite: `vehicleId` mora em `provision`, que só existe em
      // rota concluída, paga ou sem rota. Rota agendada não tem veículo nenhum
      // para comparar e sai da lista em qualquer escolha que não seja "Todos" —
      // sem esta linha, o filtro parece estar comendo rota.
      support:
          'Só rota concluída, paga ou sem rota guarda o veículo. '
          'Rota agendada fica de fora quando você escolhe um carro.',
      supportKey: const ValueKey('veiculo-aviso'),
      // Falha de leitura é uma frase **diferente** de "nenhum carro rodou": a
      // primeira leitura num aparelho sem sinal é o caso comum, e some com a
      // seção inteira de quem tem carro cadastrado. Ver `norouterule` no
      // CLAUDE.md, onde a mesma distinção já foi paga uma vez.
      child: _usedVehicles.isEmpty
          ? Text(
              key: const ValueKey('veiculo-indisponivel'),
              'Não foi possível ler seus veículos agora.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            )
          : Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip(
            keyName: 'veiculo-todos',
            label: 'Todos',
            selected: _draft.vehicleId == null,
            onTap: () => _update(_draft.copyWith(vehicleId: null)),
          ),
          for (final vehicle in _usedVehicles)
            _chip(
              keyName: 'veiculo-${vehicle.id}',
              label: vehicle.displayName,
              selected: _draft.vehicleId == vehicle.id,
              onTap: () => _update(_draft.copyWith(vehicleId: vehicle.id)),
            ),
        ],
      ),
    );
  }

  Widget _valueSection(ValueRange bounds) {
    final range = _draft.valueRange;
    // Inativa, o trilho mostra os limites inteiros — e o rascunho segue com
    // `null`. Gravar a faixa cheia aqui seria um filtro que não corta nada
    // contando um eixo no badge do ícone.
    final values = RangeValues(
      range?.min ?? bounds.min,
      range?.max ?? bounds.max,
    );

    return _section(
      title: 'Faixa de valor',
      support: range == null
          ? 'Arraste para começar a filtrar por valor.'
          : null,
      trailing: range == null
          ? null
          : IconButton(
              key: const ValueKey('valor-limpar'),
              onPressed: () => _update(_draft.copyWith(valueRange: null)),
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Limpar faixa',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RangeSlider(
            key: const ValueKey('valor-faixa'),
            values: values,
            min: bounds.min,
            max: bounds.max,
            // Um passo de R$ 10, que é a dezena para onde `valueBounds` já
            // arredondou as pontas: com o trilho contínuo, a alça para em
            // R$ 187,43 e o rótulo vira ruído.
            divisions: ((bounds.max - bounds.min) / 10).round(),
            labels: RangeLabels(_money(values.start), _money(values.end)),
            onChanged: (picked) => _update(
              _draft.copyWith(valueRange: (min: picked.start, max: picked.end)),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_money(values.start), style: _valueLabelStyle),
              Text(_money(values.end), style: _valueLabelStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderSection() {
    return _section(
      title: 'Ordenar por',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final order in RouteOrder.values)
            _chip(
              keyName: 'ordem-${order.name}',
              label: orderLabel(order),
              selected: _draft.order == order,
              onTap: () => _update(_draft.copyWith(order: order)),
            ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          // As duas ações em `Expanded`: cada uma recebe metade da largura,
          // independentemente do tamanho que a fonte do aparelho der ao rótulo.
          Expanded(
            child: TextButton(
              key: const ValueKey('filtro-limpar'),
              onPressed: _clearAll,
              child: const Text('Limpar tudo'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const ValueKey('filtro-aplicar'),
              onPressed: () => Navigator.of(context).pop(_draft),
              child: const Text('Aplicar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required Widget child,
    String? support,
    Key? supportKey,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (support != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                support,
                key: supportKey,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _chip({
    required String keyName,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? accent,
  }) => FilterPill(
    key: ValueKey(keyName),
    label: label,
    selected: selected,
    onTap: onTap,
    icon: icon,
    accent: accent,
  );
}

TextStyle get _valueLabelStyle =>
    TextStyle(fontSize: 12, color: Colors.grey.shade600);

String _money(double value) => CurrencyFormatterHelper.formatMoney(value);
