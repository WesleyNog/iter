import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeFilter.dart';
import 'package:iter/model/newRouteModal.dart';

/// Monta uma rota com o mínimo para o teste em questão — mesmo atalho de
/// `routeStats_test.dart`, para cada teste declarar só o campo que examina.
NewRouteModal _route({
  String id = 'r1',
  Company company = Company.mercadolivre,
  StatusRoute status = StatusRoute.concluido,
  double value = 100,
  DateTime? startAt,
  String? vehicleId,
}) {
  final start = startAt ?? DateTime(2026, 8, 10, 8);

  return NewRouteModal(
    id: id,
    company: company,
    dateRoute:
        '${start.day.toString().padLeft(2, '0')}/'
        '${start.month.toString().padLeft(2, '0')}/${start.year}',
    weekday: start.weekday,
    status: status,
    value: value,
    startAt: start,
    provision: vehicleId == null
        ? null
        : RouteProvision(
            vehicleId: vehicleId,
            km: 100,
            fuel: 50,
            parts: const {},
            totalParts: 0,
            calculatedAt: start.toIso8601String(),
          ),
    createdAt: start.toIso8601String(),
  );
}

List<String> _ids(List<NewRouteModal> routes) =>
    routes.map((route) => route.id).toList();

void main() {
  group('vazio ou completo passa tudo', () {
    final rotas = [
      _route(id: 'ml', company: Company.mercadolivre),
      _route(id: 'am', company: Company.amazon),
      _route(id: 'sh', company: Company.shopee),
    ];

    test('nenhuma empresa marcada mostra as três', () {
      expect(_ids(applyFilter(rotas, RouteFilter.none)), ['ml', 'am', 'sh']);
    });

    test('as três marcadas mostram o mesmo que nenhuma', () {
      const todas = RouteFilter(companies: {...Company.values});
      expect(_ids(applyFilter(rotas, todas)), ['ml', 'am', 'sh']);
    });

    test('uma marcada filtra só ela', () {
      const so = RouteFilter(companies: {Company.amazon});
      expect(_ids(applyFilter(rotas, so)), ['am']);
    });

    test('duas marcadas mostram as duas', () {
      const duas = RouteFilter(
        companies: {Company.amazon, Company.mercadolivre},
      );
      expect(_ids(applyFilter(rotas, duas)), ['ml', 'am']);
    });

    test('a mesma regra vale para status', () {
      final porStatus = [
        _route(id: 'ag', status: StatusRoute.agendado),
        _route(id: 'co', status: StatusRoute.concluido),
        _route(id: 'pa', status: StatusRoute.pago),
      ];

      expect(
        _ids(applyFilter(porStatus, RouteFilter.none)),
        ['ag', 'co', 'pa'],
      );
      expect(
        _ids(
          applyFilter(
            porStatus,
            const RouteFilter(statuses: {...StatusRoute.values}),
          ),
        ),
        ['ag', 'co', 'pa'],
      );
      expect(
        _ids(
          applyFilter(
            porStatus,
            const RouteFilter(
              statuses: {StatusRoute.concluido, StatusRoute.pago},
            ),
          ),
        ),
        ['co', 'pa'],
      );
    });
  });

  group('marcar e desmarcar', () {
    test('marcar o desmarcado adiciona', () {
      final filtro = RouteFilter.none.toggleCompany(Company.amazon);
      expect(filtro.companies, {Company.amazon});
    });

    test('tocar no marcado desmarca só ele', () {
      final filtro = RouteFilter.none
          .toggleCompany(Company.amazon)
          .toggleCompany(Company.shopee)
          .toggleCompany(Company.amazon);

      expect(filtro.companies, {Company.shopee});
    });

    test('empresa e status não se atrapalham', () {
      final filtro = RouteFilter.none
          .toggleCompany(Company.amazon)
          .toggleStatus(StatusRoute.pago);

      expect(filtro.companies, {Company.amazon});
      expect(filtro.statuses, {StatusRoute.pago});
    });

    test('o filtro original não muda', () {
      // Imutável de verdade: a folha monta um rascunho e a tela só troca de
      // filtro no "Aplicar". Um `Set` compartilhado por referência faria o
      // rascunho vazar para a lista antes da confirmação.
      const original = RouteFilter(companies: {Company.amazon});
      original.toggleCompany(Company.shopee);
      expect(original.companies, {Company.amazon});
    });
  });

  group('os eixos se cruzam com E', () {
    final rotas = [
      _route(id: 'am-pago', company: Company.amazon, status: StatusRoute.pago),
      _route(
        id: 'am-agendada',
        company: Company.amazon,
        status: StatusRoute.agendado,
      ),
      _route(
        id: 'ml-pago',
        company: Company.mercadolivre,
        status: StatusRoute.pago,
      ),
    ];

    test('Amazon + Pago é só a rota paga da Amazon', () {
      const filtro = RouteFilter(
        companies: {Company.amazon},
        statuses: {StatusRoute.pago},
      );
      // União daria três; interseção dá uma. É a diferença que o usuário
      // percebe como "o filtro não funciona".
      expect(_ids(applyFilter(rotas, filtro)), ['am-pago']);
    });
  });

  group('período', () {
    final rotas = [
      _route(id: 'jul', startAt: DateTime(2026, 7, 31, 8)),
      _route(id: 'ago1', startAt: DateTime(2026, 8, 1, 8)),
      _route(id: 'ago31', startAt: DateTime(2026, 8, 31, 22)),
      _route(id: 'set', startAt: DateTime(2026, 9, 1, 8)),
    ];

    test('as duas pontas entram, e a hora não corta o último dia', () {
      final filtro = RouteFilter(
        period: (start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31)),
      );
      // A rota das 22h do dia 31 é a que sumiria se a comparação fosse de
      // `DateTime` inteiro em vez de por dia.
      expect(_ids(applyFilter(rotas, filtro)), ['ago1', 'ago31']);
    });

    test('sem período, tudo passa', () {
      expect(applyFilter(rotas, RouteFilter.none).length, 4);
    });
  });

  group('faixa de valor', () {
    final rotas = [
      _route(id: 'baixa', value: 99.99),
      _route(id: 'ponta-min', value: 100),
      _route(id: 'meio', value: 150),
      _route(id: 'ponta-max', value: 200),
      _route(id: 'alta', value: 200.01),
    ];

    test('as duas pontas entram', () {
      const filtro = RouteFilter(valueRange: (min: 100.0, max: 200.0));
      expect(_ids(applyFilter(rotas, filtro)), [
        'ponta-min',
        'meio',
        'ponta-max',
      ]);
    });

    test('centavo de imprecisão na ponta não derruba a rota', () {
      // O `double` de uma rota de R$ 212,00 pode ser 212.00000000000003, e só
      // o `toStringAsFixed(2)` da tela esconde isso.
      final quaseDoze = [_route(id: 'x', value: 212.00000000000003)];
      const filtro = RouteFilter(valueRange: (min: 100.0, max: 212.0));
      expect(_ids(applyFilter(quaseDoze, filtro)), ['x']);
    });

    test('sem faixa, tudo passa', () {
      expect(applyFilter(rotas, RouteFilter.none).length, 5);
    });
  });

  group('veículo', () {
    final rotas = [
      _route(id: 'carro', vehicleId: 'v1'),
      _route(id: 'moto', vehicleId: 'v2'),
      _route(id: 'agendada', status: StatusRoute.agendado),
    ];

    test('filtra pelo veículo da provisão', () {
      const filtro = RouteFilter(vehicleId: 'v1');
      expect(_ids(applyFilter(rotas, filtro)), ['carro']);
    });

    test('rota sem provisão não passa em veículo nenhum', () {
      // É a limitação declarada: o id mora em `provision`, que só existe em
      // rota que já rodou. A tela precisa dizer isso — o filtro não tem como.
      for (final id in ['v1', 'v2', 'inexistente']) {
        final passou = applyFilter(rotas, RouteFilter(vehicleId: id));
        expect(passou.any((route) => route.id == 'agendada'), isFalse);
      }
    });

    test('sem veículo escolhido, a agendada aparece', () {
      expect(_ids(applyFilter(rotas, RouteFilter.none)), [
        'carro',
        'moto',
        'agendada',
      ]);
    });

    test('vehicleIdsInUse ignora rota sem provisão', () {
      expect(vehicleIdsInUse(rotas), {'v1', 'v2'});
    });

    test('vehicleIdsInUse ignora id vazio', () {
      // `RouteProvision.fromMap` devolve `''` quando o campo falta, e um
      // filtro rotulado com string vazia não tem nome para mostrar.
      expect(vehicleIdsInUse([_route(id: 'r', vehicleId: '')]), isEmpty);
    });
  });

  group('ordem', () {
    final rotas = [
      _route(id: 'b', value: 200, startAt: DateTime(2026, 8, 5, 8)),
      _route(id: 'a', value: 100, startAt: DateTime(2026, 8, 20, 8)),
      _route(id: 'c', value: 150, startAt: DateTime(2026, 8, 12, 8)),
    ];

    test('perto de hoje devolve a lista intacta', () {
      // Quem ordena por proximidade é o `RouteController`, e é ele que tem de
      // continuar sendo o único dono desse critério.
      expect(_ids(applyFilter(rotas, RouteFilter.none)), ['b', 'a', 'c']);
      expect(identical(sortRoutes(rotas, RouteOrder.pertoDeHoje), rotas), isTrue);
    });

    test('mais recente primeiro', () {
      expect(_ids(sortRoutes(rotas, RouteOrder.maisRecente)), ['a', 'c', 'b']);
    });

    test('mais antiga primeiro', () {
      expect(_ids(sortRoutes(rotas, RouteOrder.maisAntiga)), ['b', 'c', 'a']);
    });

    test('maior valor primeiro', () {
      expect(_ids(sortRoutes(rotas, RouteOrder.maiorValor)), ['b', 'c', 'a']);
    });

    test('menor valor primeiro', () {
      expect(_ids(sortRoutes(rotas, RouteOrder.menorValor)), ['a', 'c', 'b']);
    });

    test('empate não faz a ordem dançar entre rebuilds', () {
      final empatadas = [
        _route(id: 'z', value: 100),
        _route(id: 'a', value: 100),
        _route(id: 'm', value: 100),
      ];
      expect(_ids(sortRoutes(empatadas, RouteOrder.maiorValor)), ['a', 'm', 'z']);
    });

    test('ordenar não altera a lista recebida', () {
      final original = [...rotas];
      sortRoutes(rotas, RouteOrder.maiorValor);
      expect(_ids(rotas), _ids(original));
    });

    test('a ordem é aplicada depois do filtro', () {
      const filtro = RouteFilter(
        statuses: {StatusRoute.concluido},
        order: RouteOrder.maiorValor,
      );
      expect(_ids(applyFilter(rotas, filtro)), ['b', 'c', 'a']);
    });
  });

  group('badge', () {
    test('nada ligado não conta nada', () {
      expect(RouteFilter.none.extraCount, 0);
    });

    test('empresa não entra na conta', () {
      // Ela está desenhada na tela ao lado, marcada. Contá-la seria o badge
      // dizendo que existe um filtro escondido que não existe.
      const filtro = RouteFilter(companies: {Company.amazon});
      expect(filtro.extraCount, 0);
    });

    test('conta eixos, não opções marcadas', () {
      const filtro = RouteFilter(
        statuses: {StatusRoute.concluido, StatusRoute.pago, StatusRoute.agendado},
      );
      expect(filtro.extraCount, 1);
    });

    test('status com os cinco marcados não corta nada', () {
      const filtro = RouteFilter(statuses: {...StatusRoute.values});
      expect(filtro.extraCount, 0);
    });

    test('cada eixo soma um', () {
      final filtro = RouteFilter(
        statuses: const {StatusRoute.pago},
        period: (start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31)),
        vehicleId: 'v1',
        valueRange: (min: 100.0, max: 200.0),
      );
      expect(filtro.extraCount, 4);
    });

    test('a ordem não é filtro e não entra no badge', () {
      const filtro = RouteFilter(order: RouteOrder.maiorValor);
      expect(filtro.extraCount, 0);
    });
  });

  group('filtersNothing', () {
    test('o filtro vazio não corta nada', () {
      expect(RouteFilter.none.filtersNothing, isTrue);
    });

    test('as três empresas marcadas também não cortam nada', () {
      const filtro = RouteFilter(companies: {...Company.values});
      expect(filtro.filtersNothing, isTrue);
    });

    test('uma empresa marcada corta', () {
      const filtro = RouteFilter(companies: {Company.amazon});
      expect(filtro.filtersNothing, isFalse);
    });

    test('trocar a ordem conta como estado não-padrão', () {
      const filtro = RouteFilter(order: RouteOrder.maiorValor);
      expect(filtro.filtersNothing, isFalse);
    });
  });

  group('copyWith', () {
    final cheio = RouteFilter(
      companies: const {Company.amazon},
      statuses: const {StatusRoute.pago},
      period: (start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31)),
      vehicleId: 'v1',
      valueRange: (min: 100.0, max: 200.0),
      order: RouteOrder.maiorValor,
    );

    test('não passar nada mantém tudo', () {
      final copia = cheio.copyWith();
      expect(copia.period, cheio.period);
      expect(copia.vehicleId, 'v1');
      expect(copia.valueRange, cheio.valueRange);
      expect(copia.order, RouteOrder.maiorValor);
    });

    test('passar null limpa o eixo', () {
      // Sem a sentinela, isto seria indistinguível de não passar nada — e o
      // botão "Limpar" nasceria sem efeito e sem erro de compilação.
      final limpo = cheio.copyWith(
        period: null,
        vehicleId: null,
        valueRange: null,
      );
      expect(limpo.period, isNull);
      expect(limpo.vehicleId, isNull);
      expect(limpo.valueRange, isNull);
      expect(limpo.extraCount, 1);
    });
  });

  group('valueBounds', () {
    test('arredonda para fora na dezena', () {
      final rotas = [_route(id: 'a', value: 199), _route(id: 'b', value: 212)];
      expect(valueBounds(rotas), (min: 190.0, max: 220.0));
    });

    test('todas do mesmo valor não desenham faixa', () {
      // `RangeSlider` lança com `min == max`. É a rota única, e é comum.
      final rotas = [_route(id: 'a', value: 200), _route(id: 'b', value: 200)];
      expect(valueBounds(rotas), isNull);
    });

    test('uma rota só não desenha faixa', () {
      expect(valueBounds([_route(id: 'a', value: 123)]), isNull);
    });

    test('lista vazia não desenha faixa', () {
      expect(valueBounds(const []), isNull);
    });

    test('valores diferentes na mesma dezena ainda desenham faixa', () {
      // 201 e 208 arredondam para 200–210: apertado, mas discrimina, e é
      // exatamente para isso que o arredondamento para fora existe.
      final rotas = [_route(id: 'a', value: 201), _route(id: 'b', value: 208)];
      expect(valueBounds(rotas), (min: 200.0, max: 210.0));
    });

    test('a faixa cobre a menor e a maior rota', () {
      final rotas = [
        _route(id: 'a', value: 45.5),
        _route(id: 'b', value: 1234.9),
      ];
      final bounds = valueBounds(rotas)!;
      expect(bounds.min, lessThanOrEqualTo(45.5));
      expect(bounds.max, greaterThanOrEqualTo(1234.9));
    });
  });
}
