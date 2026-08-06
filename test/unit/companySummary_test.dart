import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/companySummary.dart';
import 'package:iter/model/newRouteModal.dart';

/// Rota mínima; cada teste declara só o campo que está examinando.
NewRouteModal _route({
  String id = 'r1',
  StatusRoute status = StatusRoute.concluido,
  double value = 100,
  double? kmInitial,
  double? kmFinal,
  int? packages,
  int? stops,
  List<String>? adress,
  bool? isInsucesso,
  int? insucessoQnt,
  RouteProvision? provision,
}) {
  return NewRouteModal(
    id: id,
    company: Company.amazon,
    dateRoute: '01/08/2026',
    weekday: 6,
    status: status,
    value: value,
    kmInitial: kmInitial,
    kmFinal: kmFinal,
    packages: packages,
    stops: stops,
    adress: adress,
    startAt: DateTime(2026, 8, 1, 8),
    isInsucesso: isInsucesso,
    insucessoQnt: insucessoQnt,
    provision: provision,
    createdAt: '2026-08-01T09:00:00.000',
  );
}

/// A provisão da linha 3 de JUL: 46,9 km custaram R$ 38,43.
RouteProvision _provision({
  double km = 46.9,
  double fuel = 32.83,
  double totalParts = 5.596733,
}) {
  return RouteProvision(
    vehicleId: 'v1',
    km: km,
    fuel: fuel,
    parts: const {'Óleo': 0.938, 'Pneu': 1.876},
    totalParts: totalParts,
    calculatedAt: '2026-07-01T20:00:00.000',
  );
}

void main() {
  group('recorte: só rotas realizadas', () {
    test('agendada e em andamento ficam de fora', () {
      final summary = companySummary([
        _route(status: StatusRoute.concluido, value: 100),
        _route(status: StatusRoute.pago, value: 200),
        _route(status: StatusRoute.agendado, value: 999),
        _route(status: StatusRoute.andamento, value: 888),
      ]);

      expect(summary.routes, 2);
      expect(summary.value, 300);
    });

    test('lista vazia devolve zeros e nulls sem lançar', () {
      final summary = companySummary(const []);

      expect(summary.routes, 0);
      expect(summary.value, 0);
      expect(summary.profit, 0);
      expect(summary.uncalculatedValue, 0);
      expect(summary.km, isNull);
      expect(summary.packages, isNull);
      expect(summary.stops, isNull);
      expect(summary.failures, 0);
      expect(summary.failureRate, isNull);
      expect(summary.costPerKm, isNull);
      expect(summary.topBairro, isNull);
      expect(summary.bottomBairro, isNull);
      expect(summary.isEmpty, isTrue);
    });
  });

  group('lucro: líquido onde há cálculo, bruto onde não há', () {
    test('rota com provisão entra pelo lucro real', () {
      final summary = companySummary([
        _route(value: 152.50, kmInitial: 1000, kmFinal: 1046.9, provision: _provision()),
      ]);

      expect(summary.profit, closeTo(114.0732667, 0.001));
      expect(summary.uncalculatedValue, 0);
      expect(summary.hasUncalculated, isFalse);
    });

    test('rota sem provisão entra pelo valor bruto', () {
      final summary = companySummary([_route(value: 152.50)]);

      expect(summary.profit, 152.50);
      expect(summary.uncalculatedValue, 152.50);
      expect(summary.hasUncalculated, isTrue);
    });

    test('as duas somam no mesmo número, e a parte bruta é denunciada', () {
      final summary = companySummary([
        _route(id: 'a', value: 152.50, kmInitial: 1000, kmFinal: 1046.9, provision: _provision()),
        _route(id: 'b', value: 200),
      ]);

      // 114,07 (líquido) + 200,00 (bruto)
      expect(summary.profit, closeTo(314.0732667, 0.001));
      expect(summary.value, 352.50);
      // Sem este campo, ninguém saberia que R$ 200 do "lucro" é custo não
      // descontado.
      expect(summary.uncalculatedValue, 200);
    });

    test('todas com provisão zeram a ressalva', () {
      final summary = companySummary([
        _route(id: 'a', value: 152.50, kmInitial: 1000, kmFinal: 1046.9, provision: _provision()),
        _route(id: 'b', value: 152.50, kmInitial: 1000, kmFinal: 1046.9, provision: _provision()),
      ]);

      expect(summary.uncalculatedValue, 0);
      expect(summary.hasUncalculated, isFalse);
    });

    test('rota não realizada não entra nem no lucro nem na ressalva', () {
      final summary = companySummary([
        _route(status: StatusRoute.agendado, value: 500),
      ]);

      expect(summary.profit, 0);
      expect(summary.uncalculatedValue, 0);
    });
  });

  group('KM rodado', () {
    test('soma só as que informaram', () {
      final summary = companySummary([
        _route(id: 'a', kmInitial: 1000, kmFinal: 1046.9),
        _route(id: 'b', kmInitial: 2000, kmFinal: 2050),
        _route(id: 'c'),
      ]);

      expect(summary.km, closeTo(96.9, 1e-9));
    });

    test('nenhuma informou devolve null, não zero', () {
      expect(companySummary([_route()]).km, isNull);
    });

    test('diferença zero ou negativa é dado incompleto e não entra', () {
      final summary = companySummary([
        _route(id: 'a', kmInitial: 1000, kmFinal: 1000),
        _route(id: 'b', kmInitial: 1000, kmFinal: 900),
      ]);

      expect(summary.km, isNull);
    });
  });

  group('pacotes, paradas e insucessos', () {
    test('somam só o informado', () {
      final summary = companySummary([
        _route(id: 'a', packages: 40, stops: 30),
        _route(id: 'b', packages: 20, stops: 15),
        _route(id: 'c'),
      ]);

      expect(summary.packages, 60);
      expect(summary.stops, 45);
    });

    test('ninguém informou devolve null, não zero', () {
      final summary = companySummary([_route()]);

      expect(summary.packages, isNull);
      expect(summary.stops, isNull);
    });

    test('insucesso zero é informação, não ausência', () {
      // Diferente de pacotes: "não teve insucesso" é um fato, e mostrar `—`
      // sugeriria que ninguém preencheu.
      expect(companySummary([_route()]).failures, 0);
    });

    test('switch desligado manda, mesmo com quantidade gravada', () {
      final summary = companySummary([
        _route(isInsucesso: false, insucessoQnt: 5),
      ]);

      expect(summary.failures, 0);
    });

    test('switch ligado sem quantidade vale 1', () {
      expect(companySummary([_route(isInsucesso: true)]).failures, 1);
    });
  });

  group('taxa de insucesso', () {
    test('é a porcentagem sobre os pacotes', () {
      final summary = companySummary([
        _route(packages: 100, isInsucesso: true, insucessoQnt: 3),
      ]);

      expect(summary.failureRate, closeTo(3, 1e-9));
    });

    test('sem pacotes informados é null, sem divisão por zero', () {
      final summary = companySummary([
        _route(isInsucesso: true, insucessoQnt: 3),
      ]);

      expect(summary.failureRate, isNull);
    });

    test('zero insucesso em pacotes informados é 0%, não null', () {
      expect(companySummary([_route(packages: 100)]).failureRate, 0);
    });
  });

  group('custo por km', () {
    test('é o custo total dividido pelo KM das rotas com provisão', () {
      final summary = companySummary([
        _route(value: 152.50, kmInitial: 1000, kmFinal: 1046.9, provision: _provision()),
      ]);

      // 38,426733 / 46,9 = 0,8193/km — a taxa do veículo, de volta.
      expect(summary.costPerKm, closeTo(0.8193333, 0.0001));
    });

    test('rota sem provisão não entra em nenhum dos dois lados', () {
      final summary = companySummary([
        _route(id: 'a', kmInitial: 1000, kmFinal: 1046.9, provision: _provision()),
        // 500 km sem provisão: se entrassem no divisor, o custo por km cairia
        // para um sexto do real — e errar para menos num custo é o lado que
        // engana.
        _route(id: 'b', kmInitial: 0, kmFinal: 500),
      ]);

      expect(summary.costPerKm, closeTo(0.8193333, 0.0001));
    });

    test('nenhuma rota com provisão devolve null', () {
      final summary = companySummary([
        _route(kmInitial: 1000, kmFinal: 1046.9),
      ]);

      expect(summary.costPerKm, isNull);
    });

    test('provisão com KM zero não vira divisão por zero', () {
      final summary = companySummary([
        _route(provision: _provision(km: 0, fuel: 0, totalParts: 0)),
      ]);

      expect(summary.costPerKm, isNull);
    });
  });

  group('bairros', () {
    test('mais e menos rodado saem do ranking', () {
      final summary = companySummary([
        _route(id: 'a', adress: ['Aldeota', 'Centro']),
        _route(id: 'b', adress: ['Aldeota']),
        _route(id: 'c', adress: ['Aldeota', 'Messejana']),
        _route(id: 'd', adress: ['Centro']),
      ]);

      expect(summary.topBairro, 'Aldeota'); // 3
      expect(summary.bottomBairro, 'Messejana'); // 1
    });

    test('com um bairro só, os dois são o mesmo', () {
      // Quem decide não repetir na tela é o card.
      final summary = companySummary([_route(adress: ['Aldeota'])]);

      expect(summary.topBairro, 'Aldeota');
      expect(summary.bottomBairro, 'Aldeota');
    });

    test('sem bairro nenhum devolve null nos dois', () {
      final summary = companySummary([_route()]);

      expect(summary.topBairro, isNull);
      expect(summary.bottomBairro, isNull);
    });

    test('bairro de rota não realizada não conta', () {
      // Bairro "rodado" numa rota que não saiu não é verdade.
      final summary = companySummary([
        _route(id: 'a', adress: ['Aldeota']),
        _route(id: 'b', status: StatusRoute.agendado, adress: ['Barra do Ceará']),
      ]);

      expect(summary.topBairro, 'Aldeota');
      expect(summary.bottomBairro, 'Aldeota');
    });
  });

  group('byCompany — o agrupamento da tela', () {
    test('separa as rotas por empresa mantendo as três', () {
      final routes = [
        _route(id: 'a', value: 100).copyForCompany(Company.amazon),
        _route(id: 'b', value: 200).copyForCompany(Company.mercadolivre),
        _route(id: 'c', value: 300).copyForCompany(Company.mercadolivre),
      ];

      final byCompany = summaryByCompany(routes);

      expect(byCompany.length, Company.values.length);
      expect(byCompany[Company.amazon]!.value, 100);
      expect(byCompany[Company.mercadolivre]!.value, 500);
      // Shopee sem rota continua no mapa, zerada: o card não some da tela.
      expect(byCompany[Company.shopee]!.routes, 0);
      expect(byCompany[Company.shopee]!.isEmpty, isTrue);
    });
  });
}

/// Açúcar só para o teste de agrupamento.
extension on NewRouteModal {
  NewRouteModal copyForCompany(Company company) => NewRouteModal(
    id: id,
    company: company,
    dateRoute: dateRoute,
    weekday: weekday,
    status: status,
    value: value,
    startAt: startAt,
    createdAt: createdAt,
  );
}
