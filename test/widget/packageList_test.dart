import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/packageLabel.dart';
import 'package:iter/Utils/packageSession.dart';
import 'package:iter/widget/packageList.dart';

PackageSession _session() => PackageSession()
  ..add(
    const LabelRead(
      shipmentId: '47806623578',
      type: PackageType.residencial,
      bairro: 'Papicu',
      rawBairro: 'Papicu',
    ),
  )
  ..add(
    const LabelRead(
      shipmentId: '47878868074',
      type: PackageType.agencia,
      bairro: 'Meireles',
      rawBairro: 'Meireles',
    ),
  )
  ..add(const LabelRead(shipmentId: '41111111111', rawBairro: 'Água Fria'));

/// A tela da câmera faria isto: mudar a sessão quando a lista pede.
Future<PackageSession> _pump(
  WidgetTester tester, {
  PackageListFilter filter = PackageListFilter.todos,
}) async {
  final session = _session();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PackageList(
          session: session,
          onRemove: session.remove,
          onSetType: session.setType,
          initialFilter: filter,
        ),
      ),
    ),
  );
  return session;
}

void main() {
  testWidgets('deslizar tira o pacote da carga', (tester) async {
    final session = await _pump(tester);

    await tester.drag(
      find.byKey(const ValueKey('pacote-47878868074')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(session.total, 2);
    expect(session.count(PackageType.agencia), 0);
    expect(find.text('Meireles'), findsNothing);
  });

  testWidgets('tocar na letra corrige o tipo', (tester) async {
    final session = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('tipo-41111111111')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A · Agência'));
    await tester.pumpAndSettle();

    expect(session['41111111111']!.type, PackageType.agencia);
    expect(session.untyped, 0);
  });

  testWidgets('aberta pelo A, mostra só as agências', (tester) async {
    await _pump(tester, filter: PackageListFilter.agencia);

    expect(find.text('Meireles'), findsOneWidget);
    expect(find.text('Papicu'), findsNothing);
  });

  testWidgets('trocar o filtro mostra o resto', (tester) async {
    await _pump(tester, filter: PackageListFilter.agencia);

    await tester.tap(find.byKey(const ValueKey('filtro-todos')));
    await tester.pumpAndSettle();

    expect(find.text('Papicu'), findsOneWidget);
    expect(find.text('Meireles'), findsOneWidget);
  });

  testWidgets('bairro que não casou mostra o que foi lido', (tester) async {
    await _pump(tester);

    expect(find.text('Sem bairro'), findsOneWidget);
    expect(find.textContaining('Água Fria'), findsOneWidget);
  });

  testWidgets('os últimos dígitos do envio, para achar o pacote na mão', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('…23578'), findsOneWidget);
  });
}
