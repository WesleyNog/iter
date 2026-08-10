import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/vehicleCost.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/vehicle.dart';

/// A Fiorino da planilha. [fuelPrice] existe para simular "o preço subiu
/// depois", que é o cenário que esta regra toda existe para proteger.
Vehicle _fiorino({String id = 'v1', double? fuelPrice = 7.0}) {
  return Vehicle(
    id: id,
    type: VehicleType.carro,
    brandCode: '21',
    brandName: 'Fiat',
    modelCode: '1',
    modelName: 'Fiorino',
    fuel: FuelType.flex,
    fuelPrice: fuelPrice,
    consumption: 10,
    parts: Vehicle.defaultParts(VehicleType.carro),
    createdAt: '2026-01-01T00:00:00.000',
  );
}

NewRouteModal _route({
  StatusRoute status = StatusRoute.concluido,
  double value = 152.50,
  double? kmInitial = 1000,
  double? kmFinal = 1046.9,
  RouteProvision? provision,
}) {
  return NewRouteModal(
    id: 'r1',
    company: Company.amazon,
    dateRoute: '01/07/2026',
    weekday: 3,
    status: status,
    value: value,
    kmInitial: kmInitial,
    kmFinal: kmFinal,
    startAt: DateTime(2026, 7, 1, 8),
    provision: provision,
    createdAt: '2026-07-01T08:00:00.000',
  );
}

final _fixedNow = DateTime(2026, 7, 1, 20);

void main() {
  group('resolveProvision — quando o retrato é tirado', () {
    test('rota agendada não provisiona', () {
      final resolved = resolveProvision(
        route: _route(status: StatusRoute.agendado),
        existing: null,
        vehicle: _fiorino(),
      );

      expect(resolved, isNull);
    });

    test('voltar para agendada apaga a provisão que existia', () {
      // A rota deixou de ter rodado; manter o custo dela seria contabilizar
      // gasolina de uma viagem que não aconteceu.
      final existing = provisionFor(_fiorino(), _route(), now: _fixedNow);

      final resolved = resolveProvision(
        route: _route(status: StatusRoute.andamento),
        existing: existing,
        vehicle: _fiorino(),
      );

      expect(resolved, isNull);
    });

    test('concluir pela primeira vez calcula', () {
      final resolved = resolveProvision(
        route: _route(),
        existing: null,
        vehicle: _fiorino(),
        now: _fixedNow,
      )!;

      expect(resolved.fuel, closeTo(32.83, 0.001));
      expect(resolved.totalParts, closeTo(5.596733, 0.001));
      expect(resolved.profitFrom(152.50), closeTo(114.0732667, 0.001));
    });

    test('status pago também provisiona', () {
      final resolved = resolveProvision(
        route: _route(status: StatusRoute.pago),
        existing: null,
        vehicle: _fiorino(),
      );

      expect(resolved, isNotNull);
    });

    test('a ida sem rota provisiona: o KM até o CD é KM rodado', () {
      // 20 km de ida e volta ao CD, a R$ 0,70/km de gasolina.
      final resolved = resolveProvision(
        route: _route(
          status: StatusRoute.semRota,
          value: 40,
          kmInitial: 2000,
          kmFinal: 2020,
        ),
        existing: null,
        vehicle: _fiorino(),
        now: _fixedNow,
      )!;

      expect(resolved.km, closeTo(20, 1e-9));
      expect(resolved.fuel, closeTo(14.0, 0.001));
      // Ela pagou R$ 40 e custou R$ 16,38: sobraram R$ 23,62. Sem provisão, a
      // gasolina dessa viagem simplesmente não existiria em lugar nenhum.
      expect(resolved.profitFrom(40), closeTo(23.6132, 0.001));
    });

    test('o congelamento vale para a ida também', () {
      final junho = provisionFor(
        _fiorino(),
        _route(status: StatusRoute.semRota, kmInitial: 2000, kmFinal: 2020),
        now: _fixedNow,
      );

      final resolved = resolveProvision(
        route: _route(status: StatusRoute.semRota, kmInitial: 2000, kmFinal: 2020),
        existing: junho,
        // A gasolina subiu de R$ 7,00 para R$ 9,00 desde então.
        vehicle: _fiorino(fuelPrice: 9.0),
      )!;

      expect(identical(resolved, junho), isTrue);
      expect(resolved.fuel, closeTo(14.0, 0.001));
    });

    test(
      'O TESTE QUE PROTEGE O HISTÓRICO: preço mudou, KM igual → mantém',
      () {
        // Este é o pilar do app. A planilha recalcula julho com o preço de
        // hoje toda vez que é aberta; aqui, julho é julho.
        final julho = provisionFor(_fiorino(), _route(), now: _fixedNow)!;

        final resolved = resolveProvision(
          route: _route(provision: julho),
          existing: julho,
          // Setembro: o combustível subiu de R$ 7,00 para R$ 9,00.
          vehicle: _fiorino(fuelPrice: 9.0),
        )!;

        expect(resolved.fuel, closeTo(32.83, 0.001)); // e não 42,21
        expect(resolved.calculatedAt, julho.calculatedAt);
        expect(resolved.totalParts, closeTo(julho.totalParts, 1e-9));
      },
    );

    test('editar outro campo da rota não mexe na provisão', () {
      // Corrigir o bairro de uma rota de junho não pode reescrever o custo
      // dela com a gasolina de hoje.
      final antiga = provisionFor(_fiorino(), _route(), now: _fixedNow)!;

      final resolved = resolveProvision(
        route: _route(provision: antiga, value: 200),
        existing: antiga,
        vehicle: _fiorino(fuelPrice: 9.0),
      )!;

      expect(resolved.calculatedAt, antiga.calculatedAt);
      expect(resolved.fuel, closeTo(antiga.fuel, 1e-9));
    });

    test('corrigir o KM recalcula — o retrato antigo virou mentira', () {
      final antiga = provisionFor(_fiorino(), _route(), now: _fixedNow)!;

      final resolved = resolveProvision(
        route: _route(provision: antiga, kmFinal: 1100),
        existing: antiga,
        vehicle: _fiorino(),
      )!;

      expect(resolved.km, closeTo(100, 1e-9));
      expect(resolved.fuel, closeTo(70, 0.001));
    });

    test('trocar de veículo recalcula', () {
      final antiga = provisionFor(_fiorino(), _route(), now: _fixedNow)!;

      final resolved = resolveProvision(
        route: _route(provision: antiga),
        existing: antiga,
        vehicle: _fiorino(id: 'v2', fuelPrice: 9.0),
      )!;

      expect(resolved.vehicleId, 'v2');
      expect(resolved.fuel, closeTo(42.21, 0.001));
    });

    test('sem veículo cadastrado não provisiona, mas não lança', () {
      final resolved = resolveProvision(
        route: _route(),
        existing: null,
        vehicle: null,
      );

      expect(resolved, isNull);
    });

    test('veículo excluído não apaga a provisão já gravada', () {
      // O custo é um valor em reais, não um ponteiro para o veículo.
      final antiga = provisionFor(_fiorino(), _route(), now: _fixedNow)!;

      final resolved = resolveProvision(
        route: _route(provision: antiga),
        existing: antiga,
        vehicle: null,
      );

      expect(resolved, same(antiga));
    });

    test('apagar o KM apaga a provisão em vez de manter o valor velho', () {
      final antiga = provisionFor(_fiorino(), _route(), now: _fixedNow)!;

      final resolved = resolveProvision(
        route: _route(provision: antiga, kmFinal: null),
        existing: antiga,
        vehicle: _fiorino(),
      );

      expect(resolved, isNull);
    });
  });

  group('NewRouteModal.provision — ida e volta', () {
    test('grava e lê o mapa aninhado', () {
      final route = _route(
        provision: provisionFor(_fiorino(), _route(), now: _fixedNow),
      );

      final back = NewRouteModal.fromMap(route.toMap());

      expect(back.provision, isNotNull);
      expect(back.provision!.fuel, closeTo(32.83, 0.001));
      expect(back.provision!.parts['Pneu'], closeTo(1.876, 0.001));
      expect(back.provision!.vehicleId, 'v1');
    });

    test('rota antiga, sem o campo, devolve null sem lançar', () {
      final map = _route().toMap()..remove('provision');

      expect(NewRouteModal.fromMap(map).provision, isNull);
    });

    test('campo corrompido não derruba a leitura da rota', () {
      final map = _route().toMap()..['provision'] = 'lixo';

      expect(() => NewRouteModal.fromMap(map), returnsNormally);
      expect(NewRouteModal.fromMap(map).provision, isNull);
    });

    test('lucro é derivado do valor da rota, não gravado', () {
      final route = _route(
        provision: provisionFor(_fiorino(), _route(), now: _fixedNow),
      );

      expect(route.profit, closeTo(114.0732667, 0.001));
      expect(route.toMap().containsKey('profit'), isFalse);
    });

    test('rota sem provisão não tem lucro calculável', () {
      // `null` e não `value`: sem saber o custo, "lucro = tudo que entrou"
      // seria a mentira mais cara que o app poderia contar.
      expect(_route().profit, isNull);
    });
  });
}
