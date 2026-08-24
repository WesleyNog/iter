import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/routeSlidable.dart';

NewRouteModal _route({
  String id = 'r1',
  StatusRoute status = StatusRoute.concluido,
}) {
  final start = DateTime(2026, 8, 10, 8);
  return NewRouteModal(
    id: id,
    company: Company.mercadolivre,
    dateRoute: '10/08/2026',
    weekday: start.weekday,
    status: status,
    value: 100,
    startAt: start,
    createdAt: start.toIso8601String(),
  );
}

/// O que cada gesto disparou, para o teste conferir sem espiar o estado.
class _Taps {
  int edit = 0;
  int delete = 0;
  int paid = 0;
}

Future<_Taps> _pump(
  WidgetTester tester, {
  StatusRoute status = StatusRoute.concluido,
}) async {
  final taps = _Taps();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RouteSlidable(
          route: _route(status: status),
          onEdit: () => taps.edit++,
          onDelete: () => taps.delete++,
          onMarkPaid: () => taps.paid++,
          // `Container` com cor, e não um `SizedBox` pelado: caixa vazia não
          // participa de hit test, e o `drag` acabava acertando o gesto do
          // `Slidable` por baixo. O painel abria e o teste passava — arrastando
          // outra coisa que não o card.
          child: Container(
            key: const ValueKey('card'),
            height: 80,
            width: double.infinity,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );

  return taps;
}

/// Revela um dos painéis. Positivo abre o da esquerda (pagar), negativo o da
/// direita (editar e excluir).
Future<void> _reveal(WidgetTester tester, double dx) async {
  await tester.drag(find.byKey(const ValueKey('card')), Offset(dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  group('quem pode ser marcada como paga', () {
    test('só a concluída', () {
      // A regra que sustenta o atalho inteiro: concluído e pago são os dois
      // `hasRun` com a mesma provisão, então a troca é de fato só o status.
      for (final status in StatusRoute.values) {
        final pode = RouteSlidable(
          route: _route(status: status),
          onEdit: () {},
          onDelete: () {},
          onMarkPaid: () {},
          child: const SizedBox(),
        ).canMarkPaid;

        expect(pode, status == StatusRoute.concluido, reason: status.name);
      }
    });

    testWidgets('a concluída revela o botão de pagar', (tester) async {
      await _pump(tester);
      await _reveal(tester, 200);

      expect(find.byKey(const ValueKey('acao-pagar')), findsOneWidget);
    });

    testWidgets('a paga não revela nada daquele lado', (tester) async {
      await _pump(tester, status: StatusRoute.pago);
      await _reveal(tester, 200);

      expect(find.byKey(const ValueKey('acao-pagar')), findsNothing);
    });

    testWidgets('a agendada também não', (tester) async {
      // Rota agendada não tem provisão — ela nasce ao concluir. Marcá-la paga
      // por aqui deixaria uma rota paga sem combustível nem peças cobrados.
      await _pump(tester, status: StatusRoute.agendado);
      await _reveal(tester, 200);

      expect(find.byKey(const ValueKey('acao-pagar')), findsNothing);
    });

    testWidgets('a sem rota também não', (tester) async {
      // Ela guarda valor líquido e um `noRoutePayment` congelado.
      await _pump(tester, status: StatusRoute.semRota);
      await _reveal(tester, 200);

      expect(find.byKey(const ValueKey('acao-pagar')), findsNothing);
    });

    testWidgets('tocar no botão avisa a tela', (tester) async {
      final taps = await _pump(tester);
      await _reveal(tester, 200);
      await tester.tap(find.byKey(const ValueKey('acao-pagar')));
      await tester.pumpAndSettle();

      expect(taps.paid, 1);
      expect(taps.edit, 0);
      expect(taps.delete, 0);
    });
  });

  group('editar e excluir', () {
    testWidgets('os dois aparecem do outro lado', (tester) async {
      await _pump(tester);
      await _reveal(tester, -250);

      expect(find.byKey(const ValueKey('acao-editar')), findsOneWidget);
      expect(find.byKey(const ValueKey('acao-excluir')), findsOneWidget);
    });

    testWidgets('continuam aparecendo em qualquer status', (tester) async {
      // Só o atalho de pagar é restrito; apagar e corrigir valem sempre.
      for (final status in StatusRoute.values) {
        await _pump(tester, status: status);
        await _reveal(tester, -250);
        expect(
          find.byKey(const ValueKey('acao-editar')),
          findsOneWidget,
          reason: status.name,
        );
      }
    });

    testWidgets('cada um avisa a sua ação', (tester) async {
      final taps = await _pump(tester);
      await _reveal(tester, -250);

      await tester.tap(find.byKey(const ValueKey('acao-editar')));
      await tester.pumpAndSettle();
      expect(taps.edit, 1);

      await _reveal(tester, -250);
      await tester.tap(find.byKey(const ValueKey('acao-excluir')));
      await tester.pumpAndSettle();
      expect(taps.delete, 1);
    });
  });

  group('só o ícone', () {
    testWidgets('nenhuma ação desenha rótulo de texto', (tester) async {
      // A causa, e não a aparência: `SlidableAction` sempre desenha um `Text`
      // junto do ícone e um retângulo cheio atrás. Se alguém voltar a usá-lo,
      // é este `Text` que aparece.
      await _pump(tester);
      await _reveal(tester, -250);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('acao-editar')),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });

    testWidgets('o fundo da ação é transparente', (tester) async {
      await _pump(tester);
      await _reveal(tester, -250);

      final acao = tester.widget<CustomSlidableAction>(
        find.byKey(const ValueKey('acao-editar')),
      );
      expect(acao.backgroundColor, Colors.transparent);
    });

    testWidgets('o ícone é maior que o padrão de 24', (tester) async {
      await _pump(tester);
      await _reveal(tester, -250);

      final icone = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('acao-editar')),
          matching: find.byType(Icon),
        ),
      );
      expect(icone.size, greaterThan(24));
      // Colorido, e não herdando o cinza padrão.
      expect(icone.color, isNotNull);
    });
  });
}
