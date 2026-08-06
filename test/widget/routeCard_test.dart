import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/routeCard.dart';

NewRouteModal buildRoute({
  Company company = Company.amazon,
  StatusRoute status = StatusRoute.agendado,
  double value = 150.5,
  double? kmInitial,
  double? kmFinal,
  int? packages,
  int? stops,
  List<String>? adress,
  DateTime? startAt,
  DateTime? endAt,
  bool? isInsucesso,
  int? insucessoQnt,
  Map<String, int> insucessoPorBairro = const {},
  RouteProvision? provision,
}) {
  return NewRouteModal(
    id: 'rota-1',
    company: company,
    dateRoute: '01/08/2026',
    weekday: 6,
    status: status,
    value: value,
    kmInitial: kmInitial,
    kmFinal: kmFinal,
    packages: packages,
    stops: stops,
    adress: adress,
    startAt: startAt ?? DateTime(2026, 8, 1, 8),
    endAt: endAt,
    isInsucesso: isInsucesso,
    insucessoQnt: insucessoQnt,
    insucessoPorBairro: insucessoPorBairro,
    provision: provision,
    createdAt: '2026-08-01T09:00:00.000',
  );
}

/// A provisão da linha 3 de JUL da planilha: 46,9 km com a Fiorino.
RouteProvision buildProvision({
  double km = 46.9,
  double fuel = 32.83,
  double totalParts = 5.596733,
}) {
  return RouteProvision(
    vehicleId: 'v1',
    km: km,
    fuel: fuel,
    parts: const {
      'Óleo': 0.938,
      'Pneu': 1.876,
      'Bateria': 0.6253333,
      'Freio': 0.7504,
      'Geral': 1.407,
    },
    totalParts: totalParts,
    calculatedAt: '2026-07-01T20:00:00.000',
  );
}

Future<void> pumpCard(
  WidgetTester tester,
  NewRouteModal route, {
  bool isExpanded = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RouteCard(route: route, isExpanded: isExpanded, onTap: () {}),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra data com dia da semana, valor e status', (tester) async {
    await pumpCard(tester, buildRoute());

    expect(find.text('Sáb, 01/08/2026'), findsOneWidget);
    expect(find.text('R\$ 150,50'), findsOneWidget);
    expect(find.text('Agendado'), findsOneWidget);
  });

  testWidgets('mostra R\$ 0,00 quando o valor é zero', (tester) async {
    // formatDoubleToMoney devolve string vazia para zero; o card precisa
    // exibir o valor mesmo assim.
    await pumpCard(tester, buildRoute(value: 0));

    expect(find.text('R\$ 0,00'), findsOneWidget);
  });

  testWidgets('usa o rótulo certo de cada status', (tester) async {
    await pumpCard(tester, buildRoute(status: StatusRoute.andamento));
    expect(find.text('Em rota'), findsOneWidget);

    await pumpCard(tester, buildRoute(status: StatusRoute.pago));
    expect(find.text('Pago'), findsOneWidget);
  });

  testWidgets('esconde os detalhes quando fechado', (tester) async {
    await pumpCard(tester, buildRoute(packages: 120, stops: 85));

    expect(find.text('120'), findsNothing);
    expect(find.text('85'), findsNothing);
  });

  testWidgets('expandido mostra KM, pacotes, paradas, horário e bairros', (
    tester,
  ) async {
    await pumpCard(
      tester,
      buildRoute(
        kmInitial: 1000,
        kmFinal: 1042.5,
        packages: 120,
        stops: 85,
        startAt: DateTime(2026, 8, 1, 8),
        endAt: DateTime(2026, 8, 1, 17, 30),
        adress: ['Aldeota', 'Meireles'],
      ),
      isExpanded: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('42.5 km'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
    expect(find.text('08:00 às 17:30 (9h30)'), findsOneWidget);
    expect(find.text('Aldeota, Meireles'), findsOneWidget);
  });

  testWidgets('insucesso sem distribuição mostra só o total', (tester) async {
    await pumpCard(
      tester,
      buildRoute(
        adress: ['Aldeota', 'Centro'],
        isInsucesso: true,
        insucessoQnt: 3,
      ),
      isExpanded: true,
    );

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('insucesso distribuído mostra em quais bairros foi', (
    tester,
  ) async {
    await pumpCard(
      tester,
      buildRoute(
        adress: ['Aldeota', 'Centro'],
        isInsucesso: true,
        insucessoQnt: 3,
        insucessoPorBairro: const {'Aldeota': 2, 'Centro': 1},
      ),
      isExpanded: true,
    );

    expect(find.text('3 (Aldeota 2, Centro 1)'), findsOneWidget);
  });

  testWidgets('distribuição parcial deixa a diferença visível', (tester) async {
    await pumpCard(
      tester,
      buildRoute(
        adress: ['Aldeota', 'Centro'],
        isInsucesso: true,
        insucessoQnt: 5,
        insucessoPorBairro: const {'Aldeota': 2},
      ),
      isExpanded: true,
    );

    // 5 no total, 2 com bairro: os outros 3 são os que o gráfico rateia.
    expect(find.text('5 (Aldeota 2)'), findsOneWidget);
  });

  testWidgets('sem hora de fim mostra só o início', (tester) async {
    await pumpCard(tester, buildRoute(), isExpanded: true);
    await tester.pumpAndSettle();

    expect(find.text('Início às 08:00'), findsOneWidget);
  });

  testWidgets('rota que vira o dia calcula a duração certa', (tester) async {
    // 22:00 às 02:00: o fim está no dia seguinte, não 20h antes do início.
    await pumpCard(
      tester,
      buildRoute(
        startAt: DateTime(2026, 8, 1, 22),
        endAt: DateTime(2026, 8, 2, 2),
      ),
      isExpanded: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('22:00 às 02:00 (4h)'), findsOneWidget);
  });

  group('provisão e lucro', () {
    testWidgets('mostra gasolina, provisão e lucro da planilha', (
      tester,
    ) async {
      await pumpCard(
        tester,
        buildRoute(
          status: StatusRoute.pago,
          value: 152.50,
          kmInitial: 1000,
          kmFinal: 1046.9,
          provision: buildProvision(),
        ),
        isExpanded: true,
      );
      await tester.pumpAndSettle();

      // As colunas F, L e O da linha 3 de JUL.
      expect(find.byKey(const Key('route-fuel')), findsOneWidget);
      expect(_money(tester, 'route-fuel'), 'R\$ 32,83');
      expect(_money(tester, 'route-provision'), 'R\$ 5,60');
      expect(_money(tester, 'route-profit'), 'R\$ 114,07');
    });

    testWidgets('a gasolina fica fora da provisão', (tester) async {
      await pumpCard(
        tester,
        buildRoute(
          status: StatusRoute.pago,
          value: 152.50,
          kmInitial: 1000,
          kmFinal: 1046.9,
          provision: buildProvision(),
        ),
        isExpanded: true,
      );
      await tester.pumpAndSettle();

      // Se a gasolina entrasse em `Total P.`, a provisão seria R$ 38,43.
      expect(_money(tester, 'route-provision'), 'R\$ 5,60');
    });

    testWidgets('rota sem provisão não mostra a seção', (tester) async {
      await pumpCard(
        tester,
        buildRoute(kmInitial: 1000, kmFinal: 1046.9),
        isExpanded: true,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('route-fuel')), findsNothing);
      expect(find.byKey(const Key('route-profit')), findsNothing);
      expect(find.byKey(const Key('route-profit-hint')), findsNothing);
    });

    testWidgets('concluída sem KM pede o KM em vez de mostrar lucro zero', (
      tester,
    ) async {
      await pumpCard(
        tester,
        buildRoute(status: StatusRoute.concluido),
        isExpanded: true,
      );
      await tester.pumpAndSettle();

      // "Lucro R$ 0,00" seria falso: o app não sabe o custo, e não saber é
      // diferente de não ter custo.
      expect(find.byKey(const Key('route-profit-hint')), findsOneWidget);
      expect(find.byKey(const Key('route-profit')), findsNothing);
    });

    testWidgets('prejuízo aparece em vermelho', (tester) async {
      await pumpCard(
        tester,
        buildRoute(
          status: StatusRoute.pago,
          value: 20,
          kmInitial: 1000,
          kmFinal: 1046.9,
          provision: buildProvision(),
        ),
        isExpanded: true,
      );
      await tester.pumpAndSettle();

      expect(_money(tester, 'route-profit'), 'R\$ -18,43');
      final style = tester
          .widget<Text>(find.byKey(const Key('route-profit')))
          .style!;
      expect(style.color, Colors.red.shade600);
    });

    testWidgets('card fechado não monta a seção', (tester) async {
      await pumpCard(
        tester,
        buildRoute(
          status: StatusRoute.pago,
          kmInitial: 1000,
          kmFinal: 1046.9,
          provision: buildProvision(),
        ),
      );

      expect(find.byKey(const Key('route-profit')), findsNothing);
    });
  });
}

String _money(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;
