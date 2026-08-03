import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/widget/createActionSheet.dart';

/// Sobe uma tela com um botão que abre o menu, e não o sheet solto: o pulo do
/// gato aqui é a ordem pop → `onTap`, que só existe no fluxo real do
/// `showModalBottomSheet`.
Future<void> _open(
  WidgetTester tester, {
  required List<CreateAction> actions,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCreateActionSheet(context, actions: actions),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

List<CreateAction> _actions({VoidCallback? onRoute}) => [
  CreateAction(
    icon: Icons.local_shipping_outlined,
    color: Colors.green,
    title: 'Nova rota',
    subtitle: 'Cadastrar uma rota',
    onTap: onRoute ?? () {},
  ),
  const CreateAction(
    icon: Icons.local_gas_station_outlined,
    color: Colors.orange,
    title: 'Abastecimento',
    subtitle: 'Registrar combustível',
  ),
  const CreateAction(
    icon: Icons.build_outlined,
    color: Colors.blueGrey,
    title: 'Manutenção',
    subtitle: 'Registrar manutenção',
  ),
];

void main() {
  testWidgets('mostra as três ações com título e subtítulo', (tester) async {
    await _open(tester, actions: _actions());

    expect(find.text('Nova rota'), findsOneWidget);
    expect(find.text('Cadastrar uma rota'), findsOneWidget);
    expect(find.text('Abastecimento'), findsOneWidget);
    expect(find.text('Registrar combustível'), findsOneWidget);
    expect(find.text('Manutenção'), findsOneWidget);
    expect(find.text('Registrar manutenção'), findsOneWidget);
  });

  testWidgets('ação pronta fecha o sheet e roda uma vez só', (tester) async {
    var calls = 0;
    await _open(tester, actions: _actions(onRoute: () => calls++));

    await tester.tap(find.text('Nova rota'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    // O sheet sai de cena antes da ação rodar — senão o Navigator empilharia
    // o sheet junto com a tela nova.
    expect(find.text('Nova rota'), findsNothing);
  });

  testWidgets('ação em desenvolvimento não faz nada e não fecha o sheet', (
    tester,
  ) async {
    var calls = 0;
    await _open(tester, actions: _actions(onRoute: () => calls++));

    await tester.tap(find.text('Abastecimento'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('Abastecimento'), findsOneWidget);
  });

  testWidgets('só as ações em desenvolvimento levam o selo "Em breve"', (
    tester,
  ) async {
    await _open(tester, actions: _actions());

    // Uma para abastecimento e outra para manutenção.
    expect(find.text('Em breve'), findsNWidgets(2));
    // A seta é da linha pronta, e é a única.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
