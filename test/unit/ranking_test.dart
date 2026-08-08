import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/monthStats.dart';
import 'package:iter/Utils/ranking.dart';

/// [minutos] e [pacotes] descrevem a amostra cronometrada; [rotas] é o que
/// decide se a média disputa.
MonthStats _stats({
  int rotas = 10,
  int pacotes = 0,
  int insucessos = 0,
  int cronometradas = 0,
  int minutos = 0,
}) {
  return MonthStats(
    routes: rotas,
    packages: pacotes,
    failures: insucessos,
    timedRoutes: cronometradas,
    totalMinutes: minutos,
    timedPackages: pacotes,
  );
}

List<String> _ordem(List<RankRow> rows) => [for (final r in rows) r.uid];

void main() {
  group('rankingParticipants — uma lista só', () {
    test('o dono vem primeiro, seguido dos amigos', () {
      expect(rankingParticipants('eu', ['ana', 'bia']), ['eu', 'ana', 'bia']);
    });

    test('sem amigos, o dono está lá do mesmo jeito', () {
      // O bug que esta função existe para impedir: o prefetch de perfis era
      // montado só com os amigos, e o dono aparecia no próprio ranking como
      // "Entregador", sem nome nem foto.
      expect(rankingParticipants('eu', []), ['eu']);
    });

    test('não repete o dono se ele aparecer entre os amigos', () {
      expect(rankingParticipants('eu', ['ana', 'eu']), ['eu', 'ana']);
    });
  });

  group('rotas — maior primeiro, sem amostra mínima', () {
    test('ordena do maior para o menor', () {
      final ordem = rankBy(RankCriterion.rotas, {
        'ana': _stats(rotas: 12),
        'bia': _stats(rotas: 40),
        'zeca': _stats(rotas: 3),
      });

      expect(_ordem(ordem), ['bia', 'ana', 'zeca']);
      // Contagem é o próprio placar: exigir amostra mínima esconderia
      // justamente quem rodou pouco, que é a informação.
      expect(ordem.every((r) => r.ranked), isTrue);
    });

    test('quem não rodou aparece com zero, e zero é resposta', () {
      final ordem = rankBy(RankCriterion.rotas, {
        'ana': _stats(rotas: 5),
        'bia': _stats(rotas: 0),
      });

      expect(_ordem(ordem), ['ana', 'bia']);
      expect(ordem.last.value, 0);
      expect(ordem.last.ranked, isTrue);
    });
  });

  group('tempo — menor primeiro', () {
    test('quem termina mais rápido lidera', () {
      final ordem = rankBy(RankCriterion.tempo, {
        'lento': _stats(rotas: 10, cronometradas: 10, minutos: 5400),
        'rapido': _stats(rotas: 10, cronometradas: 10, minutos: 3000),
      });

      expect(_ordem(ordem), ['rapido', 'lento']);
      expect(ordem.first.value, 300);
    });

    test('quem nunca preenche hora de fim fica fora da disputa', () {
      // `null` é "não dá para calcular", não "terminou instantaneamente".
      final ordem = rankBy(RankCriterion.tempo, {
        'semFim': _stats(rotas: 30),
        'comFim': _stats(rotas: 10, cronometradas: 10, minutos: 4800),
      });

      expect(_ordem(ordem), ['comFim', 'semFim']);
      expect(ordem.last.ranked, isFalse);
      expect(ordem.last.value, isNull);
    });
  });

  group('insucesso — menor primeiro', () {
    test('menor taxa lidera', () {
      final ordem = rankBy(RankCriterion.insucesso, {
        'ana': _stats(rotas: 20, pacotes: 1000, insucessos: 14),
        'bia': _stats(rotas: 20, pacotes: 1000, insucessos: 3),
      });

      expect(_ordem(ordem), ['bia', 'ana']);
      expect(ordem.first.value, closeTo(0.3, 0.001));
    });

    test('quem nunca preenche pacotes fica fora', () {
      final ordem = rankBy(RankCriterion.insucesso, {
        'semPacote': _stats(rotas: 30),
        'comPacote': _stats(rotas: 10, pacotes: 500, insucessos: 5),
      });

      expect(_ordem(ordem), ['comPacote', 'semPacote']);
      expect(ordem.last.ranked, isFalse);
    });
  });

  group('amostra mínima — o caso que motivou a regra', () {
    test('uma rota perfeita não ganha de quarenta rotas boas', () {
      // O caso literal: 1 rota de 8 pacotes sem insucesso dá 0%, contra 40
      // rotas e 3.000 pacotes a 1,4%. Sem o mínimo, o 0% lideraria.
      final ordem = rankBy(RankCriterion.insucesso, {
        'novato': _stats(rotas: 1, pacotes: 8),
        'veterano': _stats(rotas: 40, pacotes: 3000, insucessos: 42),
      });

      expect(_ordem(ordem), ['veterano', 'novato']);
      expect(ordem.first.ranked, isTrue);
      expect(ordem.last.ranked, isFalse);
      // O número continua visível — fica fora da disputa, não escondido.
      expect(ordem.last.value, 0);
    });

    test('exatamente o mínimo já disputa', () {
      final ordem = rankBy(RankCriterion.insucesso, {
        'nolimite': _stats(rotas: minimumRoutes, pacotes: 100),
        'abaixo': _stats(rotas: minimumRoutes - 1, pacotes: 100),
      });

      expect(ordem.firstWhere((r) => r.uid == 'nolimite').ranked, isTrue);
      expect(ordem.firstWhere((r) => r.uid == 'abaixo').ranked, isFalse);
    });

    test('o mínimo não se aplica à contagem de rotas', () {
      final ordem = rankBy(RankCriterion.rotas, {
        'poucas': _stats(rotas: 2),
      });

      expect(ordem.single.ranked, isTrue);
    });
  });

  group('desempate — a ordem não pode dançar', () {
    test('mesmo valor: mais amostra na frente', () {
      final ordem = rankBy(RankCriterion.insucesso, {
        'pouca': _stats(rotas: 6, pacotes: 100, insucessos: 1),
        'muita': _stats(rotas: 30, pacotes: 1000, insucessos: 10),
      });

      // Os dois dão 1%; quem tem 30 rotas sustenta melhor o mesmo número.
      expect(_ordem(ordem), ['muita', 'pouca']);
    });

    test('mesmo valor e mesma amostra: resolve pelo uid', () {
      final igual = _stats(rotas: 10, pacotes: 500, insucessos: 5);
      final ordem = rankBy(RankCriterion.insucesso, {
        'zeca': igual,
        'ana': igual,
        'bia': igual,
      });

      expect(_ordem(ordem), ['ana', 'bia', 'zeca']);
    });
  });

  group('rodapé e disputa vazia', () {
    test('quem não disputa vem no fim, ordenado por rotas', () {
      final ordem = rankBy(RankCriterion.tempo, {
        'semFim1': _stats(rotas: 2),
        'semFim2': _stats(rotas: 9),
        'comFim': _stats(rotas: 10, cronometradas: 10, minutos: 3000),
      });

      expect(_ordem(ordem), ['comFim', 'semFim2', 'semFim1']);
    });

    test('hasCompetition distingue disputa vazia de lista vazia', () {
      final ninguem = rankBy(RankCriterion.tempo, {
        'ana': _stats(rotas: 20),
        'bia': _stats(rotas: 30),
      });

      expect(ninguem, hasLength(2));
      expect(hasCompetition(ninguem), isFalse);

      expect(hasCompetition(rankBy(RankCriterion.rotas, {})), isFalse);
    });
  });
}
