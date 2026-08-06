/// Quando um **gasto** deve corrigir o cadastro do veículo.
///
/// Duas frentes, a mesma ideia: o abastecimento sabe o preço real do litro, e a
/// manutenção sabe o preço real da peça. Os dois campos correspondentes no
/// veículo nasceram como chute digitado uma vez, e é deles que sai a provisão
/// de toda rota.
///
/// **Nada aqui atualiza nada.** Estas funções só respondem "vale perguntar?" —
/// quem decide é sempre o dono, porque mexer nesses números muda o custo por km
/// das próximas rotas.
///
/// Ficam fora da tela porque decidem coisa demais para viver dentro de um
/// `build`, e porque a próxima spec — consumo real em km/l e lembrete de
/// manutenção por KM — mora aqui.
library;

import 'package:iter/Utils/fuelEconomy.dart';
import 'package:iter/Utils/text.dart';
import 'package:iter/model/maintenance.dart';
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

// ------------------------------------------------------- manutenção → peça

/// Diferença de preço abaixo da qual não vale perguntar: um centavo.
///
/// Mais folgado que o do litro porque peça custa centenas de reais e o valor
/// vem de uma divisão exata (R$ 2.400 ÷ 4), não de uma medição.
const _partEpsilon = 0.01;

/// A peça do cadastro que corresponde ao item da manutenção, ou `null`.
///
/// A comparação é **normalizada** — sem acento e sem caixa — porque a lista de
/// peças do veículo é editável: quem digitou "OLEO" ou "óleo" ao criar uma peça
/// nova continua sendo entendido.
///
/// Renomear a peça para algo diferente (`Freio` → `Pastilha`) quebra o vínculo
/// de propósito: aí são coisas diferentes, e adivinhar seria pior do que não
/// oferecer nada.
MaintenancePart? matchingPart(Vehicle vehicle, MaintenanceItem item) {
  final wanted = item.vehiclePartName;
  if (wanted == null) return null;

  final key = normalizeKey(wanted);
  for (final part in vehicle.parts) {
    if (normalizeKey(part.name) == key) return part;
  }

  return null;
}

/// Preço por unidade que esta manutenção sugere: `valor ÷ quantidade`.
///
/// R$ 2.400 de pneu num carro que troca quatro por vez são R$ 600 cada — e é
/// **por unidade** que o cadastro guarda, porque foi assim que a planilha
/// sempre fez (`=(X11/Y11)*4`).
///
/// A conta assume que ele trocou o jogo inteiro. Trocar dois dos quatro daria
/// um valor errado, e a defesa é a tela **mostrar a divisão** antes de
/// perguntar — nunca atualizar sozinho.
double? unitPriceFor(Vehicle vehicle, Maintenance maintenance) {
  final part = matchingPart(vehicle, maintenance.item);
  if (part == null || part.quantity <= 0) return null;
  if (maintenance.value <= 0) return null;

  return maintenance.value / part.quantity;
}

/// Se vale oferecer a correção do preço da peça.
///
/// Não oferece quando:
///
/// - não há veículo;
/// - a ação é **Reparo** — consertar um pneu por R$ 80 não é o preço de um pneu
///   novo, e é exatamente para essa distinção que o toggle da tela existe;
/// - o item não tem peça correspondente (Funilaria, Revisão, Outros…);
/// - o veículo não tem uma peça com aquele nome;
/// - o preço já é praticamente o mesmo.
bool shouldOfferPartUpdate(Vehicle? vehicle, Maintenance maintenance) {
  if (vehicle == null) return false;
  if (maintenance.action != MaintenanceAction.substituicao) return false;

  final unit = unitPriceFor(vehicle, maintenance);
  if (unit == null || unit <= 0) return false;

  final current = matchingPart(vehicle, maintenance.item)?.price;
  if (current != null && (current - unit).abs() < _partEpsilon) return false;

  return true;
}

/// O veículo com o preço da peça corrigido.
///
/// Devolve o **mesmo** veículo quando não há peça correspondente: assim quem
/// chama não precisa checar antes, e um caminho novo no futuro não consegue
/// gravar preço na peça errada.
///
/// Só o preço muda. Vida útil e quantidade continuam sendo o que o dono
/// configurou — a manutenção sabe quanto custou, não quanto vai durar.
Vehicle withPartPrice(
  Vehicle vehicle,
  MaintenanceItem item,
  double unitPrice,
) {
  final target = matchingPart(vehicle, item);
  if (target == null || unitPrice <= 0) return vehicle;

  return vehicle.copyWith(
    parts: [
      for (final part in vehicle.parts)
        identical(part, target) ? part.copyWith(price: unitPrice) : part,
    ],
  );
}

// -------------------------------------------------- abastecimentos → consumo

/// Mínimo de abastecimentos para oferecer o consumo ao cadastro.
///
/// A média acumulada assume tanque no mesmo nível nas duas pontas, e o erro
/// encolhe conforme os litros somam. Com dois registros o número já **aparece**
/// — ver cedo ajuda —, mas mudar a provisão de toda rota futura com uma leitura
/// só seria decidir no ruído.
const _minimumFills = 3;

/// Meio décimo de km/l: metade de um por cento num valor perto de dez. Abaixo
/// disso a diferença não muda decisão nenhuma e a pergunta vira incômodo.
const _consumptionEpsilon = 0.05;

/// Se vale oferecer a correção do consumo do veículo.
///
/// Terceira e última das três: preço do litro, preço da peça e agora o
/// consumo. Com os três medidos, o custo por km da provisão deixa de ter chute.
///
/// Não oferece quando:
///
/// - não há veículo;
/// - menos de [_minimumFills] abastecimentos sustentam o número;
/// - o veículo **não é flex** e o combustível medido é outro — o consumo com
///   etanol não descreve um carro que roda a gasolina;
/// - o valor já é praticamente o mesmo.
///
/// Em veículo **flex** oferece para os dois: só o motorista sabe qual dos dois
/// o `consumption` dele representa, e a tela mostra qual foi o combustível para
/// a escolha ser informada.
bool shouldOfferConsumptionUpdate(Vehicle? vehicle, FuelEconomy economy) {
  if (vehicle == null) return false;
  if (economy.kmPerLiter <= 0) return false;
  if (economy.fills < _minimumFills) return false;

  final required = SupplyFuel.fromVehicle(vehicle.fuel);
  if (required != null && required != economy.fuel) return false;

  final current = vehicle.consumption;
  if (current != null &&
      (current - economy.kmPerLiter).abs() < _consumptionEpsilon) {
    return false;
  }

  return true;
}
