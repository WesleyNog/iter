/// O filtro da lista de rotas: quais rotas passam e em que ordem elas saem.
///
/// Mora fora da tela porque é a única parte da mudança que dá para **provar**
/// sem aparelho — e porque a regra do "vazio ou completo passa tudo" vale para
/// dois eixos diferentes. Escrita duas vezes, uma delas fica para trás no
/// primeiro ajuste.
library;

import 'package:iter/Utils/periodPreset.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/model/newRouteModal.dart';

/// A ordem em que a lista sai depois de filtrada.
///
/// [pertoDeHoje] é o padrão e é o **único que não reordena nada**: quem ordena
/// por ele é `RouteController.watchAll`, e a razão está em
/// `docs/specs/lista-iter.md` — o critério muda todo dia, nenhum índice do
/// Firestore o expressa, e ter duas implementações dele seria ter duas listas
/// discordando sobre o que é "hoje".
enum RouteOrder { pertoDeHoje, maisRecente, maisAntiga, maiorValor, menorValor }

String orderLabel(RouteOrder order) {
  switch (order) {
    case RouteOrder.pertoDeHoje:
      return 'Mais perto de hoje';
    case RouteOrder.maisRecente:
      return 'Mais recente';
    case RouteOrder.maisAntiga:
      return 'Mais antiga';
    case RouteOrder.maiorValor:
      return 'Maior valor';
    case RouteOrder.menorValor:
      return 'Menor valor';
  }
}

/// Faixa de dinheiro, as duas pontas inclusive.
typedef ValueRange = ({double min, double max});

/// Sentinela do [RouteFilter.copyWith].
///
/// `null` é um valor **válido** em três dos seis campos — é ele que quer dizer
/// "este eixo não corta nada". Sem a sentinela, `copyWith(period: null)` seria
/// indistinguível de não passar `period`, e limpar um filtro pelo `copyWith`
/// seria impossível: o botão "Limpar" nasceria sem efeito e sem erro.
const Object _keep = Object();

/// O que está cortando a lista, num objeto só.
///
/// Imutável e com [copyWith] porque a folha de filtros monta um **rascunho** —
/// o usuário mexe em cinco seções e nada acontece na lista até ele confirmar.
/// Seis campos soltos numa tela seriam seis `setState` e nenhum jeito de
/// devolver "o que ele escolheu" numa coisa só.
class RouteFilter {
  const RouteFilter({
    this.companies = const {},
    this.statuses = const {},
    this.period,
    this.vehicleId,
    this.valueRange,
    this.order = RouteOrder.pertoDeHoje,
  });

  /// Nada cortando, ordem padrão — o estado inicial da tela e o destino do
  /// botão "Limpar filtros".
  static const RouteFilter none = RouteFilter();

  /// Vazio **ou** com as três: passa tudo. Ver [_passes].
  final Set<Company> companies;

  /// Mesma regra de [companies], com os cinco status.
  final Set<StatusRoute> statuses;

  /// `null` = todo o período. É o padrão de propósito: a lista sempre mostrou
  /// tudo, e abrir já filtrando por mês esconderia rota sem o usuário pedir.
  final DateRange? period;

  /// `null` = qualquer veículo.
  ///
  /// Com um id, isto é necessariamente "rotas que **já rodaram** com este
  /// carro": o id mora em `provision`, que só existe em rota concluída, paga ou
  /// sem rota. Rota agendada não tem veículo nenhum para comparar. Ver
  /// `docs/specs/filtros.md`.
  final String? vehicleId;

  /// `null` = faixa não tocada.
  ///
  /// Não é "a faixa cobrindo tudo": uma faixa que nasce cobrindo tudo parece
  /// filtro ligado sem estar cortando nada, e entraria na conta do badge.
  final ValueRange? valueRange;

  final RouteOrder order;

  RouteFilter copyWith({
    Set<Company>? companies,
    Set<StatusRoute>? statuses,
    Object? period = _keep,
    Object? vehicleId = _keep,
    Object? valueRange = _keep,
    RouteOrder? order,
  }) {
    return RouteFilter(
      companies: companies ?? this.companies,
      statuses: statuses ?? this.statuses,
      period: identical(period, _keep) ? this.period : period as DateRange?,
      vehicleId: identical(vehicleId, _keep)
          ? this.vehicleId
          : vehicleId as String?,
      valueRange: identical(valueRange, _keep)
          ? this.valueRange
          : valueRange as ValueRange?,
      order: order ?? this.order,
    );
  }

  /// Marca o que está desmarcado e desmarca o que está marcado — **só ele**.
  RouteFilter toggleCompany(Company company) =>
      copyWith(companies: _toggled(companies, company));

  RouteFilter toggleStatus(StatusRoute status) =>
      copyWith(statuses: _toggled(statuses, status));

  /// Quantos eixos **além da empresa** estão cortando a lista — o número do
  /// badge do ícone.
  ///
  /// Conta eixos, não opções marcadas: um "3" querendo dizer três status do
  /// mesmo eixo seria mentira sobre quantos cortes estão valendo. E a empresa
  /// fica de fora porque ela está desenhada na tela ao lado, marcada — contá-la
  /// duas vezes é o badge dizendo que existe um filtro escondido que não existe.
  int get extraCount {
    var count = 0;
    if (_narrows(statuses, StatusRoute.values.length)) count++;
    if (period != null) count++;
    if (vehicleId != null) count++;
    if (valueRange != null) count++;
    return count;
  }

  /// Nada está sendo cortado e a ordem é a padrão.
  ///
  /// Não é o mesmo que "os conjuntos estão vazios": com as três empresas
  /// marcadas isto é `true`, porque marcar todas é exatamente o que "mostre
  /// tudo" quer dizer. Quem precisa **limpar as marcas** usa [none].
  bool get filtersNothing =>
      !_narrows(companies, Company.values.length) &&
      extraCount == 0 &&
      order == RouteOrder.pertoDeHoje;
}

/// As rotas que passam em [filter], já na ordem que ele pede.
///
/// Filtrar e ordenar na mesma função porque são um passo só do ponto de vista
/// da tela — e porque separá-las convida a chamar uma sem a outra.
List<NewRouteModal> applyFilter(
  List<NewRouteModal> routes,
  RouteFilter filter,
) {
  var result = routes;

  final period = filter.period;
  if (period != null) {
    // `inPeriod` e não uma comparação nova aqui: a regra de "as duas pontas
    // inclusive, comparando por **dia**" já mora lá, testada, e é a mesma que
    // os gráficos usam. Uma segunda cópia divergiria no primeiro ajuste — e a
    // divergência seria a lista e o gráfico discordando sobre o mesmo mês.
    result = inPeriod(result, start: period.start, end: period.end);
  }

  result = result
      .where(
        (route) =>
            _passes(filter.companies, route.company, Company.values.length) &&
            _passes(filter.statuses, route.status, StatusRoute.values.length) &&
            _matchesVehicle(filter.vehicleId, route) &&
            _matchesValue(filter.valueRange, route.value),
      )
      .toList();

  return sortRoutes(result, filter.order);
}

/// A lista reordenada, ou **ela mesma** quando a ordem é [RouteOrder.pertoDeHoje].
///
/// Devolver a lista intacta não é economia: é o que garante que o critério de
/// proximidade com hoje continue existindo num lugar só.
List<NewRouteModal> sortRoutes(List<NewRouteModal> routes, RouteOrder order) {
  if (order == RouteOrder.pertoDeHoje) return routes;

  final sorted = [...routes];
  sorted.sort((a, b) {
    switch (order) {
      case RouteOrder.pertoDeHoje:
        return 0;
      case RouteOrder.maisRecente:
        return _tiebreak(b.startAt.compareTo(a.startAt), a, b);
      case RouteOrder.maisAntiga:
        return _tiebreak(a.startAt.compareTo(b.startAt), a, b);
      case RouteOrder.maiorValor:
        return _tiebreak(b.value.compareTo(a.value), a, b);
      case RouteOrder.menorValor:
        return _tiebreak(a.value.compareTo(b.value), a, b);
    }
  });
  return sorted;
}

/// Os limites da faixa de valor, arredondados **para fora** na dezena.
///
/// Saem da lista inteira, antes de qualquer filtro: com os limites vindo do
/// resultado filtrado, o trilho encolheria conforme o usuário filtra e a alça
/// que ele acabou de arrastar sairia dele.
///
/// `null` quer dizer "não dá para desenhar a faixa", e é o caso real de quem
/// tem uma rota só ou todas do mesmo valor: `RangeSlider` **lança** com
/// `min == max`. Arredondar para a dezena também resolve o outro extremo — de
/// R$ 199,00 a R$ 212,00 as duas pontas ficam impossíveis de agarrar.
ValueRange? valueBounds(List<NewRouteModal> routes) {
  if (routes.isEmpty) return null;

  var min = routes.first.value;
  var max = min;
  for (final route in routes) {
    if (route.value < min) min = route.value;
    if (route.value > max) max = route.value;
  }

  // Nenhuma faixa quando todas as rotas valem o mesmo — a rota única incluída.
  // Dois motivos apontando para o mesmo `null`: não há o que discriminar, e
  // `RangeSlider` **lança** com `min == max`. Com `min < max` garantido aqui, o
  // arredondamento para fora nunca colapsa as pontas.
  if (min >= max) return null;

  return (min: (min / 10).floorToDouble() * 10, max: (max / 10).ceilToDouble() * 10);
}

/// Os ids de veículo que alguma rota já usou.
///
/// Só rota com provisão tem veículo, então isto é sempre um subconjunto do que
/// já rodou. Um id órfão — veículo apagado depois da rota — sai daqui e o
/// widget não acha nome para ele: é isso que faz a seção listar só carro que
/// ainda existe, em vez de oferecer um filtro rotulado com um id cru.
Set<String> vehicleIdsInUse(List<NewRouteModal> routes) => {
  for (final route in routes)
    if (route.provision != null && route.provision!.vehicleId.isNotEmpty)
      route.provision!.vehicleId,
};

/// Vazio **ou** completo passa tudo.
///
/// As duas metades são a mesma resposta, e é isso que faz o seletor sem
/// "Todas" funcionar: nenhum marcado é o estado inicial, todos marcados é para
/// onde o usuário chega marcando um a um, e os dois querem dizer "mostre tudo".
bool _passes<T>(Set<T> selected, T value, int total) =>
    selected.isEmpty || selected.length >= total || selected.contains(value);

/// O conjunto **corta** alguma coisa: tem alguém marcado, mas não todos.
bool _narrows<T>(Set<T> selected, int total) =>
    selected.isNotEmpty && selected.length < total;

bool _matchesVehicle(String? vehicleId, NewRouteModal route) =>
    vehicleId == null || route.provision?.vehicleId == vehicleId;

/// Meio centavo de folga nas duas pontas.
///
/// Sem ela, uma rota que a tela mostra como R$ 212,00 pode cair fora de uma
/// faixa que termina em R$ 212,00 — o `double` gravado é 212.00000000000003 e
/// só o `toStringAsFixed(2)` esconde isso. É o mesmo motivo do épsilon de um
/// metro no KM da provisão, na escala do dinheiro.
const double _halfCent = 0.005;

bool _matchesValue(ValueRange? range, double value) =>
    range == null ||
    (value >= range.min - _halfCent && value <= range.max + _halfCent);

/// Desempate pelo `id` para a ordem não dançar entre dois rebuilds — a mesma
/// escolha de `sortByDateDesc` em `Utils/dated.dart`.
int _tiebreak(int primary, NewRouteModal a, NewRouteModal b) =>
    primary != 0 ? primary : a.id.compareTo(b.id);

Set<T> _toggled<T>(Set<T> selected, T value) => selected.contains(value)
    ? ({...selected}..remove(value))
    : {...selected, value};
