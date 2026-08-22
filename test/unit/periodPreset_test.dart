import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/periodPreset.dart';

/// Toda referência é fixa: "este mês" muda de resposta todo dia 1, e um teste
/// que consulta o relógio fica verde onze meses e vermelho no décimo segundo.
void main() {
  group('mês', () {
    test('este mês vai do dia 1 ao último', () {
      final range = rangeOf(PeriodPreset.esteMes, DateTime(2026, 8, 15))!;
      expect(range.start, DateTime(2026, 8, 1));
      expect(range.end, DateTime(2026, 8, 31));
    });

    test('fevereiro bissexto fecha no dia 29', () {
      // Dia 0 do mês seguinte é o último do atual, então isto sai sem nenhum
      // caso especial — e é justamente por não ter caso especial que precisa
      // de teste.
      final range = rangeOf(PeriodPreset.esteMes, DateTime(2028, 2, 10))!;
      expect(range.end, DateTime(2028, 2, 29));
    });

    test('mês anterior é o mês inteiro de trás', () {
      final range = rangeOf(PeriodPreset.mesAnterior, DateTime(2026, 8, 15))!;
      expect(range.start, DateTime(2026, 7, 1));
      expect(range.end, DateTime(2026, 7, 31));
    });

    test('mês anterior a janeiro é dezembro do ano passado', () {
      // `month - 1` vira o mês 0, que o construtor normaliza. O `if` que não
      // existe é o que este teste está guardando.
      final range = rangeOf(PeriodPreset.mesAnterior, DateTime(2026, 1, 10))!;
      expect(range.start, DateTime(2025, 12, 1));
      expect(range.end, DateTime(2025, 12, 31));
    });

    test('a hora da referência não vaza para as pontas', () {
      final range = rangeOf(PeriodPreset.esteMes, DateTime(2026, 8, 15, 14, 30))!;
      expect(range.start, DateTime(2026, 8, 1));
      expect(range.end, DateTime(2026, 8, 31));
    });
  });

  group('semana', () {
    // 17/08/2026 é uma segunda; 23/08 é o domingo dela.
    const segunda = 17;
    const domingo = 23;

    test('no meio da semana pega de segunda a domingo', () {
      // 19/08 é quarta.
      final range = rangeOf(PeriodPreset.estaSemana, DateTime(2026, 8, 19))!;
      expect(range.start, DateTime(2026, 8, segunda));
      expect(range.end, DateTime(2026, 8, domingo));
    });

    test('no domingo ainda é a semana que está acabando', () {
      // O dia em que a conta errada devolve a semana **seguinte**: domingo é
      // `weekday == 7`, o fim do bloco, não o começo do próximo.
      final range = rangeOf(PeriodPreset.estaSemana, DateTime(2026, 8, domingo))!;
      expect(range.start, DateTime(2026, 8, segunda));
      expect(range.end, DateTime(2026, 8, domingo));
    });

    test('na segunda é a semana que está começando', () {
      final range = rangeOf(PeriodPreset.estaSemana, DateTime(2026, 8, segunda))!;
      expect(range.start, DateTime(2026, 8, segunda));
      expect(range.end, DateTime(2026, 8, domingo));
    });

    test('semana anterior é a de trás, fechada', () {
      final range = rangeOf(PeriodPreset.semanaAnterior, DateTime(2026, 8, 19))!;
      expect(range.start, DateTime(2026, 8, 10));
      expect(range.end, DateTime(2026, 8, 16));
    });

    test('na segunda, a semana anterior é a que acabou ontem', () {
      final range = rangeOf(
        PeriodPreset.semanaAnterior,
        DateTime(2026, 8, segunda),
      )!;
      expect(range.start, DateTime(2026, 8, 10));
      expect(range.end, DateTime(2026, 8, 16));
    });

    test('a semana atravessa a virada do mês', () {
      // 02/09/2026 é quarta; a segunda dela é 31/08.
      final range = rangeOf(PeriodPreset.estaSemana, DateTime(2026, 9, 2))!;
      expect(range.start, DateTime(2026, 8, 31));
      expect(range.end, DateTime(2026, 9, 6));
    });

    test('a semana atravessa a virada do ano', () {
      // 01/01/2027 é sexta; a segunda dela é 28/12/2026.
      final range = rangeOf(PeriodPreset.estaSemana, DateTime(2027, 1, 1))!;
      expect(range.start, DateTime(2026, 12, 28));
      expect(range.end, DateTime(2027, 1, 3));
    });

    test('semana e semana anterior são sete dias e não se tocam', () {
      final atual = rangeOf(PeriodPreset.estaSemana, DateTime(2026, 8, 19))!;
      final anterior = rangeOf(
        PeriodPreset.semanaAnterior,
        DateTime(2026, 8, 19),
      )!;

      expect(atual.end.difference(atual.start).inDays, 6);
      expect(anterior.end.difference(anterior.start).inDays, 6);
      // Encostam sem sobrepor: o domingo de uma é a véspera da segunda da outra.
      expect(anterior.end.add(const Duration(days: 1)), atual.start);
    });

    test('a hora da referência não vaza para as pontas', () {
      final range = rangeOf(PeriodPreset.estaSemana, DateTime(2026, 8, 19, 23, 59))!;
      expect(range.start, DateTime(2026, 8, segunda));
      expect(range.end, DateTime(2026, 8, domingo));
    });
  });

  group('personalizado', () {
    test('não tem recorte próprio', () {
      // `null` é "esta pergunta não se aplica", e é o que faz o widget manter
      // as datas que já estavam na tela. Devolver o mês corrente aqui apagaria
      // a escolha do usuário toda vez que ele reabrisse a seção.
      expect(rangeOf(PeriodPreset.personalizado, DateTime(2026, 8, 15)), isNull);
    });
  });

  group('rótulos', () {
    test('todos os atalhos têm nome em pt-BR', () {
      for (final preset in PeriodPreset.values) {
        expect(presetLabel(preset), isNotEmpty);
      }
      expect(presetLabel(PeriodPreset.esteMes), 'Este Mês');
      expect(presetLabel(PeriodPreset.mesAnterior), 'Mês Anterior');
      expect(presetLabel(PeriodPreset.estaSemana), 'Esta Semana');
      expect(presetLabel(PeriodPreset.semanaAnterior), 'Semana Anterior');
      expect(presetLabel(PeriodPreset.personalizado), 'Personalizado');
    });
  });

  group('compatibilidade', () {
    test('currentMonth é o mesmo recorte de esteMes', () {
      // `PeriodFilter.currentMonth` delega para cá e o Resumo depende dela.
      final reference = DateTime(2026, 8, 15);
      expect(currentMonth(reference), rangeOf(PeriodPreset.esteMes, reference));
    });
  });
}
