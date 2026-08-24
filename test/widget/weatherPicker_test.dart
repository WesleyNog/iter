import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/services/openWeather.dart';
import 'package:iter/widget/weatherPicker.dart';

/// Abre o seletor pelo fluxo real e guarda o que ele devolveu, para o teste
/// poder distinguir "fechou sem escolher" de "escolheu Sem informar".
Future<List<WeatherChoice?>> _open(
  WidgetTester tester, {
  WeatherType? selected,
}) async {
  final results = <WeatherChoice?>[];

  // Tela de celular de verdade (iPhone 16 Plus). O padrão do teste é 800x600,
  // deitado e baixo: o sheet rola e as opções de baixo saem da dobra, coisa que
  // não acontece no aparelho.
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              results.add(await showWeatherPicker(context, selected: selected));
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('mostra uma opção por ícone desenhado', (tester) async {
    await _open(tester);

    expect(find.text('Sol'), findsOneWidget);
    expect(find.text('Poucas nuvens'), findsOneWidget);
    expect(find.text('Nublado'), findsOneWidget);
    expect(find.text('Chuva'), findsOneWidget);
    expect(find.text('Chuva forte'), findsOneWidget);
    expect(find.text('Trovoada'), findsOneWidget);
    expect(find.text('Vento forte'), findsOneWidget);
    // As duas noturnas: sem estas linhas, tirá-las de `selectableWeather` ou
    // errar um rótulo deixaria a suíte inteira verde — e o único jeito de
    // registrar céu noturno à mão sumiria calado.
    expect(find.text('Noite limpa'), findsOneWidget);
    expect(find.text('Noite nublada'), findsOneWidget);
    expect(find.text('Sem informar'), findsOneWidget);

    // Nada de opções que a API traz mas repetiriam ícone.
    expect(find.text('Garoa'), findsNothing);
    expect(find.text('Neblina'), findsNothing);
  });

  testWidgets('escolher um tempo devolve ele e fecha', (tester) async {
    final results = await _open(tester);

    await tester.tap(find.text('Chuva forte'));
    await tester.pumpAndSettle();

    expect(results.single?.value, WeatherType.heavyRain);
    expect(find.text('Sem informar'), findsNothing);
  });

  testWidgets('"Sem informar" devolve escolha com valor nulo', (tester) async {
    final results = await _open(tester, selected: WeatherType.clear);

    await tester.tap(find.text('Sem informar'));
    await tester.pumpAndSettle();

    // Escolha feita, valor vazio — diferente de fechar sem escolher.
    expect(results.single, isNotNull);
    expect(results.single!.value, isNull);
  });

  testWidgets('fechar sem escolher não devolve escolha nenhuma', (
    tester,
  ) async {
    final results = await _open(tester, selected: WeatherType.rain);

    // Toque fora do sheet: é o gesto de desistir.
    await tester.tapAt(const Offset(200, 60));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
  });

  testWidgets('o tempo atual da rota aparece destacado', (tester) async {
    await _open(tester, selected: WeatherType.thunderstorm);

    final selecionado = tester.widget<Text>(find.text('Trovoada'));
    final outro = tester.widget<Text>(find.text('Sol'));

    expect(selecionado.style?.fontWeight, FontWeight.w700);
    expect(outro.style?.fontWeight, FontWeight.w500);
  });
}
