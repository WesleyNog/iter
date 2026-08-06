/// A conta que transforma KM rodado em dinheiro provisionado.
///
/// Tudo aqui é função pura sobre [Vehicle] e [NewRouteModal] — sem Firestore,
/// sem `BuildContext`, testável sem mock nenhum. É a tradução do bloco
/// `V8:Z15` de `Entregas.xlsx`, e o teste âncora em
/// `test/unit/vehicleCost_test.dart` prova que os números batem com a planilha.
///
/// A regra é sempre a mesma, para toda linha: **preço real ÷ quilômetros que
/// aquilo dura**. A gasolina não é exceção — o "preço" é o litro e a "vida" é o
/// consumo em km/l.
///
/// Um `null` devolvido aqui significa **"não dá para calcular"**, nunca zero e
/// nunca infinito.
library;

import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/vehicle.dart';

/// Taxa da peça em R$/km, ou `null` quando falta dado.
///
/// [MaintenancePart.quantity] é multiplicado porque o preço informado é de
/// **uma** peça: é o `*4` que a planilha esconde na fórmula do pneu
/// (`=(X11/Y11)*4`), as quatro rodas.
double? partRatePerKm(MaintenancePart part) {
  // A "Geral" é taxa digitada direto; preço e vida não se aplicam.
  final fixed = part.fixedRate;
  if (fixed != null) return fixed;

  final price = part.price;
  final life = part.lifeKm;
  // Vida zero não é custo infinito, é campo não preenchido.
  if (price == null || life == null || life <= 0) return null;

  return price * part.quantity / life;
}

/// R$/km de combustível: `preço do litro ÷ km por litro`.
///
/// Espelha `W9 = X9/Y9` da planilha — R$ 7,00 e 10 km/l dão R$ 0,70/km.
double? fuelRatePerKm(Vehicle vehicle) {
  final price = vehicle.fuelPrice;
  final consumption = vehicle.consumption;
  if (price == null || consumption == null || consumption <= 0) return null;

  return price / consumption;
}

/// Soma das taxas das peças, **sem** o combustível.
///
/// Peça sem dado suficiente fica de fora em vez de derrubar a soma — e aparece
/// em [unpricedParts] para que a tela possa avisar, em vez de sumir calada.
double partsRatePerKm(Vehicle vehicle) {
  var total = 0.0;
  for (final part in vehicle.parts) {
    total += partRatePerKm(part) ?? 0;
  }
  return total;
}

/// Nomes das peças que não dá para calcular.
///
/// Existe para a interface conseguir dizer *quais* peças ficaram de fora: uma
/// peça descartada em silêncio é custo que o entregador acha que provisionou.
List<String> unpricedParts(Vehicle vehicle) {
  return [
    for (final part in vehicle.parts)
      if (partRatePerKm(part) == null) part.name,
  ];
}

/// Custo total do veículo por quilômetro: combustível mais peças.
///
/// `null` quando o combustível não dá para calcular. Devolver só as peças
/// mostraria R$ 0,119/km como custo de um carro que gasta R$ 0,819 — errado por
/// sete vezes para menos, e para menos é o lado que engana.
double? totalRatePerKm(Vehicle vehicle) {
  final fuel = fuelRatePerKm(vehicle);
  if (fuel == null) return null;

  return fuel + partsRatePerKm(vehicle);
}

/// KM rodado na rota, ou `null` quando não dá para saber.
///
/// Mesma guarda que `routeCard.dart` já usa: diferença não positiva é dado
/// incompleto, não rota de zero quilômetro.
double? kmOf(NewRouteModal route) {
  final initial = route.kmInitial;
  final complete = route.kmFinal;
  if (initial == null || complete == null) return null;

  final total = complete - initial;
  return total > 0 ? total : null;
}

/// Calcula a provisão de uma rota, ou `null` quando não há como.
///
/// As guardas são as da planilha, `IF(AND($C3>0,$D3>0), …, 0)`: sem valor e sem
/// KM rodado não há custo a provisionar — é a linha do domingo parado.
///
/// [now] existe para o teste fixar o carimbo de `calculatedAt`.
RouteProvision? provisionFor(
  Vehicle vehicle,
  NewRouteModal route, {
  DateTime? now,
}) {
  final km = kmOf(route);
  if (km == null || route.value <= 0) return null;

  final fuelRate = fuelRatePerKm(vehicle);
  // Sem consumo informado, o combustível — 85% do custo — sairia como zero e o
  // lucro apareceria inflado. Melhor não haver número do que haver um errado.
  if (fuelRate == null) return null;

  final parts = <String, double>{};
  for (final part in vehicle.parts) {
    final rate = partRatePerKm(part);
    if (rate == null) continue;
    // `+=` e não `=`: duas peças com o mesmo nome somam em vez de uma apagar a
    // outra.
    parts[part.name] = (parts[part.name] ?? 0) + rate * km;
  }

  var totalParts = 0.0;
  for (final value in parts.values) {
    totalParts += value;
  }

  return RouteProvision(
    vehicleId: vehicle.id,
    km: km,
    fuel: fuelRate * km,
    parts: parts,
    totalParts: totalParts,
    calculatedAt: (now ?? DateTime.now()).toIso8601String(),
  );
}

/// Diferença de KM que conta como "o usuário mexeu no campo".
///
/// Um metro. Nenhuma edição real muda menos que isso, e comparar `double` com
/// `==` deixaria a decisão nas mãos do último bit da representação.
const _kmEpsilon = 0.001;

/// Decide o que acontece com a provisão quando a rota é salva.
///
/// É a regra que protege o histórico, e a razão de ela existir é o pilar do
/// app: a planilha recalcula o lucro de dias que já aconteceram toda vez que um
/// preço muda, e um lucro que muda depois do fato não é lucro.
///
/// | situação | resultado |
/// |---|---|
/// | rota não está concluída nem paga | `null` — ela voltou a não ter rodado |
/// | concluída, ainda sem provisão | calcula agora |
/// | concluída, mesmo KM e mesmo veículo | **mantém** o que já estava |
/// | concluída, KM ou veículo mudou | recalcula |
/// | sem veículo cadastrado | mantém o que havia; `null` se não havia |
///
/// A terceira linha é a que importa: corrigir o endereço de uma rota de junho
/// não pode reescrever a provisão dela com o preço de gasolina de hoje.
RouteProvision? resolveProvision({
  required NewRouteModal route,
  required RouteProvision? existing,
  required Vehicle? vehicle,
  DateTime? now,
}) {
  final done =
      route.status == StatusRoute.concluido || route.status == StatusRoute.pago;
  // Rota que voltou para agendada não rodou: manter o custo seria contabilizar
  // gasolina de uma viagem que não aconteceu.
  if (!done) return null;

  // Veículo excluído não apaga o que já foi calculado — a provisão é um valor
  // em reais, não um ponteiro para o veículo.
  if (vehicle == null) return existing;

  if (existing != null) {
    final km = kmOf(route);
    final sameKm = km != null && (km - existing.km).abs() < _kmEpsilon;

    if (sameKm && existing.vehicleId == vehicle.id) return existing;
  }

  return provisionFor(vehicle, route, now: now);
}
