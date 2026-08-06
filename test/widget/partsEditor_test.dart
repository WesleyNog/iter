import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/widget/partsEditor.dart';

/// Monta o editor sozinho, sem Firebase e sem a tela de cadastro.
Future<List<MaintenancePart>> _pump(
  WidgetTester tester, {
  List<MaintenancePart>? parts,
}) async {
  var current = parts ?? Vehicle.defaultParts(VehicleType.carro);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PartsEditor(
            parts: current,
            onChanged: (updated) => current = updated,
          ),
        ),
      ),
    ),
  );

  return current;
}

void main() {
  testWidgets('abre com as cinco peças da planilha', (tester) async {
    await _pump(tester);

    expect(
      tester.widget<TextField>(find.byKey(const Key('part-name-0'))).controller!.text,
      'Óleo',
    );
    expect(find.byKey(const Key('part-name-4')), findsOneWidget);
    expect(find.byKey(const Key('part-name-5')), findsNothing);
  });

  testWidgets('mostra a taxa de cada peça já calculada', (tester) async {
    await _pump(tester);

    // Os números que o Wesley usa hoje, conferíveis contra a planilha sem sair
    // da tela.
    expect(_rateText(tester, 0), 'R\$ 0,0200 /km'); // Óleo
    expect(_rateText(tester, 1), 'R\$ 0,0400 /km'); // Pneu, já com o *4
    expect(_rateText(tester, 2), 'R\$ 0,0133 /km'); // Bateria
    expect(_rateText(tester, 3), 'R\$ 0,0160 /km'); // Freio
    expect(_rateText(tester, 4), 'R\$ 0,0300 /km'); // Geral
  });

  testWidgets('pneu mostra 0,0400 por causa da quantidade 4', (tester) async {
    await _pump(tester);

    expect(
      tester.widget<TextField>(find.byKey(const Key('part-qty-1'))).controller!.text,
      '4',
    );
    // Sem a quantidade seria 0,0100 — quatro vezes menos do que ele provisiona.
    expect(_rateText(tester, 1), 'R\$ 0,0400 /km');
  });

  testWidgets('a "Geral" tem taxa direta, sem preço nem vida útil', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('part-fixed-4')), findsOneWidget);
    expect(find.byKey(const Key('part-price-4')), findsNothing);
    expect(find.byKey(const Key('part-life-4')), findsNothing);
  });

  testWidgets('taxa incalculável mostra — e não R\$ 0,00', (tester) async {
    await _pump(
      tester,
      parts: const [MaintenancePart(name: 'Correia', price: 300)],
    );

    expect(_rateText(tester, 0), '—');
  });

  testWidgets('editar a vida útil recalcula a taxa na hora', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('part-life-0')), '20000');
    await tester.pump();

    // R$ 200 durando o dobro custa metade por km.
    expect(_rateText(tester, 0), 'R\$ 0,0100 /km');
  });

  testWidgets('esvaziar a vida útil vira —, não zero', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('part-life-0')), '');
    await tester.pump();

    expect(_rateText(tester, 0), '—');
  });

  testWidgets('avisa o pai a cada edição', (tester) async {
    List<MaintenancePart>? reported;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PartsEditor(
              parts: Vehicle.defaultParts(VehicleType.carro),
              onChanged: (updated) => reported = updated,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('part-life-0')), '20000');
    await tester.pump();

    expect(reported, isNotNull);
    expect(reported!.first.lifeKm, 20000);
  });

  testWidgets('adicionar peça cria linha vazia com taxa —', (tester) async {
    await _pump(tester);

    await tester.ensureVisible(find.byKey(const Key('parts-add')));
    await tester.tap(find.byKey(const Key('parts-add')));
    await tester.pump();

    expect(find.byKey(const Key('part-name-5')), findsOneWidget);
    expect(_rateText(tester, 5), '—');
  });

  testWidgets('remover peça tira a linha e avisa o pai', (tester) async {
    List<MaintenancePart>? reported;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PartsEditor(
              parts: Vehicle.defaultParts(VehicleType.carro),
              onChanged: (updated) => reported = updated,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('part-remove-0')));
    await tester.pump();

    expect(find.byKey(const Key('part-name-4')), findsNothing);
    expect(reported!.length, 4);
    expect(reported!.first.name, 'Pneu');
  });

  group('leitura de número — pt-BR e teclado numérico', () {
    test('quilometragem: o ponto é sempre milhar', () {
      expect(parseKm('50000'), 50000);
      expect(parseKm('50.000'), 50000);
      expect(parseKm('10.000'), 10000);
      expect(parseKm(''), isNull); // vazio é "não preenchi", não zero
      expect(parseKm('abc'), isNull);
    });

    test('taxa: o ponto é decimal', () {
      // O teclado numérico do celular oferece ponto. Tratá-lo como milhar
      // faria 0.03 virar 3 — cem vezes a taxa, num campo que ninguém confere
      // de cabeça.
      expect(parseRate('0,03'), 0.03);
      expect(parseRate('0.03'), 0.03);
      expect(parseRate('0,0133'), 0.0133);
      expect(parseRate(''), isNull);
    });

    test('taxa com vírgula devolve o ponto ao papel de milhar', () {
      expect(parseRate('1.234,5'), 1234.5);
    });
  });

  testWidgets('taxa direta digitada com ponto não vira cem vezes o valor', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('part-fixed-4')), '0.05');
    await tester.pump();

    expect(_rateText(tester, 4), 'R\$ 0,0500 /km');
  });

  testWidgets('vida útil digitada com ponto de milhar é lida certo', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('part-life-0')), '20.000');
    await tester.pump();

    expect(_rateText(tester, 0), 'R\$ 0,0100 /km');
  });

  testWidgets('moto abre com 2 pneus', (tester) async {
    await _pump(tester, parts: Vehicle.defaultParts(VehicleType.moto));

    expect(
      tester.widget<TextField>(find.byKey(const Key('part-qty-1'))).controller!.text,
      '2',
    );
    expect(_rateText(tester, 1), 'R\$ 0,0200 /km');
  });
}

String _rateText(WidgetTester tester, int index) =>
    tester.widget<Text>(find.byKey(Key('part-rate-$index'))).data!;
