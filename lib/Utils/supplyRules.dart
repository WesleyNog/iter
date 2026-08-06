/// Regras que ligam um abastecimento ao veículo que o consumiu.
///
/// Ficam fora da tela porque decidem coisa demais para viver dentro de um
/// `build` — e porque a próxima spec, a do consumo real em km/l, mora aqui.
library;

import 'package:iter/model/supply.dart';
import 'package:iter/model/vehicle.dart';

/// Diferença de preço abaixo da qual não vale perguntar nada.
///
/// Meio centavo por litro: o preço vem de uma divisão (`valor ÷ litros`) e
/// quase nunca bate exatamente com o que está gravado. Sem esta folga, o app
/// perguntaria a cada abastecimento por causa da terceira casa decimal.
const _priceEpsilon = 0.005;

/// Se vale oferecer a atualização do preço do litro do veículo.
///
/// **Nunca automático.** Mudar `Vehicle.fuelPrice` muda o custo por km de toda
/// rota futura, e isso é decisão do dono — não efeito colateral de registrar
/// uma despesa.
///
/// Não oferece quando:
///
/// - não há veículo, ou não há litros para calcular o preço;
/// - o preço é praticamente o mesmo que já está gravado;
/// - o veículo **não é flex** e o combustível abastecido é outro. Encher o
///   tanque de diesel de um carro emprestado não pode reprecificar a gasolina
///   do carro dele.
///
/// Em veículo **flex**, oferece para gasolina e etanol: só o motorista sabe
/// qual dos dois o `fuelPrice` dele representa, e a tela mostra qual foi o
/// combustível para a escolha ser informada.
bool shouldOfferPriceUpdate(Vehicle? vehicle, Supply supply) {
  if (vehicle == null) return false;

  final price = supply.pricePerLiter;
  if (price == null || price <= 0) return false;

  final current = vehicle.fuelPrice;
  if (current != null && (current - price).abs() < _priceEpsilon) return false;

  // Combustível único: só faz sentido se for o mesmo líquido.
  final required = SupplyFuel.fromVehicle(vehicle.fuel);
  if (required != null && required != supply.fuel) return false;

  return true;
}
