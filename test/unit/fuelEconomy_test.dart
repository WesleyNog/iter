import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/fuelEconomy.dart';
import 'package:iter/model/supply.dart';

/// Abastecimento do veículo `v1`, gasolina, salvo em ordem de data.
Supply _s({
  required String id,
  required String date,
  double? odometer,
  double? liters = 40,
  double value = 250,
  SupplyFuel fuel = SupplyFuel.gasolina,
  String? vehicleId = 'v1',
}) {
  return Supply(
    id: id,
    vehicleId: vehicleId,
    value: value,
    liters: liters,
    fuel: fuel,
    odometer: odometer,
    date: date,
    createdAt: date,
  );
}

/// Os três do exemplo da spec.
List<Supply> get _tres => [
  _s(id: 'a', date: '2026-08-01T10:00:00.000', odometer: 128000, liters: 40),
  _s(id: 'b', date: '2026-08-05T10:00:00.000', odometer: 128400, liters: 35),
  _s(id: 'c', date: '2026-08-10T10:00:00.000', odometer: 128800, liters: 38),
];

EconomyResult _gasolina(List<Supply> supplies) =>
    measuredEconomy(supplies, vehicleId: 'v1')[SupplyFuel.gasolina]!;

void main() {
  group('O TESTE ÂNCORA', () {
    test('os três do exemplo dão 10,96 km/l', () {
      final r = _gasolina(_tres);

      expect(r.gap, isNull);
      expect(r.economy!.km, closeTo(800, 1e-9));
      expect(r.economy!.liters, closeTo(73, 1e-9));
      expect(r.economy!.kmPerLiter, closeTo(10.9589, 0.001));
      expect(r.economy!.fills, 3);
      expect(r.economy!.fuel, SupplyFuel.gasolina);
    });

    test('o primeiro abastecimento não entra nos litros', () {
      // Ele encheu o tanque que rodou a distância **anterior** à janela;
      // contá-lo faria o consumo parecer pior do que é.
      final r = _gasolina(_tres);

      expect(r.economy!.liters, 73); // 35 + 38, sem os 40 do primeiro
      expect(r.economy!.liters, isNot(113));
    });
  });

  group('quanto dado é preciso', () {
    test('dois registros já dão número', () {
      final r = _gasolina([
        _s(id: 'a', date: '2026-08-01T10:00:00.000', odometer: 128000),
        _s(id: 'b', date: '2026-08-05T10:00:00.000', odometer: 128400, liters: 35),
      ]);

      expect(r.gap, isNull);
      expect(r.economy!.kmPerLiter, closeTo(400 / 35, 1e-9));
      expect(r.economy!.fills, 2);
    });

    test('um só diz que falta mais um', () {
      final r = _gasolina([
        _s(id: 'a', date: '2026-08-01T10:00:00.000', odometer: 128000),
      ]);

      expect(r.gap, EconomyGap.faltamRegistros);
      expect(r.missing, 1);
      expect(r.economy, isNull);
    });

    test('nenhum com KM diz que faltam dois', () {
      final r = _gasolina([
        _s(id: 'a', date: '2026-08-01T10:00:00.000'),
        _s(id: 'b', date: '2026-08-05T10:00:00.000'),
      ]);

      expect(r.gap, EconomyGap.semKm);
      expect(r.missing, 2);
    });

    test('combustível sem abastecimento nenhum não aparece no mapa', () {
      // Mostrar "Etanol: informe o KM" para quem nunca abasteceu etanol é
      // ruído.
      final mapa = measuredEconomy(_tres, vehicleId: 'v1');

      expect(mapa.keys, [SupplyFuel.gasolina]);
    });
  });

  group('o caso que faria o número mentir para melhor', () {
    test('abastecimento sem litros DENTRO da janela invalida', () {
      // Aquele combustível entrou no tanque e não entraria na conta: o km/l
      // sairia melhor do que é, a provisão de gasolina menor, e o lucro
      // superestimado em toda rota.
      final r = _gasolina([
        _s(id: 'a', date: '2026-08-01T10:00:00.000', odometer: 128000),
        _s(id: 'b', date: '2026-08-05T10:00:00.000', liters: null),
        _s(id: 'c', date: '2026-08-10T10:00:00.000', odometer: 128800, liters: 38),
      ]);

      expect(r.gap, EconomyGap.litrosFaltando);
      expect(r.economy, isNull);
    });

    test('sem litros no PRIMEIRO não atrapalha — ele não entra na conta', () {
      final r = _gasolina([
        _s(id: 'a', date: '2026-08-01T10:00:00.000', odometer: 128000, liters: null),
        _s(id: 'b', date: '2026-08-05T10:00:00.000', odometer: 128400, liters: 35),
      ]);

      expect(r.gap, isNull);
      expect(r.economy!.liters, 35);
    });

    test('sem litros FORA da janela não atrapalha', () {
      final r = _gasolina([
        ..._tres,
        // Depois do último com KM: está fora da janela.
        _s(id: 'd', date: '2026-08-20T10:00:00.000', liters: null),
      ]);

      expect(r.gap, isNull);
      expect(r.economy!.kmPerLiter, closeTo(10.9589, 0.001));
    });
  });

  group('hodômetro inconsistente', () {
    test('KM igual não vira divisão por zero', () {
      final r = _gasolina([
        _s(id: 'a', date: '2026-08-01T10:00:00.000', odometer: 128000),
        _s(id: 'b', date: '2026-08-05T10:00:00.000', odometer: 128000, liters: 35),
      ]);

      expect(r.gap, EconomyGap.kmNaoAvanca);
      expect(r.economy, isNull);
    });

    test('KM que anda para trás não vira consumo negativo', () {
      final r = _gasolina([
        _s(id: 'a', date: '2026-08-01T10:00:00.000', odometer: 128800),
        _s(id: 'b', date: '2026-08-05T10:00:00.000', odometer: 128000, liters: 35),
      ]);

      expect(r.gap, EconomyGap.kmNaoAvanca);
    });

    test('erro de digitação no meio é denunciado', () {
      // 12.880 em vez de 128.800: as pontas fecham, mas o dado está errado e
      // calcular em cima disso seria fingir que está tudo bem.
      final r = _gasolina([
        _s(id: 'a', date: '2026-08-01T10:00:00.000', odometer: 128000),
        _s(id: 'b', date: '2026-08-05T10:00:00.000', odometer: 12880, liters: 35),
        _s(id: 'c', date: '2026-08-10T10:00:00.000', odometer: 128800, liters: 38),
      ]);

      expect(r.gap, EconomyGap.kmNaoAvanca);
    });
  });

  group('separação por combustível', () {
    test('gasolina e etanol saem com os próprios litros', () {
      final mapa = measuredEconomy([
        _s(id: 'g1', date: '2026-08-01T10:00:00.000', odometer: 128000),
        _s(id: 'g2', date: '2026-08-05T10:00:00.000', odometer: 128400, liters: 35),
        _s(id: 'e1', date: '2026-08-06T10:00:00.000', odometer: 128500, liters: 40, fuel: SupplyFuel.etanol),
        _s(id: 'e2', date: '2026-08-12T10:00:00.000', odometer: 128900, liters: 50, fuel: SupplyFuel.etanol),
      ], vehicleId: 'v1');

      expect(mapa.length, 2);
      // Gasolina: 128.400 − 128.000 = 400 km ÷ 35 L
      expect(mapa[SupplyFuel.gasolina]!.economy!.kmPerLiter, closeTo(400 / 35, 1e-9));
      // Etanol: 128.900 − 128.500 = 400 km ÷ 50 L — bem menos por litro
      expect(mapa[SupplyFuel.etanol]!.economy!.kmPerLiter, closeTo(400 / 50, 1e-9));
    });

    test('a média única seria enganosa, e por isso não existe', () {
      // Se misturasse, daria 800 ÷ 85 = 9,41 — que não descreve nem a gasolina
      // (11,43) nem o etanol (8,00).
      final mapa = measuredEconomy([
        _s(id: 'g1', date: '2026-08-01T10:00:00.000', odometer: 128000),
        _s(id: 'g2', date: '2026-08-05T10:00:00.000', odometer: 128400, liters: 35),
        _s(id: 'e1', date: '2026-08-06T10:00:00.000', odometer: 128500, liters: 40, fuel: SupplyFuel.etanol),
        _s(id: 'e2', date: '2026-08-12T10:00:00.000', odometer: 128900, liters: 50, fuel: SupplyFuel.etanol),
      ], vehicleId: 'v1');

      for (final r in mapa.values) {
        expect(r.economy!.kmPerLiter, isNot(closeTo(9.41, 0.1)));
      }
    });
  });

  group('de quem é o abastecimento', () {
    test('abastecimento de outro veículo não entra', () {
      final r = _gasolina([
        ..._tres,
        _s(id: 'moto', date: '2026-08-11T10:00:00.000', odometer: 9000, liters: 12, vehicleId: 'v2'),
      ]);

      expect(r.economy!.kmPerLiter, closeTo(10.9589, 0.001));
    });

    test('abastecimento sem veículo não entra', () {
      final r = _gasolina([
        ..._tres,
        _s(id: 'orfao', date: '2026-08-11T10:00:00.000', odometer: 999999, liters: 50, vehicleId: null),
      ]);

      expect(r.economy!.kmPerLiter, closeTo(10.9589, 0.001));
    });
  });

  test('lista vazia devolve mapa vazio, sem lançar', () {
    expect(measuredEconomy(const [], vehicleId: 'v1'), isEmpty);
  });

  test('a ordem da lista de entrada não importa', () {
    // O Firestore devolve na ordem que quiser; quem ordena é a função.
    final embaralhado = [_tres[2], _tres[0], _tres[1]];

    expect(
      _gasolina(embaralhado).economy!.kmPerLiter,
      closeTo(10.9589, 0.001),
    );
  });

  group('o que a tela diz quando não dá', () {
    test('cada tipo de problema pede uma coisa diferente', () {
      // São quatro motivos e **três** frases, de propósito: `semKm` e
      // `faltamRegistros` pedem a mesma coisa — mais registros com KM — e
      // diferem só na contagem. O que não pode é informar KM, informar litros e
      // conferir digitação virarem uma mensagem só: cada uma manda o usuário
      // fazer algo diferente.
      final frases = {
        for (final g in EconomyGap.values) economyGapMessage(g, 2),
      };

      expect(frases.length, 3);
      expect(
        economyGapMessage(EconomyGap.semKm, 2),
        economyGapMessage(EconomyGap.faltamRegistros, 2),
      );
      for (final g in EconomyGap.values) {
        expect(economyGapMessage(g, 2), isNotEmpty);
      }
    });

    test('a contagem entra na frase, no singular e no plural', () {
      expect(
        economyGapMessage(EconomyGap.faltamRegistros, 1),
        contains('mais 1 abastecimento para'),
      );
      expect(
        economyGapMessage(EconomyGap.semKm, 2),
        contains('mais 2 abastecimentos'),
      );
    });

    test('litros faltando pede litros, não KM', () {
      final frase = economyGapMessage(EconomyGap.litrosFaltando, 0);

      expect(frase, contains('litros'));
      expect(frase, isNot(contains('KM em mais')));
    });

    test('hodômetro inconsistente manda conferir, não registrar mais', () {
      final frase = economyGapMessage(EconomyGap.kmNaoAvanca, 0);

      expect(frase, contains('Confira'));
      expect(frase, isNot(contains('mais')));
    });
  });

  group('formatEconomy', () {
    test('duas casas, com vírgula', () {
      expect(formatEconomy(10.9589), '10,96 km/l');
      expect(formatEconomy(8), '8,00 km/l');
    });
  });

  group('periodEconomy — o recorte do Resumo', () {
    test('com um veículo só, calcula normalmente', () {
      final mapa = periodEconomy(_tres)!;

      expect(mapa[SupplyFuel.gasolina]!.economy!.kmPerLiter, closeTo(10.9589, 0.001));
    });

    test('com dois veículos no período, devolve null', () {
      // Consumo é propriedade do carro: um número único para Fit e moto não
      // descreveria nenhum dos dois.
      final mapa = periodEconomy([
        ..._tres,
        _s(id: 'm1', date: '2026-08-03T10:00:00.000', odometer: 9000, liters: 12, vehicleId: 'v2'),
      ]);

      expect(mapa, isNull);
    });

    test('abastecimento sem veículo bloqueia', () {
      // Poderia ser de qualquer carro; ignorá-lo repetiria o erro dos litros
      // faltando — combustível fora da conta, km/l inflado.
      final mapa = periodEconomy([
        ..._tres,
        _s(id: 'orfao', date: '2026-08-03T10:00:00.000', liters: 30, vehicleId: null),
      ]);

      expect(mapa, isNull);
    });

    test('período vazio devolve null, sem lançar', () {
      expect(periodEconomy(const []), isNull);
    });
  });
}
