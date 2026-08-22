import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeFilter.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/widget/routeFilterSheet.dart';

/// Uma rota com o mínimo para o teste em questão — mesmo atalho de
/// `routeFilter_test.dart`, para cada teste declarar só o campo que examina.
NewRouteModal _route({
  String id = 'r1',
  double value = 100,
  StatusRoute status = StatusRoute.concluido,
  String? vehicleId,
}) {
  final start = DateTime(2026, 8, 10, 8);

  return NewRouteModal(
    id: id,
    company: Company.mercadolivre,
    dateRoute: '10/08/2026',
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

/// Duas rotas de valores diferentes: é o que faz `valueBounds` devolver uma
/// faixa desenhável, então é o cenário padrão de quase todo teste daqui.
List<NewRouteModal> _routes() => [
  _route(id: 'r1', value: 100),
  _route(id: 'r2', value: 250),
];

Vehicle _vehicle({String id = 'v1', String nickname = 'Fiorino branca'}) =>
    Vehicle(
      id: id,
      type: VehicleType.carro,
      brandCode: '21',
      brandName: 'Fiat',
      modelCode: '4828',
      modelName: 'Fiorino',
      nickname: nickname,
      fuel: FuelType.flex,
      createdAt: '2026-01-01T00:00:00.000',
    );

/// O que a folha devolveu, e se ela chegou a fechar.
///
/// `null` em [filter] só quer dizer alguma coisa junto com [closed]: sem ele,
/// "descartada" e "ainda aberta" seriam o mesmo `null`.
class _Opened {
  RouteFilter? filter;
  bool closed = false;
}

/// Sobe um `Scaffold` com um botão que abre a folha, e não a folha solta: é o
/// único jeito de ter um `BuildContext` com `Navigator`, e é o fluxo real —
/// descartar e devolver `null` só existe dentro do `showModalBottomSheet`.
Future<_Opened> _open(
  WidgetTester tester, {
  RouteFilter current = RouteFilter.none,
  List<NewRouteModal>? routes,
  /// `null` é "não deu para saber" — a leitura falhou ou não chegou. O padrão
  /// `const []` é a leitura que deu certo e não achou veículo nenhum.
  List<Vehicle>? vehicles = const [],
}) async {
  final opened = _Opened();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              opened.filter = await showRouteFilterSheet(
                context,
                current: current,
                routes: routes ?? _routes(),
                vehicles: vehicles,
              );
              opened.closed = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return opened;
}

/// Rola até o alvo antes de tocar: são cinco seções e a tela do teste tem 600
/// pixels de altura, então a ordenação nasce fora do campo de visão.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('descartar devolve null', (tester) async {
    final opened = await _open(
      tester,
      current: const RouteFilter(statuses: {StatusRoute.pago}),
    );

    // Toque fora da folha: a barreira do modal fecha sem passar pelo "Aplicar".
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(opened.closed, isTrue, reason: 'a folha não chegou a fechar');
    expect(opened.filter, isNull);
  });

  testWidgets('Aplicar devolve o rascunho com o que foi marcado', (
    tester,
  ) async {
    final opened = await _open(tester);

    await _tap(tester, 'status-pago');
    await _tap(tester, 'status-concluido');
    await _tap(tester, 'ordem-maiorValor');
    await _tap(tester, 'filtro-aplicar');

    final filter = opened.filter;
    expect(filter, isNotNull);
    expect(filter!.statuses, {StatusRoute.pago, StatusRoute.concluido});
    expect(filter.order, RouteOrder.maiorValor);
  });

  testWidgets('tocar num status marcado desmarca só ele', (tester) async {
    final opened = await _open(
      tester,
      current: const RouteFilter(
        statuses: {StatusRoute.pago, StatusRoute.concluido},
      ),
    );

    await _tap(tester, 'status-pago');
    await _tap(tester, 'filtro-aplicar');

    expect(opened.filter!.statuses, {StatusRoute.concluido});
  });

  testWidgets('Limpar tudo devolve ao estado RouteFilter.none', (tester) async {
    final opened = await _open(
      tester,
      current: RouteFilter(
        companies: const {Company.amazon},
        statuses: const {StatusRoute.pago},
        period: (start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        vehicleId: 'v1',
        valueRange: (min: 100, max: 200),
        order: RouteOrder.menorValor,
      ),
      routes: [
        _route(id: 'r1', value: 100, vehicleId: 'v1'),
        _route(id: 'r2', value: 250),
      ],
      vehicles: [_vehicle()],
    );

    await _tap(tester, 'filtro-limpar');
    await _tap(tester, 'filtro-aplicar');

    final filter = opened.filter!;
    expect(filter.companies, isEmpty);
    expect(filter.statuses, isEmpty);
    expect(filter.period, isNull);
    expect(filter.vehicleId, isNull);
    expect(filter.valueRange, isNull);
    expect(filter.order, RouteOrder.pertoDeHoje);
    expect(filter.filtersNothing, isTrue);
  });

  testWidgets('Limpar tudo não fecha a folha', (tester) async {
    final opened = await _open(
      tester,
      current: const RouteFilter(statuses: {StatusRoute.pago}),
    );

    await _tap(tester, 'filtro-limpar');

    expect(opened.closed, isFalse);
    expect(find.byKey(const ValueKey('filtro-aplicar')), findsOneWidget);
  });

  testWidgets('sem limites de valor a seção de faixa não é desenhada', (
    tester,
  ) async {
    // Todas as rotas valendo o mesmo: `valueBounds` devolve `null` e o
    // `RangeSlider` **lança** com `min == max`.
    await _open(
      tester,
      routes: [
        _route(id: 'r1', value: 180),
        _route(id: 'r2', value: 180),
      ],
    );

    expect(find.byType(RangeSlider), findsNothing);
    expect(find.byKey(const ValueKey('valor-faixa')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a faixa começa inativa e o Aplicar não a inventa', (
    tester,
  ) async {
    final opened = await _open(tester);

    // O trilho está lá, mostrando os limites — mas o rascunho segue sem faixa.
    // Uma faixa que nasce cobrindo tudo não corta nada e ainda assim contaria
    // um eixo no badge do ícone.
    expect(find.byKey(const ValueKey('valor-faixa')), findsOneWidget);

    await _tap(tester, 'filtro-aplicar');

    expect(opened.filter!.valueRange, isNull);
  });

  testWidgets('sem veículo em uso a seção de veículo não é desenhada', (
    tester,
  ) async {
    // Rota agendada não tem provisão, então não tem veículo — mesmo com um
    // carro cadastrado, não há o que oferecer.
    await _open(
      tester,
      routes: [_route(id: 'r1', value: 100, status: StatusRoute.agendado)],
      vehicles: [_vehicle()],
    );

    expect(find.byKey(const ValueKey('veiculo-todos')), findsNothing);
    expect(find.byKey(const ValueKey('veiculo-v1')), findsNothing);
    expect(find.byKey(const ValueKey('veiculo-aviso')), findsNothing);
  });

  testWidgets('com veículo em uso a seção aparece com a linha de apoio', (
    tester,
  ) async {
    await _open(
      tester,
      routes: [
        _route(id: 'r1', value: 100, vehicleId: 'v1'),
        _route(id: 'r2', value: 250),
      ],
      vehicles: [
        _vehicle(),
        _vehicle(id: 'v2', nickname: 'Moto'),
      ],
    );

    expect(find.byKey(const ValueKey('veiculo-todos')), findsOneWidget);
    expect(find.byKey(const ValueKey('veiculo-v1')), findsOneWidget);
    // O carro cadastrado que nenhuma rota rodou fica de fora: um chip que
    // devolve lista vazia é filtro que parece quebrado.
    expect(find.byKey(const ValueKey('veiculo-v2')), findsNothing);
    // Sem a linha de apoio, o filtro parece estar comendo as rotas agendadas.
    expect(find.byKey(const ValueKey('veiculo-aviso')), findsOneWidget);
  });

  testWidgets('escolher um veículo devolve o id no rascunho', (tester) async {
    final opened = await _open(
      tester,
      routes: [
        _route(id: 'r1', value: 100, vehicleId: 'v1'),
        _route(id: 'r2', value: 250),
      ],
      vehicles: [_vehicle()],
    );

    await _tap(tester, 'veiculo-v1');
    await _tap(tester, 'filtro-aplicar');

    expect(opened.filter!.vehicleId, 'v1');
  });

  testWidgets('o conteúdo das seções rola na vertical', (tester) async {
    await _open(tester);

    // A causa, não a aparência: com as cinco seções dentro de um scroll
    // vertical, nenhuma delas é cortada em tela baixa — que é o único jeito de
    // garantir isso sem depender da fonte do aparelho.
    final scroll = tester.widget<SingleChildScrollView>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('status-pago')),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );

    expect(scroll.scrollDirection, Axis.vertical);
    // O rodapé fica fora do scroll: "Aplicar" não pode exigir rolar até o fim
    // para existir.
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('filtro-aplicar')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  group('a faixa guardada é conferida contra os limites de agora', () {
    testWidgets('faixa acima do teto novo é descartada em vez de lançar', (
      tester,
    ) async {
      // O caminho real: a lista tinha rotas de 100/250/500, o usuário filtrou
      // 300–500, e depois apagou a de R$ 500 deslizando o card. Sem a
      // reconciliação, `RangeSlider` estoura `assert(values.start >= min)`.
      final opened = await _open(
        tester,
        current: const RouteFilter(valueRange: (min: 300.0, max: 500.0)),
        routes: [_route(id: 'r1', value: 100), _route(id: 'r2', value: 250)],
      );

      expect(tester.takeException(), isNull);

      await _tap(tester, 'filtro-aplicar');
      expect(opened.filter, isNotNull);
      expect(opened.filter!.valueRange, isNull);
      // E some do badge junto: deixou mesmo de cortar.
      expect(opened.filter!.extraCount, 0);
    });

    testWidgets('faixa dentro dos limites sobrevive à reabertura', (
      tester,
    ) async {
      final opened = await _open(
        tester,
        current: const RouteFilter(valueRange: (min: 100.0, max: 200.0)),
        routes: [_route(id: 'r1', value: 100), _route(id: 'r2', value: 250)],
      );

      await _tap(tester, 'filtro-aplicar');
      expect(opened.filter!.valueRange, (min: 100.0, max: 200.0));
    });

    testWidgets('sem faixa desenhável, o eixo é desligado', (tester) async {
      // Uma rota só: `valueBounds` devolve null e a seção não existe. Manter o
      // eixo ligado deixaria o badge contando um filtro cujo botão de limpar
      // mora dentro da seção que sumiu.
      final opened = await _open(
        tester,
        current: const RouteFilter(valueRange: (min: 100.0, max: 200.0)),
        routes: [_route(id: 'r1', value: 123)],
      );

      expect(find.byKey(const ValueKey('valor-faixa')), findsNothing);

      await _tap(tester, 'filtro-aplicar');
      expect(opened.filter!.valueRange, isNull);
      expect(opened.filter!.extraCount, 0);
    });
  });

  group('veículo: não deu para saber é diferente de não tem', () {
    testWidgets('leitura indisponível avisa em vez de sumir com a seção', (
      tester,
    ) async {
      // A primeira leitura num aparelho sem sinal é o caso comum. Esconder a
      // seção mandaria quem TEM carro procurar o filtro que sumiu.
      await _open(
        tester,
        routes: [_route(id: 'r1', value: 100, vehicleId: 'v1')],
        vehicles: null,
      );

      expect(find.byKey(const ValueKey('veiculo-indisponivel')), findsOneWidget);
    });

    testWidgets('sem rota com veículo, nem o aviso aparece', (tester) async {
      // Aqui não há mesmo o que filtrar, e a leitura ter falhado não muda isso.
      await _open(tester, vehicles: null);

      expect(find.byKey(const ValueKey('veiculo-indisponivel')), findsNothing);
      expect(find.byKey(const ValueKey('veiculo-todos')), findsNothing);
    });

    testWidgets('com veículo lido, os chips aparecem e o aviso não', (
      tester,
    ) async {
      await _open(
        tester,
        routes: [_route(id: 'r1', value: 100, vehicleId: 'v1')],
        vehicles: [_vehicle()],
      );

      expect(find.byKey(const ValueKey('veiculo-v1')), findsOneWidget);
      expect(find.byKey(const ValueKey('veiculo-indisponivel')), findsNothing);
    });
  });
}
