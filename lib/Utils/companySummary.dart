/// Resumo de um recorte de rotas: uma empresa num período, ou todas juntas.
///
/// É a tradução do bloco `V2:AA6` da planilha — ganhos, provisão e lucro por
/// plataforma — mais o que ela não tem: KM, pacotes, paradas, insucessos e
/// bairros. Ver `docs/specs/resumo-por-empresa.md`.
///
/// Fica separado de `routeStats.dart`, que devolve **rankings e séries** para
/// gráficos, e de `profileStats.dart`, que é carreira inteira sem filtro. Aqui
/// é um objeto de resumo por recorte. O que dá para reusar é importado, não
/// copiado.
library;

import 'package:iter/Utils/routeStats.dart';
import 'package:iter/Utils/vehicleCost.dart' show kmOf;
import 'package:iter/model/newRouteModal.dart';

/// Um `null` neste objeto significa **"não dá para calcular"**, nunca zero.
class CompanySummary {
  const CompanySummary({
    required this.routes,
    required this.value,
    required this.profit,
    required this.uncalculatedValue,
    required this.failures,
    required this.noRouteCount,
    required this.noRouteValue,
    this.km,
    this.packages,
    this.stops,
    this.failureRate,
    this.costPerKm,
    this.topBairro,
    this.bottomBairro,
  });

  /// Quantas rotas realizadas (`concluido` + `pago`) no recorte.
  ///
  /// A ida sem rota **não** entra: ela está em [noRouteCount]. Ela não entregou
  /// pacote, não passou por bairro e não foi uma rota — mas o dinheiro e o KM
  /// dela estão em [value], [profit], [km] e [costPerKm].
  final int routes;

  /// Quantas idas que não viraram rota (`semRota`).
  final int noRouteCount;

  /// Quanto delas veio, já com o percentual aplicado. Faz parte de [value] — é a
  /// parcela, não uma soma à parte.
  final double noRouteValue;

  /// `Σ value` — o que a empresa pagou, pelas rotas **e** pelas idas sem rota.
  final double value;

  /// Lucro **misto**: líquido nas rotas que já têm custo calculado, bruto nas
  /// que ainda não têm.
  ///
  /// É a conta pedida, e ela não perde rota nenhuma — mas sozinha engana de
  /// dois jeitos: sem provisão nenhuma sai idêntica a [value], e vai *caindo*
  /// conforme as provisões são calculadas, parecendo que se lucra menos quando
  /// só se passou a medir certo. Por isso [uncalculatedValue] existe e a tela é
  /// obrigada a mostrá-la.
  final double profit;

  /// Quanto de [profit] ainda é bruto. Zero = o número está inteiro.
  final double uncalculatedValue;

  /// Insucessos. Zero é informação — "não teve" é um fato, diferente de
  /// "ninguém preencheu".
  final int failures;

  /// `Σ (kmFinal − kmInitial)` das que informaram.
  final double? km;

  final int? packages;
  final int? stops;

  /// `insucessos ÷ pacotes × 100`.
  final double? failureRate;

  /// Custo por quilômetro **só das rotas com provisão**.
  ///
  /// Incluir as outras jogaria KM no divisor sem jogar custo no dividendo, e o
  /// resultado erraria sempre para menos — o lado que engana num custo.
  final double? costPerKm;

  final String? topBairro;

  /// O bairro menos rodado **entre os que ele rodou**. Bairro onde nunca foi
  /// não é "pouco rodado", é ausente.
  ///
  /// Com um bairro só, é igual a [topBairro]; quem decide não repetir na tela é
  /// o card.
  final String? bottomBairro;

  /// Não há **nada** para mostrar.
  ///
  /// As duas contagens, e não só [routes]: um mês só de idas ao CD tem dinheiro,
  /// KM e lucro, e `routes == 0` sozinho faria a aba Resumo inteira dizer
  /// "Nenhuma rota entre 01/08 e 31/08" escondendo tudo — o mesmo "some o
  /// dinheiro e o KM" que esta feature existe para consertar, reproduzido
  /// dentro do app.
  bool get isEmpty => routes == 0 && noRouteCount == 0;

  /// Há lucro bruto misturado, então a ressalva precisa aparecer.
  bool get hasUncalculated => uncalculatedValue > 0;
}

/// Resume a lista **já filtrada** por período e empresa.
///
/// O recorte de status é feito aqui, e são **dois** recortes, não um:
///
/// - `realized` (`concluido` + `pago`) manda em tudo que descreve uma rota —
///   a contagem, os pacotes, as paradas, os insucessos e os bairros. Rota
///   agendada não entregou pacote, não rodou quilômetro e não passou por bairro
///   nenhum.
/// - `noRouteTrips` (`semRota`) entra só no que é dinheiro e quilômetro: valor,
///   lucro, KM e custo por km. A ida ao CD queimou gasolina de verdade, mas não
///   foi uma rota.
CompanySummary companySummary(List<NewRouteModal> all) {
  final done = realized(all);
  final trips = noRouteTrips(all);

  var value = 0.0;
  var profit = 0.0;
  var uncalculated = 0.0;
  var failures = 0;
  var noRouteValue = 0.0;

  double? km;
  int? packages;
  int? stops;

  // Acumuladores do custo por km, alimentados só pelas rotas com provisão.
  var provisionedCost = 0.0;
  var provisionedKm = 0.0;

  // Dinheiro, lucro e quilômetro — o que a rota e a ida sem rota têm em comum.
  //
  // Uma função e não o corpo copiado: somar o KM de uma e o custo da outra erra
  // o custo por km sem nenhum sinal, e sempre para o mesmo lado — mais KM no
  // divisor sem custo no dividendo baixa o R$/km, que é a direção que faz o
  // entregador achar que lucra mais.
  void addMoney(NewRouteModal route) {
    value += route.value;

    final routeProfit = route.profit;
    if (routeProfit == null) {
      // Sem custo calculado, entra bruto — e fica registrado que entrou.
      profit += route.value;
      uncalculated += route.value;
    } else {
      profit += routeProfit;
    }

    final provision = route.provision;
    if (provision != null) {
      provisionedCost += provision.total;
      provisionedKm += provision.km;
    }

    // `kmOf` e não a subtração à mão: é a mesma definição de "KM rodado" que a
    // provisão e o card da rota usam, com a guarda de diferença não positiva.
    final routeKm = kmOf(route);
    if (routeKm != null) km = (km ?? 0) + routeKm;
  }

  for (final route in done) {
    addMoney(route);

    final routePackages = route.packages;
    if (routePackages != null) packages = (packages ?? 0) + routePackages;

    final routeStops = route.stops;
    if (routeStops != null) stops = (stops ?? 0) + routeStops;

    failures += failuresOf(route);
  }

  // Passada separada, e **nunca** ampliando a lista `done` acima: todo o corpo
  // daquele laço — pacotes, paradas, insucessos — e o `routesPerBairro` logo
  // abaixo iteram `done`. Uma rota editada de `concluido` para `semRota` mantém
  // `adress`, `packages` e o insucesso gravados, então bastaria alargar aquela
  // linha para a ida ao CD entrar em cinco métricas que ela não tem.
  for (final trip in trips) {
    addMoney(trip);
    noRouteValue += trip.value;
  }

  final ranking = routesPerBairro(done);

  return CompanySummary(
    routes: done.length,
    noRouteCount: trips.length,
    noRouteValue: noRouteValue,
    value: value,
    profit: profit,
    uncalculatedValue: uncalculated,
    failures: failures,
    km: km,
    packages: packages,
    stops: stops,
    // Sem pacotes informados não há taxa — e não é 0%.
    failureRate: (packages == null || packages == 0)
        ? null
        : failures / packages * 100,
    costPerKm: provisionedKm > 0 ? provisionedCost / provisionedKm : null,
    topBairro: ranking.isEmpty ? null : ranking.first.label,
    bottomBairro: ranking.isEmpty ? null : ranking.last.label,
  );
}

/// Um resumo por empresa, **sempre com as três**.
///
/// Empresa sem rota vem zerada em vez de faltar: card que some e volta faz a
/// posição dos outros dançar de um mês para o outro, e "Shopee: sem rotas" é
/// informação, não ausência de informação.
Map<Company, CompanySummary> summaryByCompany(List<NewRouteModal> all) {
  return {
    for (final company in Company.values)
      company: companySummary(
        all.where((route) => route.company == company).toList(),
      ),
  };
}
