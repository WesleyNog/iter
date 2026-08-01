import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeTime.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/model/newRouteModal.dart';

NewRouteModal route({
  required String id,
  required String dateRoute,
  String createdAt = '2026-01-01T00:00:00.000',
}) {
  return NewRouteModal(
    id: id,
    company: Company.mercadolivre,
    dateRoute: dateRoute,
    weekday: 1,
    status: StatusRoute.agendado,
    value: 100,
    startAt: RouteTime.parseDate(dateRoute) ?? DateTime(1970),
    createdAt: createdAt,
  );
}

void main() {
  group('parseDate', () {
    test('converte dd/MM/yyyy', () {
      expect(RouteController.parseDate('01/08/2026'), DateTime(2026, 8, 1));
    });

    test('devolve null para formato inválido', () {
      expect(RouteController.parseDate('2026-08-01'), isNull);
      expect(RouteController.parseDate('01/08'), isNull);
      expect(RouteController.parseDate('ab/cd/efgh'), isNull);
      expect(RouteController.parseDate(''), isNull);
    });

    test('devolve null para mês ou dia fora do intervalo', () {
      expect(RouteController.parseDate('01/13/2026'), isNull);
      expect(RouteController.parseDate('32/01/2026'), isNull);
    });
  });

  group('sortByDate', () {
    // "Hoje" fixo para o teste não depender do relógio.
    final hoje = DateTime(2026, 8, 1);

    test('mais perto de hoje primeiro, indo para as mais distantes', () {
      final sorted = RouteController.sortByDate([
        route(id: 'daqui-a-um-mes', dateRoute: '31/08/2026'),
        route(id: 'amanha', dateRoute: '02/08/2026'),
        route(id: 'hoje', dateRoute: '01/08/2026'),
        route(id: 'daqui-a-uma-semana', dateRoute: '08/08/2026'),
      ], reference: hoje);

      expect(sorted.map((r) => r.id), [
        'hoje',
        'amanha',
        'daqui-a-uma-semana',
        'daqui-a-um-mes',
      ]);
    });

    test('passado recente vem antes de futuro distante', () {
      final sorted = RouteController.sortByDate([
        route(id: 'daqui-a-dez-dias', dateRoute: '11/08/2026'),
        route(id: 'ontem', dateRoute: '31/07/2026'),
      ], reference: hoje);

      expect(sorted.map((r) => r.id), ['ontem', 'daqui-a-dez-dias']);
    });

    test('empate de distância fica com a do futuro', () {
      final sorted = RouteController.sortByDate([
        route(id: 'tres-dias-atras', dateRoute: '29/07/2026'),
        route(id: 'em-tres-dias', dateRoute: '04/08/2026'),
      ], reference: hoje);

      expect(sorted.map((r) => r.id), ['em-tres-dias', 'tres-dias-atras']);
    });

    test('ordena por data e não por texto', () {
      // O caso que um orderBy do Firestore erraria: comparando string,
      // '02/01/2026' viria antes de '31/12/2025'.
      final sorted = RouteController.sortByDate([
        route(id: 'ano-novo', dateRoute: '02/01/2026'),
        route(id: 'reveillon', dateRoute: '31/12/2025'),
      ], reference: DateTime(2025, 12, 30));

      expect(sorted.map((r) => r.id), ['reveillon', 'ano-novo']);
    });

    test('mesma data desempata pela data de cadastro', () {
      final sorted = RouteController.sortByDate([
        route(
          id: 'cadastrada-antes',
          dateRoute: '01/08/2026',
          createdAt: '2026-07-01T10:00:00.000',
        ),
        route(
          id: 'cadastrada-depois',
          dateRoute: '01/08/2026',
          createdAt: '2026-07-02T10:00:00.000',
        ),
      ], reference: hoje);

      expect(sorted.first.id, 'cadastrada-depois');
    });

    test('joga data ilegível para o fim, sem lançar', () {
      final sorted = RouteController.sortByDate([
        route(id: 'quebrada', dateRoute: 'sem-data'),
        route(id: 'valida', dateRoute: '01/08/2026'),
      ], reference: hoje);

      expect(sorted.map((r) => r.id), ['valida', 'quebrada']);
    });

    test('não altera a lista recebida', () {
      final original = [
        route(id: 'a', dateRoute: '31/08/2026'),
        route(id: 'b', dateRoute: '02/08/2026'),
      ];
      RouteController.sortByDate(original, reference: hoje);

      expect(original.map((r) => r.id), ['a', 'b']);
    });
  });
}
