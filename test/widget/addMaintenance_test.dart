import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/expenseRules.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/screens/addMaintenance.dart';

Vehicle _fit({List<MaintenancePart>? parts}) {
  return Vehicle(
    id: 'v1',
    type: VehicleType.carro,
    brandCode: '25',
    brandName: 'Honda',
    modelCode: '1',
    modelName: 'Fit EXL 1.5',
    nickname: 'Fit',
    fuel: FuelType.flex,
    fuelPrice: 7,
    consumption: 10,
    parts: parts ?? Vehicle.defaultParts(VehicleType.carro),
    createdAt: '2026-01-01T00:00:00.000',
  );
}

/// [width] em pontos lógicos. 360 é a largura de Android barato — foi numa
/// tela assim que o formulário de rota estourou.
Future<void> _pump(
  WidgetTester tester, {
  List<Vehicle>? vehicles,
  Vehicle? active,
  double width = 411,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AddMaintenance(
        uid: 'u1',
        vehiclesLoader: () async => (
          all: vehicles ?? const <Vehicle>[],
          active: active,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('o formulário', () {
    testWidgets('tem os campos que o usuário pediu', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('maintenance-item')), findsOneWidget);
      expect(find.byKey(const Key('maintenance-action')), findsOneWidget);
      expect(find.byKey(const Key('maintenance-value')), findsOneWidget);
      expect(find.byKey(const Key('maintenance-workshop')), findsOneWidget);
      expect(find.byKey(const Key('maintenance-description')), findsOneWidget);
      expect(find.byKey(const Key('maintenance-odometer')), findsOneWidget);
    });

    // Dois testes e não um: `pumpWidget` duas vezes no mesmo teste reaproveita
    // o `State` — o `initState` não roda de novo, e o segundo carregador seria
    // ignorado em silêncio.
    testWidgets('sem veículo cadastrado, não mostra o seletor', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('maintenance-vehicle')), findsNothing);
    });

    testWidgets('com veículo cadastrado, mostra o seletor', (tester) async {
      final fit = _fit();
      await _pump(tester, vehicles: [fit], active: fit);

      expect(find.byKey(const Key('maintenance-vehicle')), findsOneWidget);
    });

    testWidgets('valor vazio bloqueia o salvamento', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('maintenance-save')));
      await tester.pump();

      expect(find.text('Informe o valor'), findsOneWidget);
    });

    testWidgets('oficina e descrição são opcionais', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byKey(const Key('maintenance-value')), '240000');
      await tester.tap(find.byKey(const Key('maintenance-save')));
      await tester.pump();

      expect(find.text('Informe o valor'), findsNothing);
    });
  });

  group('o toggle Reparo | Substituição', () {
    testWidgets('mostra as duas opções', (tester) async {
      await _pump(tester);

      expect(find.text('Reparo'), findsOneWidget);
      expect(find.text('Substituição'), findsOneWidget);
    });

    testWidgets('começa em Substituição, que é o caso comum', (tester) async {
      await _pump(tester);

      final botao = tester.widget<SegmentedButton<MaintenanceAction>>(
        find.byKey(const Key('maintenance-action')),
      );

      expect(botao.selected, {MaintenanceAction.substituicao});
    });

    testWidgets('dá para trocar para Reparo', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Reparo'));
      await tester.pumpAndSettle();

      final botao = tester.widget<SegmentedButton<MaintenanceAction>>(
        find.byKey(const Key('maintenance-action')),
      );

      expect(botao.selected, {MaintenanceAction.reparo});
    });
  });

  group('cabe em tela estreita', () {
    // Estes três só provam que nada **estourou**. A primeira versão do
    // formulário passava neles e mesmo assim o rótulo "Substituição" quebrava
    // linha no iPhone — quebra não é overflow, não vira exceção e o teste fica
    // verde. Por isso existe o grupo seguinte.
    testWidgets('em 360 px nada estoura', (tester) async {
      await _pump(tester, width: 360);
      expect(tester.takeException(), isNull);
    });

    testWidgets('em 320 px — o menor Android em uso — também não', (
      tester,
    ) async {
      await _pump(tester, width: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('com o seletor de veículo montado também cabe', (tester) async {
      final fit = _fit();
      await _pump(tester, vehicles: [fit], active: fit, width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('o toggle recebe a linha inteira', () {
    // **O que estes testes NÃO conseguem provar:** que "Substituição" cabe sem
    // quebrar linha. A fonte padrão do `flutter_test` é quadrada — 14,25 px por
    // caractere em `fontSize: 14`, medido — enquanto uma fonte real gasta uns
    // 7. "Substituição" mede 171 px no teste e ~85 no aparelho. Testar "cabe?"
    // aqui reprovaria layouts que funcionam e me faria desenhar para uma fonte
    // que não existe.
    //
    // O que dá para provar é a **causa** do defeito: o toggle estava dividindo
    // a linha com o campo Valor e ficava com pouco mais de um terço da largura.
    // Agora recebe a linha inteira, e cada segmento tem o dobro do espaço.
    // Se alguém voltar a colocar algo ao lado dele, estes testes quebram.
    Future<void> ocupaTudo(WidgetTester tester, double width) async {
      await _pump(tester, width: width);

      const padding = 32.0; // 16 de cada lado, do ListView
      final toggle = tester
          .getSize(find.byKey(const Key('maintenance-action')))
          .width;

      expect(toggle, closeTo(width - padding, 1));
    }

    testWidgets('em 411 px (o iPhone do usuário)', (tester) async {
      await ocupaTudo(tester, 411);
    });

    testWidgets('em 360 px', (tester) async {
      await ocupaTudo(tester, 360);
    });

    testWidgets('em 320 px — o menor Android em uso', (tester) async {
      await ocupaTudo(tester, 320);
    });
  });

  group('o valor subiu para a linha da peça', () {
    testWidgets('os dois dividem a mesma linha', (tester) async {
      await _pump(tester, width: 411);

      final peca = tester.getRect(find.byKey(const Key('maintenance-item')));
      final valor = tester.getRect(find.byKey(const Key('maintenance-value')));

      // Mesma faixa vertical = mesma linha.
      expect(peca.top, closeTo(valor.top, 2));
      // E o campo do valor fica à direita da peça.
      expect(valor.left, greaterThan(peca.right - 1));
    });

    testWidgets('a peça fica com mais espaço que o valor', (tester) async {
      // "Pastilha de freio" é o rótulo mais longo da lista; o valor cabe em
      // "R$ 2.400,00".
      await _pump(tester, width: 411);

      final peca = tester.getSize(find.byKey(const Key('maintenance-item')));
      final valor = tester.getSize(find.byKey(const Key('maintenance-value')));

      expect(peca.width, greaterThan(valor.width));
    });
  });

  group('a lista de itens', () {
    testWidgets('começa em Pneu', (tester) async {
      await _pump(tester);

      expect(find.text('Pneu'), findsOneWidget);
    });

    testWidgets('abre com os treze itens', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('maintenance-item')));
      await tester.pumpAndSettle();

      // O menu monta um item por valor do enum; alguns aparecem duas vezes
      // (o do campo e o do menu), então basta conferir que os raros estão lá.
      expect(find.text('Funilaria'), findsWidgets);
      expect(find.text('Pastilha de freio'), findsWidgets);
      expect(find.text('Amortecedor'), findsWidgets);
    });
  });

  group('withPartPrice — o que a confirmação grava', () {
    test('troca só o preço da peça certa', () {
      final atualizado = withPartPrice(_fit(), MaintenanceItem.pneu, 600);
      final pneu = atualizado.parts.firstWhere((p) => p.name == 'Pneu');
      final oleo = atualizado.parts.firstWhere((p) => p.name == 'Óleo');

      expect(pneu.price, 600);
      expect(oleo.price, 200); // intocado
    });

    test('vida útil e quantidade não mudam', () {
      // A manutenção sabe quanto custou, não quanto vai durar.
      final pneu = withPartPrice(_fit(), MaintenanceItem.pneu, 600)
          .parts
          .firstWhere((p) => p.name == 'Pneu');

      expect(pneu.lifeKm, 50000);
      expect(pneu.quantity, 4);
    });

    test('sem peça correspondente devolve o mesmo veículo', () {
      final original = _fit();
      final resultado = withPartPrice(original, MaintenanceItem.funilaria, 600);

      expect(identical(resultado, original), isTrue);
    });

    test('preço zero ou negativo não grava nada', () {
      final original = _fit();

      expect(identical(withPartPrice(original, MaintenanceItem.pneu, 0), original), isTrue);
      expect(identical(withPartPrice(original, MaintenanceItem.pneu, -1), original), isTrue);
    });
  });
}
