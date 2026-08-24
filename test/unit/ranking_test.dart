import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/monthStats.dart';
import 'package:iter/Utils/ranking.dart';

/// Um balde de mês para o ranking.
///
/// [rotas] são as do mês inteiro; quem decide a disputa é a **amostra do
/// critério** — [cronometradas] com [paradas] no ritmo, [comPacotes] no
/// insucesso. Por padrão toda rota com pacotes tem pacotes informados, que é o
/// caso comum; os testes que separam as populações passam [comPacotes] à mão.
///
/// [paradas] em zero é o balde de quem preencheu hora de fim e não preencheu
/// parada nenhuma: sem denominador não há ritmo, e é assim que os testes de
/// rodapé montam esse caso.
MonthStats _stats({
  int rotas = 10,
  int pacotes = 0,
  int insucessos = 0,
  int? comPacotes,
  int cronometradas = 0,
  int minutos = 0,
  int paradas = 0,
}) {
  return MonthStats(
    routes: rotas,
    packages: pacotes,
    failures: insucessos,
    packagedRoutes: comPacotes ?? (pacotes > 0 ? rotas : 0),
    pacedRoutes: paradas > 0 ? cronometradas : 0,
    pacedMinutes: paradas > 0 ? minutos : 0,
    pacedStops: paradas,
  );
}

List<String> _ordem(List<RankRow> rows) => [for (final r in rows) r.uid];

void main() {
  group('sampleLabel — a legenda embaixo do nome', () {
    RankRow row({int rotas = 17, int amostra = 12, int? unidades = 506}) =>
        RankRow(
          uid: 'eu',
          value: 5.7,
          routes: rotas,
          sampleRoutes: amostra,
          sampleUnits: unidades,
          ranked: true,
        );

    test('o denominador e as rotas que o formaram', () {
      expect(sampleLabel(RankCriterion.ritmo, row()), '506 paradas · 12 rotas');
      expect(
        sampleLabel(RankCriterion.insucesso, row(unidades: 573)),
        '573 pacotes · 12 rotas',
      );
    });

    test('na contagem de rotas, só as rotas', () {
      expect(sampleLabel(RankCriterion.rotas, row(unidades: null)), '17 rotas');
    });

    test('sem amostra, cai nas rotas do mês', () {
      // O rodapé de quem nunca preencheu paradas: dizer "0 paradas · 0 rotas"
      // para quem rodou dezessete troca uma informação verdadeira por zeros.
      expect(
        sampleLabel(RankCriterion.ritmo, row(amostra: 0, unidades: 0)),
        '17 rotas',
      );
    });

    test('denominador zerado também é falta de amostra', () {
      // O caso que escapou: balde antigo devolve `packagedRoutes` pelas rotas
      // do mês e `packages` zerado. A linha afirmava "0 pacotes · 17 rotas" —
      // 17 rotas com pacotes informados somando zero pacotes, as duas metades
      // se contradizendo.
      expect(
        sampleLabel(RankCriterion.insucesso, row(amostra: 17, unidades: 0)),
        '17 rotas',
      );
    });

    test('singular de verdade nos dois lados', () {
      expect(
        sampleLabel(
          RankCriterion.ritmo,
          row(rotas: 1, amostra: 1, unidades: 1),
        ),
        '1 parada · 1 rota',
      );
    });
  });

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

  group('ritmo — menor primeiro, e por parada', () {
    test('quem gasta menos tempo por parada lidera', () {
      final ordem = rankBy(RankCriterion.ritmo, {
        'lento': _stats(
          rotas: 10,
          cronometradas: 10,
          minutos: 5400,
          paradas: 600,
        ),
        'rapido': _stats(
          rotas: 10,
          cronometradas: 10,
          minutos: 3000,
          paradas: 500,
        ),
      });

      expect(_ordem(ordem), ['rapido', 'lento']);
      expect(ordem.first.value, 6);
    });

    test('a rota grande ganha da rota curta — o caso que motivou a troca', () {
      // Os números da tela do usuário: 17 rotas em 2h49 de média contra 5 em
      // 4h27. Pela duração, um abismo; pelo ritmo, praticamente empatados,
      // com o segundo a meio minuto por parada do primeiro.
      final wesley = _stats(
        rotas: 17,
        cronometradas: 17,
        minutos: 2873,
        paradas: 506,
      );
      final meu = _stats(
        rotas: 5,
        cronometradas: 5,
        minutos: 1335,
        paradas: 221,
      );

      // Pelo critério antigo — 2873/17 = 169 min contra 1335/5 = 267 — a
      // ordem era a inversa, e por larga margem.
      final ordem = rankBy(RankCriterion.ritmo, {'wesley': wesley, 'meu': meu});
      expect(_ordem(ordem), ['wesley', 'meu']);
      expect(ordem.first.value, closeTo(5.7, 0.05));
      expect(ordem.last.value, closeTo(6.0, 0.05));
    });

    test('quem nunca preenche hora de fim fica fora da disputa', () {
      // `null` é "não dá para calcular", não "terminou instantaneamente".
      final ordem = rankBy(RankCriterion.ritmo, {
        'semFim': _stats(rotas: 30),
        'comFim': _stats(
          rotas: 10,
          cronometradas: 10,
          minutos: 4800,
          paradas: 400,
        ),
      });

      expect(_ordem(ordem), ['comFim', 'semFim']);
      expect(ordem.last.ranked, isFalse);
      expect(ordem.last.value, isNull);
    });

    test('cronometrar sem informar paradas não dá ritmo', () {
      // Hora de fim em todas as rotas e nenhuma parada digitada: há duração
      // média, e não há ritmo. O ranking antigo classificava essa pessoa; este
      // manda para o rodapé, porque o número que ele ordena não existe.
      final ordem = rankBy(RankCriterion.ritmo, {
        'semParada': _stats(rotas: 20, cronometradas: 20, minutos: 6000),
        'comParada': _stats(
          rotas: 10,
          cronometradas: 10,
          minutos: 3000,
          paradas: 500,
        ),
      });

      expect(_ordem(ordem), ['comParada', 'semParada']);
      expect(ordem.last.ranked, isFalse);
      expect(ordem.last.value, isNull);
      // As 20 rotas do mês continuam visíveis na linha — é o que o rodapé
      // mostra quando não há amostra do critério. Cair na duração média dessa
      // pessoa é que não pode: a coluna estaria comparando minutos por rota
      // com minutos por parada.
      expect(ordem.last.routes, 20);
      expect(ordem.last.sampleRoutes, 0);
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
      final ordem = rankBy(RankCriterion.rotas, {'poucas': _stats(rotas: 2)});

      expect(ordem.single.ranked, isTrue);
    });

    test('o mínimo conta a população da média, não as rotas do mês', () {
      // O defeito que a correção fecha: 40 rotas no mês, **uma** cronometrada.
      // A porta antiga olhava as 40 e deixava disputar com amostra de uma — e
      // a linha ainda anunciava "40 rotas" embaixo do número.
      final ordem = rankBy(RankCriterion.ritmo, {
        'quaseNunca': _stats(
          rotas: 40,
          cronometradas: 1,
          minutos: 60,
          paradas: 40,
        ),
        'sempre': _stats(
          rotas: 8,
          cronometradas: 8,
          minutos: 2400,
          paradas: 400,
        ),
      });

      final fora = ordem.firstWhere((r) => r.uid == 'quaseNunca');
      expect(fora.ranked, isFalse);
      // O número continua visível, e a amostra dele também: uma rota, não 40.
      expect(fora.value, 1.5);
      expect(fora.sampleRoutes, 1);
      expect(fora.routes, 40);

      expect(ordem.first.uid, 'sempre');
      expect(ordem.first.sampleRoutes, 8);
      expect(ordem.first.sampleUnits, 400);
    });

    test('o mesmo vale para o insucesso: a amostra é quem tem pacotes', () {
      final ordem = rankBy(RankCriterion.insucesso, {
        'umaSo': _stats(rotas: 40, pacotes: 8, comPacotes: 1),
        'todas': _stats(rotas: 6, pacotes: 400, insucessos: 6),
      });

      expect(_ordem(ordem), ['todas', 'umaSo']);
      expect(ordem.last.ranked, isFalse);
      expect(ordem.last.sampleRoutes, 1);
      expect(ordem.last.sampleUnits, 8);
    });

    test('uma unidade só não vira "1 paradas"', () {
      // O plural do denominador é decidido pelo critério, e o caso de uma
      // unidade só mora justamente onde a tela mais o desenha: no rodapé de
      // quem tem amostra pequena.
      expect(RankCriterion.ritmo.sampleUnitFor(1), 'parada');
      expect(RankCriterion.ritmo.sampleUnitFor(0), 'paradas');
      expect(RankCriterion.ritmo.sampleUnitFor(506), 'paradas');
      expect(RankCriterion.insucesso.sampleUnitFor(1), 'pacote');
      expect(RankCriterion.insucesso.sampleUnitFor(573), 'pacotes');
      // Na contagem de rotas não há denominador para nomear.
      expect(RankCriterion.rotas.sampleUnitFor(12), isNull);
    });

    test('na contagem de rotas a amostra é a própria contagem', () {
      final linha = rankBy(RankCriterion.rotas, {
        'ana': _stats(rotas: 12),
      }).single;

      expect(linha.sampleRoutes, 12);
      // Sem denominador: o número **é** a amostra, e a linha diz "12 rotas"
      // em vez de repetir o mesmo número duas vezes.
      expect(linha.sampleUnits, isNull);
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

    test('mesmo valor e mesmas rotas: mais denominador na frente', () {
      // 1% de 1.000 pacotes e 1% de 100, as duas com dez rotas. O desempate
      // pelo uid mandaria a amostra fraca para cima em metade dos casos.
      final ordem = rankBy(RankCriterion.insucesso, {
        'ana': _stats(rotas: 10, pacotes: 100, insucessos: 1),
        'bia': _stats(rotas: 10, pacotes: 1000, insucessos: 10),
      });

      expect(_ordem(ordem), ['bia', 'ana']);
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
      final ordem = rankBy(RankCriterion.ritmo, {
        'semFim1': _stats(rotas: 2),
        'semFim2': _stats(rotas: 9),
        'comFim': _stats(
          rotas: 10,
          cronometradas: 10,
          minutos: 3000,
          paradas: 500,
        ),
      });

      expect(_ordem(ordem), ['comFim', 'semFim2', 'semFim1']);
    });

    test('hasCompetition distingue disputa vazia de lista vazia', () {
      final ninguem = rankBy(RankCriterion.ritmo, {
        'ana': _stats(rotas: 20),
        'bia': _stats(rotas: 30),
      });

      expect(ninguem, hasLength(2));
      expect(hasCompetition(ninguem), isFalse);

      expect(hasCompetition(rankBy(RankCriterion.rotas, {})), isFalse);
    });
  });
}
