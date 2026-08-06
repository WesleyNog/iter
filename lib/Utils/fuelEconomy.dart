/// Consumo **medido** em km/l, a partir dos abastecimentos já gravados.
///
/// Fecha o último dos três números do veículo que ainda era chute digitado: o
/// preço do litro veio do abastecimento, o preço da peça veio da manutenção, e
/// o consumo vem daqui. Com os três medidos, o custo por km da provisão deixa
/// de ser estimativa.
///
/// `cadastro-veiculo.md` registrou este dado como impossível de obter — nenhuma
/// API brasileira o tem, o INMETRO publica PDF. A saída era medir, e medir
/// exigia o hodômetro que o abastecimento passou a gravar.
///
/// Ver `docs/specs/consumo-real.md`.
library;

import 'package:iter/model/supply.dart';

/// Consumo medido de um combustível.
typedef FuelEconomy = ({
  SupplyFuel fuel,
  double kmPerLiter,
  double km,
  double liters,

  /// Quantos abastecimentos sustentam o número. Quanto maior, menor o erro —
  /// é por isso que a tela mostra com 2 e só oferece ao cadastro com 3.
  int fills,
});

/// Por que ainda não dá para calcular.
///
/// Cada caso tem uma frase própria na tela, porque cada um se resolve de um
/// jeito diferente: informar KM, informar litros, ou corrigir uma digitação.
enum EconomyGap {
  /// Nenhum abastecimento com hodômetro.
  semKm,

  /// Só um com hodômetro — falta o segundo para haver intervalo.
  faltamRegistros,

  /// Abastecimento sem litros **dentro** da janela: combustível entrou no
  /// tanque e não entraria na conta.
  litrosFaltando,

  /// Hodômetro que não avança entre os registros.
  kmNaoAvanca,
}

typedef EconomyResult = ({
  FuelEconomy? economy,
  EconomyGap? gap,

  /// Quantos registros com KM ainda faltam, para a tela dizer o que fazer.
  int missing,
});

/// Consumo medido do veículo, **um resultado por combustível**.
///
/// Só entram no mapa os combustíveis que têm algum abastecimento: mostrar
/// "Etanol: informe o KM" para quem nunca abasteceu etanol é ruído.
///
/// Separar não é preciosismo — etanol roda cerca de 30% menos por litro, e uma
/// média única ficaria entre os dois sem descrever nenhum.
Map<SupplyFuel, EconomyResult> measuredEconomy(
  List<Supply> supplies, {
  required String vehicleId,
}) {
  final byFuel = <SupplyFuel, List<Supply>>{};

  for (final supply in supplies) {
    // Abastecimento sem veículo, ou de outro, não diz nada sobre este carro.
    if (supply.vehicleId != vehicleId) continue;
    byFuel.putIfAbsent(supply.fuel, () => []).add(supply);
  }

  return {
    for (final entry in byFuel.entries)
      entry.key: _economyOf(entry.key, entry.value),
  };
}

EconomyResult _economyOf(SupplyFuel fuel, List<Supply> supplies) {
  // Ordem cronológica: o Firestore devolve na ordem que quiser, e a janela
  // depende de quem veio antes.
  final ordered = [...supplies]..sort((a, b) => a.date.compareTo(b.date));

  final anchors = <int>[
    for (var i = 0; i < ordered.length; i++)
      if (ordered[i].odometer != null) i,
  ];

  if (anchors.isEmpty) {
    return (economy: null, gap: EconomyGap.semKm, missing: 2);
  }
  if (anchors.length == 1) {
    return (economy: null, gap: EconomyGap.faltamRegistros, missing: 1);
  }

  // Hodômetro tem de subir a cada registro. Verificar **todos** e não só as
  // pontas pega o erro de digitação no meio (12.880 em vez de 128.800), que
  // deixaria as pontas fechando e o dado errado.
  for (var i = 1; i < anchors.length; i++) {
    final anterior = ordered[anchors[i - 1]].odometer!;
    final atual = ordered[anchors[i]].odometer!;
    if (atual <= anterior) {
      return (economy: null, gap: EconomyGap.kmNaoAvanca, missing: 0);
    }
  }

  final first = anchors.first;
  final last = anchors.last;
  final km = ordered[last].odometer! - ordered[first].odometer!;

  // A janela vai do primeiro ao último com hodômetro. O que estiver fora não
  // interessa: antes, foi consumido antes; depois, ainda não foi medido.
  var liters = 0.0;
  var fills = 1; // o primeiro conta como registro, mas não como litros

  for (var i = first + 1; i <= last; i++) {
    final supplyLiters = ordered[i].liters;
    // Sem litros aqui, entrou combustível que a conta não veria — e o km/l
    // sairia melhor do que é. Melhor não haver número.
    if (supplyLiters == null || supplyLiters <= 0) {
      return (economy: null, gap: EconomyGap.litrosFaltando, missing: 0);
    }

    liters += supplyLiters;
    fills++;
  }

  if (liters <= 0) {
    return (economy: null, gap: EconomyGap.litrosFaltando, missing: 0);
  }

  return (
    economy: (
      fuel: fuel,
      kmPerLiter: km / liters,
      km: km,
      liters: liters,
      fills: fills,
    ),
    gap: null,
    missing: 0,
  );
}

/// A frase que a tela mostra quando ainda não dá para calcular.
///
/// Uma por motivo, e não uma genérica: cada caso se resolve de um jeito
/// diferente — informar KM, informar litros, ou corrigir uma digitação. Uma
/// mensagem só faria o usuário tentar a coisa errada.
String economyGapMessage(EconomyGap gap, int missing) => switch (gap) {
  // Os dois primeiros são o mesmo pedido, mudando só a contagem.
  EconomyGap.semKm || EconomyGap.faltamRegistros =>
    missing == 1
        ? 'Informe o KM em mais 1 abastecimento para o app calcular seu consumo.'
        : 'Informe o KM em mais $missing abastecimentos para o app calcular '
              'seu consumo.',
  EconomyGap.litrosFaltando =>
    'Um abastecimento está sem os litros — informe para o consumo fechar.',
  EconomyGap.kmNaoAvanca =>
    'O KM informado não avança entre os abastecimentos. Confira os valores.',
};

/// `10,96 km/l`.
String formatEconomy(double kmPerLiter) =>
    '${kmPerLiter.toStringAsFixed(2).replaceAll('.', ',')} km/l';

/// Consumo de um recorte de abastecimentos — o mês do Resumo, por exemplo.
///
/// Devolve `null` quando os abastecimentos **não são todos do mesmo veículo**.
/// Consumo é propriedade do carro, não do período: com um Fit e uma moto no
/// mesmo mês, um número único não descreveria nenhum dos dois.
///
/// Abastecimento **sem veículo** também bloqueia. Ele poderia ser de qualquer
/// carro, e ignorá-lo repetiria o erro dos litros faltando: combustível que
/// entrou no tanque e ficou de fora da conta, inflando o km/l.
Map<SupplyFuel, EconomyResult>? periodEconomy(List<Supply> supplies) {
  if (supplies.isEmpty) return null;

  final vehicles = <String>{};
  for (final supply in supplies) {
    final id = supply.vehicleId;
    if (id == null || id.isEmpty) return null;
    vehicles.add(id);
  }

  if (vehicles.length != 1) return null;

  return measuredEconomy(supplies, vehicleId: vehicles.first);
}
