import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/model/newRouteModal.dart';

/// Rota realizada com o mínimo para o teste em questão.
NewRouteModal _route({
  String id = 'r1',
  Company company = Company.mercadolivre,
  StatusRoute status = StatusRoute.concluido,
  double value = 100,
  DateTime? startAt,
  DateTime? endAt,
  int? packages,
  int? stops,
  bool? isInsucesso,
  int? insucessoQnt,
}) {
  final start = startAt ?? DateTime(2026, 8, 10, 8);

  return NewRouteModal(
    id: id,
    company: company,
    dateRoute:
        '${start.day.toString().padLeft(2, '0')}/'
        '${start.month.toString().padLeft(2, '0')}/${start.year}',
    weekday: start.weekday,
    status: status,
    value: value,
    packages: packages,
    stops: stops,
    startAt: start,
    endAt: endAt,
    isInsucesso: isInsucesso,
    insucessoQnt: insucessoQnt,
    createdAt: start.toIso8601String(),
  );
}

void main() {
  group('recorte', () {
    test('só concluído e pago entram', () {
      final stats = profileStats([
        _route(status: StatusRoute.concluido),
        _route(status: StatusRoute.pago),
        _route(status: StatusRoute.agendado),
        _route(status: StatusRoute.andamento),
      ]);

      // Rota agendada não entregou pacote nenhum.
      expect(stats.routes, 2);
    });

    test('a ida sem rota fica fora da carreira', () {
      // `profileStats` alimenta `profiles/{uid}/stats/all`, que outro
      // entregador lê. Ninguém fica mais produtivo por uma rota que não teve —
      // e, como `monthStats`, este arquivo não mudou uma linha: quem exclui é
      // `realized`.
      final stats = profileStats([
        _route(
          status: StatusRoute.pago,
          packages: 100,
          stops: 80,
          endAt: DateTime(2026, 8, 10, 16),
        ),
        _route(
          id: 'ida',
          status: StatusRoute.semRota,
          packages: 500,
          stops: 400,
          endAt: DateTime(2026, 8, 10, 8, 40),
          isInsucesso: true,
          insucessoQnt: 60,
        ),
      ]);

      expect(stats.routes, 1);
      expect(stats.deliveredPackages, 100);
      expect(stats.stops, 80);
      expect(stats.failureRate, 0);
      expect(stats.averageDuration, const Duration(hours: 8));
    });

    test('lista vazia devolve zeros e nulos, sem lançar', () {
      final stats = profileStats([]);

      expect(stats.routes, 0);
      expect(stats.deliveredPackages, 0);
      expect(stats.stops, 0);
      expect(stats.failureRate, isNull);
      expect(stats.topCompany, isNull);
      expect(stats.averageDuration, isNull);
    });
  });

  group('pacotes entregues', () {
    test('desconta os insucessos', () {
      final stats = profileStats([
        _route(packages: 100, isInsucesso: true, insucessoQnt: 3),
        _route(packages: 50),
      ]);

      expect(stats.deliveredPackages, 147);
    });

    test('rota sem pacotes informados não entra em nenhum dos dois lados', () {
      final stats = profileStats([
        _route(packages: 100),
        // Sem pacotes, o insucesso não tem de onde ser descontado.
        _route(packages: null, isInsucesso: true, insucessoQnt: 40),
      ]);

      expect(stats.deliveredPackages, 100);
      expect(stats.failureRate, 0);
    });

    test('insucesso desligado não desconta, mesmo com quantidade gravada', () {
      final stats = profileStats([
        _route(packages: 10, isInsucesso: false, insucessoQnt: 9),
      ]);

      expect(stats.deliveredPackages, 10);
    });

    test('mais insucessos que pacotes não vira número negativo', () {
      final stats = profileStats([
        _route(packages: 2, isInsucesso: true, insucessoQnt: 5),
      ]);

      expect(stats.deliveredPackages, 0);
    });
  });

  group('paradas', () {
    test('soma as informadas', () {
      final stats = profileStats([
        _route(stops: 40),
        _route(stops: 25),
        _route(stops: null),
      ]);

      expect(stats.stops, 65);
    });
  });

  group('taxa de insucesso', () {
    test('é percentual sobre os pacotes', () {
      final stats = profileStats([
        _route(packages: 200, isInsucesso: true, insucessoQnt: 3),
      ]);

      expect(stats.failureRate, 1.5);
    });

    test('é nula quando ninguém informou pacotes', () {
      final stats = profileStats([_route(packages: null), _route(packages: 0)]);

      // Nula, e não 0% — que afirmaria um dado que não foi coletado.
      expect(stats.failureRate, isNull);
    });
  });

  group('empresa mais rodada', () {
    test('devolve rótulo e participação', () {
      final stats = profileStats([
        _route(company: Company.shopee),
        _route(company: Company.shopee),
        _route(company: Company.shopee),
        _route(company: Company.amazon),
      ]);

      expect(stats.topCompany?.label, 'Shopee');
      expect(stats.topCompany?.share, 75);
    });

    test('empate resolve pelo nome, para o rótulo não dançar', () {
      final stats = profileStats([
        _route(company: Company.shopee),
        _route(company: Company.amazon),
      ]);

      expect(stats.topCompany?.label, 'Amazon');
      expect(stats.topCompany?.share, 50);
    });
  });

  group('tempo médio', () {
    test('é a média de fim menos início', () {
      final stats = profileStats([
        _route(
          startAt: DateTime(2026, 8, 10, 8),
          endAt: DateTime(2026, 8, 10, 14),
        ),
        _route(
          startAt: DateTime(2026, 8, 11, 8),
          endAt: DateTime(2026, 8, 11, 15),
        ),
      ]);

      expect(stats.averageDuration, const Duration(hours: 6, minutes: 30));
    });

    test('rota sem hora de fim é ignorada, não contada como zero', () {
      final stats = profileStats([
        _route(
          startAt: DateTime(2026, 8, 10, 8),
          endAt: DateTime(2026, 8, 10, 14),
        ),
        _route(startAt: DateTime(2026, 8, 11, 8), endAt: null),
      ]);

      // Contar a segunda como zero derrubaria a média para 3h.
      expect(stats.averageDuration, const Duration(hours: 6));
    });

    test('rota que virou o dia tem duração real', () {
      final stats = profileStats([
        _route(
          startAt: DateTime(2026, 8, 10, 22),
          endAt: DateTime(2026, 8, 11, 2),
        ),
      ]);

      expect(stats.averageDuration, const Duration(hours: 4));
    });

    test('duração não positiva é descartada', () {
      final stats = profileStats([
        // Fim antes do início só acontece em documento corrompido: resolveEnd
        // já rola a virada do dia na gravação.
        _route(
          startAt: DateTime(2026, 8, 10, 8),
          endAt: DateTime(2026, 8, 10, 7),
        ),
      ]);

      expect(stats.averageDuration, isNull);
    });

    test('nenhuma rota com hora de fim devolve nulo', () {
      final stats = profileStats([_route(endAt: null)]);

      expect(stats.averageDuration, isNull);
    });
  });

  group('ritmo da carreira — minutos por parada', () {
    test('é a soma dos minutos sobre a soma das paradas', () {
      final stats = profileStats([
        _route(
          startAt: DateTime(2026, 8, 10, 8),
          endAt: DateTime(2026, 8, 10, 16),
          stops: 100,
        ),
        _route(
          id: 'r2',
          startAt: DateTime(2026, 8, 11, 8),
          endAt: DateTime(2026, 8, 11, 12),
          stops: 50,
        ),
      ]);

      // 720 minutos, 150 paradas. **Não** é a média dos dois ritmos (4,8 e
      // 4,8, que aqui coincidem): o certo é a razão das somas, senão uma rota
      // de cinco paradas pesaria igual a uma de duzentas.
      expect(stats.pacedMinutes, 720);
      expect(stats.pacedStops, 150);
      expect(stats.minutesPerStop, 4.8);
    });

    test('rota cronometrada sem paradas fica fora dos dois lados', () {
      final stats = profileStats([
        _route(
          startAt: DateTime(2026, 8, 10, 8),
          endAt: DateTime(2026, 8, 10, 16),
          stops: 100,
        ),
        _route(
          id: 'r2',
          startAt: DateTime(2026, 8, 11, 8),
          endAt: DateTime(2026, 8, 11, 12),
        ),
      ]);

      // A duração média enxerga as duas rotas...
      expect(stats.averageDuration, const Duration(hours: 6));
      // ...e o ritmo, só a que tem denominador. Somar os 240 minutos da outra
      // daria 9,6 min/parada — um ritmo pior do que qualquer uma das rotas.
      expect(stats.pacedMinutes, 480);
      expect(stats.minutesPerStop, 4.8);
    });

    test('parada sem hora de fim não entra no ritmo, mas conta em stops', () {
      final stats = profileStats([
        _route(
          startAt: DateTime(2026, 8, 10, 8),
          endAt: DateTime(2026, 8, 10, 16),
          stops: 100,
        ),
        _route(id: 'r2', startAt: DateTime(2026, 8, 11, 8), stops: 900),
      ]);

      // As 900 paradas contam na carreira — elas aconteceram...
      expect(stats.stops, 1000);
      // ...e ficam fora do ritmo, que não tem tempo medido para dividir. Com
      // elas no denominador, o ritmo seria 0,48 min/parada.
      expect(stats.pacedStops, 100);
      expect(stats.minutesPerStop, 4.8);
    });

    test('sem paradas cronometradas o ritmo é nulo, nunca zero', () {
      final stats = profileStats([
        _route(
          startAt: DateTime(2026, 8, 10, 8),
          endAt: DateTime(2026, 8, 10, 16),
        ),
      ]);

      expect(stats.averageDuration, const Duration(hours: 8));
      expect(stats.minutesPerStop, isNull);
    });

    test('a travessia leva e traz o ritmo', () {
      const original = ProfileStats(
        routes: 17,
        deliveredPackages: 551,
        stops: 506,
        averageDuration: Duration(hours: 2, minutes: 49),
        pacedMinutes: 2873,
        pacedStops: 506,
      );

      final volta = ProfileStats.fromMap(original.toMap());

      expect(volta.pacedMinutes, 2873);
      expect(volta.pacedStops, 506);
      expect(volta.minutesPerStop, closeTo(5.68, 0.01));
    });

    test('carreira publicada antes do ritmo volta sem ritmo', () {
      // O documento do amigo que ainda não reabriu o app: tem `averageMinutes`
      // e não tem as paradas cronometradas. `null` é a verdade sobre ele — o
      // dialog desenha `—` e o número volta sozinho na próxima abertura.
      final volta = ProfileStats.fromMap(const {
        'routes': 17,
        'deliveredPackages': 551,
        'stops': 506,
        'averageMinutes': 169,
      });

      expect(volta.averageDuration, const Duration(minutes: 169));
      expect(volta.minutesPerStop, isNull);
    });
  });
}
