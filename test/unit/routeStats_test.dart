import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/model/newRouteModal.dart';

/// Monta uma rota com o mínimo necessário para o teste em questão.
///
/// O padrão é uma rota realizada de R$ 100 no dia 10/08/2026 às 08h, para cada
/// teste precisar declarar só o campo que está examinando.
NewRouteModal _route({
  String id = 'r1',
  Company company = Company.mercadolivre,
  StatusRoute status = StatusRoute.concluido,
  double value = 100,
  DateTime? startAt,
  List<String>? adress,
  bool? isInsucesso,
  int? insucessoQnt,
  Map<String, int> insucessoPorBairro = const {},
  int? packages,
  String? weather,
}) {
  final start = startAt ?? DateTime(2026, 8, 10, 8);

  return NewRouteModal(
    id: id,
    company: company,
    dateRoute:
        '${start.day.toString().padLeft(2, '0')}/'
        '${start.month.toString().padLeft(2, '0')}/${start.year}',
    weekday: start.weekday,
    weather: weather,
    status: status,
    value: value,
    packages: packages,
    adress: adress,
    startAt: start,
    isInsucesso: isInsucesso,
    insucessoQnt: insucessoQnt,
    insucessoPorBairro: insucessoPorBairro,
    createdAt: start.toIso8601String(),
  );
}

/// Período de agosto/2026 inteiro, usado pela maioria dos testes.
final _start = DateTime(2026, 8, 1);
final _end = DateTime(2026, 8, 31);

/// Atalho para achar um degrau pelo rótulo sem depender da posição.
double _valueOf(List<RankEntry> ranking, String label) =>
    ranking.firstWhere((entry) => entry.label == label).value;

bool _has(List<RankEntry> ranking, String label) =>
    ranking.any((entry) => entry.label == label);

/// Os mesmos atalhos para os índices, que carregam a conta além da taxa.
FailureRate _rateOf(List<FailureRate> rates, String label) =>
    rates.firstWhere((rate) => rate.label == label);

bool _hasRate(List<FailureRate> rates, String label) =>
    rates.any((rate) => rate.label == label);

void main() {
  group('realizedInPeriod', () {
    test('inclui as duas pontas do período', () {
      final routes = [
        _route(id: 'primeiro', startAt: DateTime(2026, 8, 1, 6)),
        _route(id: 'ultimo', startAt: DateTime(2026, 8, 31, 23, 59)),
      ];

      final result = realizedInPeriod(routes, start: _start, end: _end);

      expect(result.map((r) => r.id), ['primeiro', 'ultimo']);
    });

    test('exclui o dia anterior ao início e o seguinte ao fim', () {
      final routes = [
        _route(id: 'antes', startAt: DateTime(2026, 7, 31, 23)),
        _route(id: 'dentro', startAt: DateTime(2026, 8, 15)),
        _route(id: 'depois', startAt: DateTime(2026, 9, 1)),
      ];

      final result = realizedInPeriod(routes, start: _start, end: _end);

      expect(result.map((r) => r.id), ['dentro']);
    });

    test('compara só a data: a hora do filtro não recorta o dia', () {
      final routes = [_route(startAt: DateTime(2026, 8, 31, 22))];

      final result = realizedInPeriod(
        routes,
        // Fim escolhido às 00h do dia 31 — a rota das 22h ainda é do dia 31.
        start: DateTime(2026, 8, 1, 13),
        end: DateTime(2026, 8, 31),
      );

      expect(result, hasLength(1));
    });

    test('inPeriod mantém todos os status', () {
      final routes = [
        _route(id: 'agendado', status: StatusRoute.agendado),
        _route(id: 'andamento', status: StatusRoute.andamento),
        _route(id: 'concluido', status: StatusRoute.concluido),
        _route(id: 'pago', status: StatusRoute.pago),
      ];

      final result = inPeriod(routes, start: _start, end: _end);

      expect(result, hasLength(4));
    });

    test('notRunYet é agendado mais em andamento', () {
      final routes = [
        _route(id: 'agendado', status: StatusRoute.agendado),
        _route(id: 'andamento', status: StatusRoute.andamento),
        _route(id: 'concluido', status: StatusRoute.concluido),
        _route(id: 'pago', status: StatusRoute.pago),
      ];

      expect(notRunYet(routes).map((r) => r.id), ['agendado', 'andamento']);
    });

    test('só concluído e pago entram', () {
      final routes = [
        _route(id: 'agendado', status: StatusRoute.agendado),
        _route(id: 'andamento', status: StatusRoute.andamento),
        _route(id: 'concluido', status: StatusRoute.concluido),
        _route(id: 'pago', status: StatusRoute.pago),
      ];

      final result = realizedInPeriod(routes, start: _start, end: _end);

      expect(result.map((r) => r.id), ['concluido', 'pago']);
    });
  });

  group('summarize', () {
    test('total, quantidade e média', () {
      final summary = summarize([
        _route(value: 100),
        _route(value: 50),
        _route(value: 30),
      ]);

      expect(summary.total, 180);
      expect(summary.count, 3);
      expect(summary.average, 60);
    });

    test('lista vazia não divide por zero', () {
      final summary = summarize([]);

      expect(summary.total, 0);
      expect(summary.count, 0);
      expect(summary.average, 0);
      expect(summary.deliveryRate, isNull);
    });

    test('taxa de entrega usa só rotas com pacotes informados', () {
      final summary = summarize([
        _route(packages: 100, isInsucesso: true, insucessoQnt: 5),
        // Sem pacotes: não entra em nenhum dos dois lados da conta.
        _route(packages: null, isInsucesso: true, insucessoQnt: 40),
      ]);

      expect(summary.packages, 100);
      expect(summary.failures, 5);
      expect(summary.deliveryRate, 0.95);
    });

    test('taxa de entrega é nula quando ninguém informou pacotes', () {
      final summary = summarize([_route(packages: null), _route(packages: 0)]);

      expect(summary.deliveryRate, isNull);
    });

    test('a receber é o concluído; recebido é o pago', () {
      final summary = summarize([
        _route(status: StatusRoute.concluido, value: 200),
        _route(status: StatusRoute.concluido, value: 45),
        _route(status: StatusRoute.pago, value: 155),
      ]);

      expect(summary.pending, 245);
      expect(summary.pendingCount, 2);
      expect(summary.received, 155);
      expect(summary.total, 400);
      expect(summary.receivedRate, closeTo(0.3875, 0.0001));
    });

    test('agendado e em andamento somam a estimativa', () {
      final summary = summarize([
        _route(status: StatusRoute.agendado, value: 100),
        _route(status: StatusRoute.andamento, value: 80),
        _route(status: StatusRoute.pago, value: 20),
      ]);

      expect(summary.upcoming, 180);
      expect(summary.scheduledCount, 1);
      expect(summary.runningCount, 1);
      expect(summary.upcomingCount, 2);
      expect(summary.total, 200);
      expect(summary.realizedTotal, 20);
    });

    test('rota agendada com pacotes não entra na taxa de entrega', () {
      final summary = summarize([
        _route(status: StatusRoute.pago, packages: 100),
        // Pacotes estimados numa rota que ainda não saiu: contá-los faria a
        // taxa subir sem ninguém ter entregue nada.
        _route(status: StatusRoute.agendado, packages: 500),
      ]);

      expect(summary.packages, 100);
      expect(summary.deliveryRate, 1);
    });

    test('agendada não derruba a taxa de recebimento', () {
      final summary = summarize([
        _route(status: StatusRoute.pago, value: 100),
        _route(status: StatusRoute.agendado, value: 900),
      ]);

      // 100% do que aconteceu foi pago; marcar rota na agenda não muda isso.
      expect(summary.receivedRate, 1);
    });

    test('tudo pago zera o a receber', () {
      final summary = summarize([_route(status: StatusRoute.pago, value: 90)]);

      expect(summary.pending, 0);
      expect(summary.receivedRate, 1);
    });

    test('sem rota não existe proporção de recebimento', () {
      expect(summarize([]).receivedRate, isNull);
    });

    test('mais insucessos que pacotes não vira taxa negativa', () {
      final summary = summarize([
        _route(packages: 2, isInsucesso: true, insucessoQnt: 5),
      ]);

      expect(summary.deliveryRate, 0);
    });
  });

  group('pendingPayment / receivedPayment', () {
    test('separa o que falta receber do que já entrou', () {
      final routes = [
        _route(id: 'a', status: StatusRoute.concluido),
        _route(id: 'b', status: StatusRoute.pago),
        _route(id: 'c', status: StatusRoute.concluido),
      ];

      expect(pendingPayment(routes).map((r) => r.id), ['a', 'c']);
      expect(receivedPayment(routes).map((r) => r.id), ['b']);
    });

    test('agendado e em andamento não são "a receber"', () {
      final routes = [
        _route(status: StatusRoute.agendado),
        _route(status: StatusRoute.andamento),
      ];

      // A rota nem aconteceu; contar o dinheiro dela seria contar com o ovo.
      expect(pendingPayment(routes), isEmpty);
    });
  });

  group('valueByStatus', () {
    test('vem na ordem do ciclo, não por tamanho', () {
      final byStatus = valueByStatus([
        _route(status: StatusRoute.pago, value: 500),
        _route(status: StatusRoute.agendado, value: 10),
      ]);

      // A barra do resumo é lida como esteira: agendado → andamento →
      // concluído → pago, mesmo com o pago sendo o maior.
      expect(byStatus.map((e) => e.status), StatusRoute.values);
      expect(byStatus.first.value, 10);
      expect(byStatus.last.value, 500);
    });

    test('status sem rota vem zerado', () {
      final byStatus = valueByStatus([
        _route(status: StatusRoute.pago, value: 500),
      ]);

      expect(byStatus.where((e) => e.value > 0), hasLength(1));
      expect(byStatus, hasLength(4));
    });
  });

  group('rankings por empresa', () {
    test('valor por empresa, do maior para o menor', () {
      final ranking = valuePerCompany([
        _route(company: Company.shopee, value: 30),
        _route(company: Company.mercadolivre, value: 100),
        _route(company: Company.mercadolivre, value: 50),
        _route(company: Company.amazon, value: 80),
      ]);

      expect(ranking.map((e) => e.label), [
        'Mercado Livre',
        'Amazon',
        'Shopee',
      ]);
      expect(ranking.map((e) => e.value), [150, 80, 30]);
    });

    test('valueByCompany preserva o enum, na mesma ordem', () {
      final grouped = valueByCompany([
        _route(company: Company.shopee, value: 30),
        _route(company: Company.amazon, value: 80),
      ]);

      expect(grouped.map((e) => e.company), [Company.amazon, Company.shopee]);
      expect(grouped.map((e) => e.value), [80, 30]);
    });

    test('quantidade de rotas por empresa', () {
      final ranking = countPerCompany([
        _route(company: Company.amazon),
        _route(company: Company.amazon),
        _route(company: Company.shopee),
      ]);

      expect(_valueOf(ranking, 'Amazon'), 2);
      expect(_valueOf(ranking, 'Shopee'), 1);
    });

    test('insucesso sem quantidade informada conta 1', () {
      final ranking = failuresPerCompany([
        _route(company: Company.amazon, isInsucesso: true),
      ]);

      expect(_valueOf(ranking, 'Amazon'), 1);
    });

    test('insucesso desligado ou ausente não conta', () {
      final ranking = failuresPerCompany([
        // insucessoQnt gravado, mas o switch desligado: não é insucesso.
        _route(company: Company.amazon, isInsucesso: false, insucessoQnt: 9),
        _route(company: Company.shopee, isInsucesso: null, insucessoQnt: 4),
      ]);

      expect(_valueOf(ranking, 'Amazon'), 0);
      expect(_valueOf(ranking, 'Shopee'), 0);
    });

    test('empresa que rodou sem insucesso aparece zerada', () {
      final ranking = failuresPerCompany([
        _route(company: Company.amazon, isInsucesso: true, insucessoQnt: 3),
        _route(company: Company.shopee),
      ]);

      expect(ranking.map((e) => e.label), ['Amazon', 'Shopee']);
      expect(_valueOf(ranking, 'Shopee'), 0);
    });

    test('índice de insucesso é percentual sobre pacotes', () {
      final ranking = failureRatePerCompany([
        _route(
          company: Company.amazon,
          packages: 100,
          isInsucesso: true,
          insucessoQnt: 5,
        ),
        _route(
          company: Company.shopee,
          packages: 50,
          isInsucesso: true,
          insucessoQnt: 5,
        ),
      ]);

      // 10% da Shopee dói mais que 5% da Amazon, mesmo sendo o mesmo número.
      expect(ranking.map((e) => e.label), ['Shopee', 'Amazon']);
      expect(_rateOf(ranking, 'Amazon').rate, 5);
      expect(_rateOf(ranking, 'Shopee').rate, 10);

      // A conta vem junto: é ela que o card mostra entre parênteses.
      expect(_rateOf(ranking, 'Amazon').failures, 5);
      expect(_rateOf(ranking, 'Amazon').packages, 100);
    });

    test('empresa sem pacotes informados fica fora do índice', () {
      final ranking = failureRatePerCompany([
        _route(company: Company.amazon, packages: 100),
        _route(company: Company.shopee, packages: null, isInsucesso: true),
        _route(company: Company.mercadolivre, packages: 0, isInsucesso: true),
      ]);

      // Fora do ranking, e não 0% — que seria afirmar um dado que não existe.
      expect(_hasRate(ranking, 'Shopee'), isFalse);
      expect(_hasRate(ranking, 'Mercado Livre'), isFalse);
      expect(_hasRate(ranking, 'Amazon'), isTrue);
    });
  });

  group('rankings por bairro', () {
    test('cada bairro da rota conta uma passagem', () {
      final ranking = routesPerBairro([
        _route(adress: ['Aldeota', 'Centro']),
        _route(adress: ['Aldeota']),
        _route(adress: ['Cocó']),
      ]);

      expect(ranking.first.label, 'Aldeota');
      expect(_valueOf(ranking, 'Aldeota'), 2);
      expect(_valueOf(ranking, 'Centro'), 1);
    });

    test('rota sem bairro não entra', () {
      final ranking = routesPerBairro([
        _route(adress: null),
        _route(adress: []),
      ]);

      expect(ranking, isEmpty);
    });

    test('insucesso é rateado entre os bairros da rota', () {
      final ranking = failuresPerBairro([
        _route(
          adress: ['Aldeota', 'Centro', 'Cocó'],
          isInsucesso: true,
          insucessoQnt: 3,
        ),
      ]);

      expect(_valueOf(ranking, 'Aldeota'), 1);
      expect(_valueOf(ranking, 'Centro'), 1);
      expect(_valueOf(ranking, 'Cocó'), 1);
    });

    test('a soma do rateio bate com o total de insucessos', () {
      final routes = [
        _route(
          adress: ['Aldeota', 'Centro'],
          isInsucesso: true,
          insucessoQnt: 5,
        ),
        _route(adress: ['Cocó'], isInsucesso: true, insucessoQnt: 2),
      ];

      final total = failuresPerBairro(
        routes,
      ).fold<double>(0, (sum, entry) => sum + entry.value);

      expect(total, closeTo(7, 0.0001));
    });

    test('bairro sem insucesso não polui o ranking', () {
      final ranking = failuresPerBairro([
        _route(adress: ['Aldeota'], isInsucesso: true, insucessoQnt: 1),
        _route(adress: ['Centro']),
      ]);

      expect(ranking.map((e) => e.label), ['Aldeota']);
    });

    test('distribuição exata substitui o rateio', () {
      final ranking = failuresPerBairro([
        _route(
          adress: ['Aldeota', 'Centro', 'Cocó'],
          isInsucesso: true,
          insucessoQnt: 3,
          insucessoPorBairro: {'Aldeota': 3},
        ),
      ]);

      // Sem distribuição isso daria 1,0 em cada um dos três.
      expect(ranking.map((e) => e.label), ['Aldeota']);
      expect(_valueOf(ranking, 'Aldeota'), 3);
    });

    test('distribuição parcial rateia só o restante', () {
      final ranking = failuresPerBairro([
        _route(
          adress: ['Aldeota', 'Centro'],
          isInsucesso: true,
          insucessoQnt: 5,
          // "2 foram na Aldeota, o resto não lembro."
          insucessoPorBairro: {'Aldeota': 2},
        ),
      ]);

      // Os 3 restantes se dividem entre os dois bairros: 1,5 para cada.
      expect(_valueOf(ranking, 'Aldeota'), 3.5);
      expect(_valueOf(ranking, 'Centro'), 1.5);
    });

    test('a soma continua batendo com o total, distribuído ou não', () {
      final routes = [
        _route(
          adress: ['Aldeota', 'Centro'],
          isInsucesso: true,
          insucessoQnt: 5,
          insucessoPorBairro: {'Aldeota': 2},
        ),
        _route(adress: ['Cocó'], isInsucesso: true, insucessoQnt: 4),
      ];

      final total = failuresPerBairro(
        routes,
      ).fold<double>(0, (sum, entry) => sum + entry.value);

      expect(total, closeTo(9, 0.0001));
    });

    test('documento antigo, sem o campo, continua rateado', () {
      final ranking = failuresPerBairro([
        _route(
          adress: ['Aldeota', 'Centro'],
          isInsucesso: true,
          insucessoQnt: 2,
        ),
      ]);

      expect(_valueOf(ranking, 'Aldeota'), 1);
      expect(_valueOf(ranking, 'Centro'), 1);
    });

    test('distribuição citando bairro fora da rota é ignorada', () {
      final ranking = failuresPerBairro([
        _route(
          adress: ['Centro'],
          isInsucesso: true,
          insucessoQnt: 2,
          // A Aldeota saiu de "Bairros" depois da distribuição.
          insucessoPorBairro: {'Aldeota': 2},
        ),
      ]);

      // Os 2 voltam a ser rateados, e o ranking não cita bairro que a rota
      // não tem.
      expect(ranking.map((e) => e.label), ['Centro']);
      expect(_valueOf(ranking, 'Centro'), 2);
    });

    test('distribuição acima do total não infla o ranking', () {
      final ranking = failuresPerBairro([
        _route(
          adress: ['Aldeota', 'Centro'],
          isInsucesso: true,
          insucessoQnt: 2,
          insucessoPorBairro: {'Aldeota': 5, 'Centro': 5},
        ),
      ]);

      final total = ranking.fold<double>(0, (sum, e) => sum + e.value);
      expect(total, 2);
    });

    test('insucesso em rota sem bairro não vira ranking', () {
      final ranking = failuresPerBairro([
        _route(adress: null, isInsucesso: true, insucessoQnt: 4),
      ]);

      expect(ranking, isEmpty);
    });
  });

  group('índice por bairro', () {
    test('os pacotes da rota são divididos por igual entre os bairros', () {
      final ranking = failureRatePerBairro([
        _route(
          adress: ['Aeroporto', 'Vila União'],
          packages: 48,
          isInsucesso: true,
          insucessoQnt: 3,
          // Todos os 3 insucessos foram no Aeroporto.
          insucessoPorBairro: {'Aeroporto': 3},
        ),
      ]);

      // 24 pacotes para cada: é estimativa, e o card avisa disso.
      expect(_rateOf(ranking, 'Aeroporto').packages, 24);
      expect(_rateOf(ranking, 'Vila União').packages, 24);

      // O numerador respeita a distribuição informada, sem ratear.
      expect(_rateOf(ranking, 'Aeroporto').failures, 3);
      expect(_rateOf(ranking, 'Aeroporto').rate, 12.5);
      expect(_rateOf(ranking, 'Vila União').rate, 0);
    });

    test(
      'sem distribuição informada, o insucesso é rateado como no ranking',
      () {
        final ranking = failureRatePerBairro([
          _route(
            adress: ['Aeroporto', 'Vila União'],
            packages: 40,
            isInsucesso: true,
            insucessoQnt: 4,
          ),
        ]);

        // 2 insucessos e 20 pacotes de cada lado.
        expect(_rateOf(ranking, 'Aeroporto').rate, 10);
        expect(_rateOf(ranking, 'Vila União').rate, 10);
      },
    );

    test('bairro com pacotes e sem insucesso aparece zerado', () {
      final ranking = failureRatePerBairro([
        _route(adress: ['Centro'], packages: 30),
      ]);

      // Diferente de bairro sem pacotes: aqui o dado foi coletado.
      expect(_rateOf(ranking, 'Centro').rate, 0);
    });

    test('rota sem pacotes ou sem bairro fica fora', () {
      final ranking = failureRatePerBairro([
        _route(adress: ['Centro'], packages: null, isInsucesso: true),
        _route(adress: null, packages: 30, isInsucesso: true),
      ]);

      expect(ranking, isEmpty);
    });

    test('a soma dos insucessos rateados bate com o total da rota', () {
      final ranking = failureRatePerBairro([
        _route(
          adress: ['A', 'B', 'C'],
          packages: 30,
          isInsucesso: true,
          insucessoQnt: 5,
        ),
      ]);

      final total = ranking.fold<double>(0, (sum, r) => sum + r.failures);
      expect(total, closeTo(5, 0.0001));
    });
  });

  group('rankings por clima', () {
    test('o insucesso da rota é inteiro do clima dela, sem rateio', () {
      final ranking = failuresPerWeather([
        _route(weather: 'rain', isInsucesso: true, insucessoQnt: 3),
        _route(weather: 'rain', isInsucesso: true, insucessoQnt: 2),
        _route(weather: 'clear', isInsucesso: true, insucessoQnt: 1),
      ]);

      expect(_valueOf(ranking, 'Chuva'), 5);
      expect(_valueOf(ranking, 'Sol'), 1);
    });

    test('clima que rodou sem insucesso aparece zerado', () {
      final ranking = failuresPerWeather([
        _route(weather: 'rain', isInsucesso: true, insucessoQnt: 2),
        _route(weather: 'clear'),
      ]);

      // Diferente de bairro: "no sol não deu problema nenhum" é resposta.
      expect(_valueOf(ranking, 'Sol'), 0);
    });

    test('rota sem clima informado não entra', () {
      final ranking = failuresPerWeather([
        _route(isInsucesso: true, insucessoQnt: 5),
        _route(weather: '', isInsucesso: true, insucessoQnt: 5),
      ]);

      expect(ranking, isEmpty);
    });

    test('o rótulo é o nome em pt-BR, não o valor gravado', () {
      final ranking = failuresPerWeather([
        _route(weather: 'heavyRain', isInsucesso: true, insucessoQnt: 1),
      ]);

      expect(_has(ranking, 'Chuva forte'), isTrue);
      expect(_has(ranking, 'heavyRain'), isFalse);
    });

    test('climas de mesmo nome viram uma barra só', () {
      // `mist` e `fog` são os dois "Neblina": por enum virariam duas barras
      // com o mesmo rótulo no gráfico.
      final ranking = failuresPerWeather([
        _route(weather: 'mist', isInsucesso: true, insucessoQnt: 2),
        _route(weather: 'fog', isInsucesso: true, insucessoQnt: 3),
      ]);

      expect(ranking, hasLength(1));
      expect(_valueOf(ranking, 'Neblina'), 5);
    });

    test('índice é percentual sobre os pacotes daquele clima', () {
      final ranking = failureRatePerWeather([
        _route(
          weather: 'rain',
          packages: 100,
          isInsucesso: true,
          insucessoQnt: 8,
        ),
        _route(
          weather: 'clear',
          packages: 50,
          isInsucesso: true,
          insucessoQnt: 1,
        ),
      ]);

      expect(_rateOf(ranking, 'Chuva').rate, 8);
      expect(_rateOf(ranking, 'Sol').rate, 2);
      // Chuva pior que sol: é para isso que o índice existe.
      expect(ranking.first.label, 'Chuva');
    });

    test('clima sem pacotes informados fica fora do índice', () {
      final ranking = failureRatePerWeather([
        _route(
          weather: 'rain',
          packages: 20,
          isInsucesso: true,
          insucessoQnt: 1,
        ),
        _route(weather: 'clear', isInsucesso: true, insucessoQnt: 4),
      ]);

      // Sol não vira 0%: seria afirmar um dado que não foi coletado.
      expect(_hasRate(ranking, 'Sol'), isFalse);
      expect(ranking, hasLength(1));
    });

    test('lista vazia não divide por zero', () {
      expect(failuresPerWeather([]), isEmpty);
      expect(failureRatePerWeather([]), isEmpty);
    });
  });

  group('valuePerWeekday', () {
    test('devolve sempre os 7 dias, inclusive os zerados', () {
      // 10/08/2026 é uma segunda-feira.
      final series = valuePerWeekday([
        _route(startAt: DateTime(2026, 8, 10), value: 90),
      ]);

      expect(series, hasLength(7));
      expect(series.first, 90);
      expect(series.sublist(1), everyElement(0));
    });

    test('domingo cai na última posição', () {
      // 16/08/2026 é um domingo.
      final series = valuePerWeekday([
        _route(startAt: DateTime(2026, 8, 16), value: 40),
      ]);

      expect(series.last, 40);
    });

    test('soma as rotas do mesmo dia da semana', () {
      final series = valuePerWeekday([
        _route(startAt: DateTime(2026, 8, 10), value: 60),
        _route(startAt: DateTime(2026, 8, 17), value: 40),
      ]);

      expect(series.first, 100);
    });
  });

  group('faixa horária', () {
    test('os quatro turnos cobrem as 24 horas sem sobreposição', () {
      final covered = <int>[];
      for (final shift in Shift.values) {
        for (var hour = shift.startHour; hour <= shift.endHour; hour++) {
          covered.add(hour);
        }
      }

      expect(covered..sort(), List.generate(24, (i) => i));
    });

    test('agrupa pela hora de início da rota', () {
      final series = valuePerHour([
        _route(startAt: DateTime(2026, 8, 10, 8, 45), value: 70),
      ], Shift.manha);

      expect(series.firstWhere((point) => point.hour == 8).value, 70);
    });

    test('devolve todas as horas do turno, mesmo zeradas', () {
      final series = valuePerHour([], Shift.manha);

      expect(series.map((point) => point.hour), [5, 6, 7, 8, 9, 10, 11]);
      expect(series.map((point) => point.value), everyElement(0));
    });

    test('rota de outro turno não entra', () {
      final series = valuePerHour([
        _route(startAt: DateTime(2026, 8, 10, 4), value: 70),
      ], Shift.manha);

      expect(series.map((point) => point.value), everyElement(0));
    });
  });

  group('lista vazia', () {
    test('nenhuma agregação lança', () {
      expect(realizedInPeriod([], start: _start, end: _end), isEmpty);
      expect(valuePerCompany([]), isEmpty);
      expect(countPerCompany([]), isEmpty);
      expect(failuresPerCompany([]), isEmpty);
      expect(failureRatePerCompany([]), isEmpty);
      expect(routesPerBairro([]), isEmpty);
      expect(failuresPerBairro([]), isEmpty);
      expect(valuePerWeekday([]), everyElement(0));
    });
  });
}
