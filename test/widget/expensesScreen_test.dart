import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/screens/expensesScreen.dart';

const _station = FuelStation(
  id: 'way-1',
  name: 'Posto Apiguana',
  lat: -3.73,
  lng: -38.52,
);

Supply _supply({double value = 250, String date = '2026-10-05T14:32:00.000'}) =>
    Supply(
      id: 's1',
      vehicleId: 'v1',
      value: value,
      liters: 40,
      station: _station,
      date: date,
      createdAt: '2026-10-05T14:32:00.000',
    );

const _maintenance = Maintenance(
  id: 'm1',
  item: MaintenanceItem.pneu,
  action: MaintenanceAction.reparo,
  value: 120,
  date: '2026-10-03T10:00:00.000',
  createdAt: '2026-10-03T10:00:00.000',
);

/// O que a tela pediu, sem Firestore e sem abrir formulário.
class _Calls {
  final deletedSupplies = <String>[];
  final deletedMaintenances = <String>[];
}

Future<_Calls> _pump(
  WidgetTester tester, {
  Supply? Function(Supply)? editSupply,
  Maintenance? Function(Maintenance)? editMaintenance,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: ExpensesScreen(
        uid: 'u1',
        supplies: [_supply()],
        maintenances: const [_maintenance],
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
        periodLabel: 'Outubro',
        supplyEditor: (_, supply) async => editSupply?.call(supply),
        maintenanceEditor: (_, item) async => editMaintenance?.call(item),
        supplyDeleter: (_, id) async => calls.deletedSupplies.add(id),
        maintenanceDeleter: (_, id) async => calls.deletedMaintenances.add(id),
      ),
    ),
  );
  return calls;
}

/// Abre o painel de ações da linha [index]. O abastecimento (dia 5) vem antes
/// da manutenção (dia 3): o extrato é do mais recente para o mais antigo.
Future<void> _reveal(WidgetTester tester, int index) async {
  await tester.drag(
    find.byKey(Key('expense-title-$index')),
    const Offset(-300, 0),
  );
  await tester.pumpAndSettle();
}

/// O aviso de sucesso some sozinho; sem isto o timer dele fica pendente.
Future<void> _flushToast(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 10));

void main() {
  testWidgets('deslizar mostra editar e excluir', (tester) async {
    await _pump(tester);
    await _reveal(tester, 0);

    expect(find.byKey(const ValueKey('gasto-editar-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('gasto-excluir-s1')), findsOneWidget);
  });

  testWidgets('excluir pergunta antes, e cancelar não apaga', (tester) async {
    final calls = await _pump(tester);
    await _reveal(tester, 0);
    await tester.tap(find.byKey(const ValueKey('gasto-excluir-s1')));
    await tester.pumpAndSettle();

    expect(find.text('Excluir abastecimento?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(calls.deletedSupplies, isEmpty);
    expect(find.textContaining('Apiguana'), findsOneWidget);
  });

  testWidgets('confirmar apaga e tira a linha', (tester) async {
    final calls = await _pump(tester);
    await _reveal(tester, 0);
    await tester.tap(find.byKey(const ValueKey('gasto-excluir-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gasto-confirmar-exclusao')));
    await tester.pumpAndSettle();
    await _flushToast(tester);

    expect(calls.deletedSupplies, ['s1']);
    expect(find.textContaining('Apiguana'), findsNothing);
    // A manutenção continua: só a linha escolhida sai.
    expect(find.text('R\$ 120,00'), findsOneWidget);
  });

  testWidgets('editar troca a linha pelo que o formulário gravou', (
    tester,
  ) async {
    await _pump(tester, editSupply: (_) => _supply(value: 300));
    await _reveal(tester, 0);
    await tester.tap(find.byKey(const ValueKey('gasto-editar-s1')));
    await tester.pumpAndSettle();

    expect(find.text('R\$ 300,00'), findsOneWidget);
    expect(find.text('R\$ 250,00'), findsNothing);
  });

  testWidgets('a data levada para fora do período tira a linha', (
    tester,
  ) async {
    // Mesmo filtro do card do Resumo: o lançamento de setembro não é deste
    // extrato de outubro.
    await _pump(
      tester,
      editSupply: (_) => _supply(date: '2026-09-20T12:00:00.000'),
    );
    await _reveal(tester, 0);
    await tester.tap(find.byKey(const ValueKey('gasto-editar-s1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Apiguana'), findsNothing);
  });

  testWidgets('voltar do formulário sem salvar não muda nada', (tester) async {
    await _pump(tester, editSupply: (_) => null);
    await _reveal(tester, 0);
    await tester.tap(find.byKey(const ValueKey('gasto-editar-s1')));
    await tester.pumpAndSettle();

    expect(find.text('R\$ 250,00'), findsOneWidget);
  });

  testWidgets('a manutenção desliza, edita e exclui do mesmo jeito', (
    tester,
  ) async {
    final calls = await _pump(
      tester,
      editMaintenance: (item) => Maintenance(
        id: item.id,
        item: item.item,
        action: item.action,
        value: 95,
        date: item.date,
        createdAt: item.createdAt,
      ),
    );

    await _reveal(tester, 1);
    await tester.tap(find.byKey(const ValueKey('gasto-editar-m1')));
    await tester.pumpAndSettle();
    expect(find.text('R\$ 95,00'), findsOneWidget);

    await _reveal(tester, 1);
    await tester.tap(find.byKey(const ValueKey('gasto-excluir-m1')));
    await tester.pumpAndSettle();
    expect(find.text('Excluir manutenção?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gasto-confirmar-exclusao')));
    await tester.pumpAndSettle();
    await _flushToast(tester);

    expect(calls.deletedMaintenances, ['m1']);
    expect(find.text('R\$ 95,00'), findsNothing);
  });
}
