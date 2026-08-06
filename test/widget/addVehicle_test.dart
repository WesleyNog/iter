import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/screens/addVehicle.dart';

/// O formulário sem rede e sem Firestore: nada em `initState` toca em nenhum
/// dos dois, só as ações do usuário — e nenhum teste aqui as dispara.
Future<void> _pump(WidgetTester tester, {Vehicle? vehicle}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: AddVehicle(uid: 'u1', vehicle: vehicle)),
  );
  await tester.pump();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('abre com os números da planilha: R\$ 0,8193/km', (tester) async {
    await _pump(tester);

    // O critério de aceite da spec inteira: cadastrar um carro sem tocar em
    // nada tem de reproduzir o custo que ele calcula hoje no Excel.
    expect(_text(tester, 'vehicle-total-rate'), 'R\$ 0,8193 / km');
  });

  testWidgets('mostra a taxa do combustível separada', (tester) async {
    await _pump(tester);

    expect(_text(tester, 'vehicle-fuel-rate'), 'R\$ 0,7000 /km');
  });

  testWidgets('título muda entre cadastrar e editar', (tester) async {
    await _pump(tester);
    expect(find.text('Novo veículo'), findsOneWidget);
  });

  testWidgets('mudar o consumo recalcula o total na hora', (tester) async {
    await _pump(tester);

    // 20 km/l corta a gasolina pela metade: 0,35 + 0,1193 = 0,4693.
    await tester.enterText(find.byKey(const Key('vehicle-consumption')), '20');
    await tester.pump();

    expect(_text(tester, 'vehicle-total-rate'), 'R\$ 0,4693 / km');
  });

  testWidgets('consumo vazio vira — em vez de mostrar só as peças', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('vehicle-consumption')), '');
    await tester.pump();

    // Mostrar R$ 0,1193 aqui diria que o carro custa um sétimo do que custa.
    expect(_text(tester, 'vehicle-total-rate'), '—');
  });

  testWidgets('trocar para moto refaz as peças com 2 rodas', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Moto'));
    await tester.pumpAndSettle();

    // Peças de moto: 0,02 + 0,02 + 0,0133 + 0,008 + 0,03 = 0,0913 (+0,70).
    expect(_text(tester, 'vehicle-total-rate'), 'R\$ 0,7913 / km');
  });

  testWidgets('peça sem dado é denunciada em vez de sumir da conta', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('part-life-0')), '');
    await tester.pump();

    expect(
      _text(tester, 'vehicle-missing-parts'),
      contains('Óleo'),
    );
    // E o total cai só o que a peça valia, sem fingir que ela entrou.
    expect(_text(tester, 'vehicle-total-rate'), 'R\$ 0,7993 / km');
  });

  testWidgets('editar um veículo preenche os campos gravados', (tester) async {
    await _pump(
      tester,
      vehicle: Vehicle(
        id: 'v1',
        type: VehicleType.carro,
        brandCode: '21',
        brandName: 'Fiat',
        modelCode: '1',
        modelName: 'Fiorino Endurance 1.3',
        nickname: 'Fiorino do trabalho',
        fuel: FuelType.flex,
        fuelPrice: 8.0,
        consumption: 12.0,
        parts: Vehicle.defaultParts(VehicleType.carro),
        createdAt: '2026-01-01T00:00:00.000',
      ),
    );

    expect(find.text('Editar veículo'), findsOneWidget);
    expect(find.text('Fiorino Endurance 1.3'), findsOneWidget);
    // `find.text` acharia dois: o valor e o `hintText`, que é o mesmo texto.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('vehicle-nickname')))
          .controller!
          .text,
      'Fiorino do trabalho',
    );
    // 8,00 / 12 = 0,6667 + 0,1193 = 0,786
    expect(_text(tester, 'vehicle-total-rate'), 'R\$ 0,7860 / km');
  });

  testWidgets('modelo e ano só abrem depois da marca', (tester) async {
    await _pump(tester);

    // Sem marca escolhida, a FIPE não tem o que listar — e oferecer o toque
    // levaria a uma folha vazia.
    expect(
      tester.widget<InkWell>(find.byKey(const Key('vehicle-model'))).onTap,
      isNull,
    );
    expect(
      tester.widget<InkWell>(find.byKey(const Key('vehicle-year'))).onTap,
      isNull,
    );
    expect(
      tester.widget<InkWell>(find.byKey(const Key('vehicle-brand'))).onTap,
      isNotNull,
    );
  });
}
