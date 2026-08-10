import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/noRouteRule.dart';
import 'package:iter/model/newRouteModal.dart';

/// A regra de pagamento da rota que acabou antes de começar.
///
/// **Dinheiro é comparado com igualdade exata aqui, nunca `closeTo`.** Não é
/// preciosismo: `toStringAsFixed(2)` esconde um `double` sujo na tela, no card e
/// no gráfico, então a verificação no aparelho não consegue detectar a falta do
/// arredondamento — só este arquivo consegue. Um `closeTo(99.96, 0.001)`
/// passaria com `99.96000000000001` e não testaria nada.
void main() {
  group('readPercent — o que conta como regra cadastrada', () {
    test('inteiro dentro da faixa passa', () {
      expect(readPercent({'percent': 40}), 40);
      expect(readPercent({'percent': 100}), 100);
      expect(readPercent({'percent': 1}), 1);
    });

    test('double redondo passa: é o que o Firestore devolve', () {
      // `40.0 == 40` é verdadeiro em Dart, então o documento gravado como
      // número decimal continua valendo.
      expect(readPercent({'percent': 40.0}), 40);
    });

    test('documento inexistente é ausência de regra, não erro', () {
      expect(readPercent(null), isNull);
    });

    test('campo ausente ou de outro tipo não vira número', () {
      expect(readPercent({}), isNull);
      expect(readPercent({'percent': '40'}), isNull);
      expect(readPercent({'percent': true}), isNull);
      expect(readPercent({'outro': 40}), isNull);
    });

    test('zero é recusado: é indistinguível de documento quebrado', () {
      // E aceitá-lo zeraria o valor da rota, o que apaga a provisão junto —
      // `provisionFor` desiste em `value <= 0` e a gasolina de uma ida que
      // aconteceu de verdade sumiria do custo.
      expect(readPercent({'percent': 0}), isNull);
      expect(readPercent({'percent': -40}), isNull);
    });

    test('acima de 100 é recusado: pega o 400 digitado no lugar de 40', () {
      expect(readPercent({'percent': 101}), isNull);
      expect(readPercent({'percent': 400}), isNull);
    });

    test('percentual com casa decimal é recusado, não truncado', () {
      // Truncar gravaria 42% congelado em toda rota sem ninguém ter conferido.
      expect(readPercent({'percent': 42.5}), isNull);
    });
  });

  group('a conta, em centavos', () {
    test('âncora: 40% de R\$ 250,00 são R\$ 100,00', () {
      expect(NoRoutePayment.paidValue(250, 40), 100.0);
    });

    test('âncora: 40% de R\$ 249,90 são R\$ 99,96 — exatos', () {
      // Este é o caso que passa **por sorte** sem arredondamento nenhum:
      // `249.9 * 40 / 100` dá 99,96 exato, enquanto `249.9 * (40/100)` dá
      // 99.96000000000001. Ele fica aqui como âncora histórica; quem prova o
      // arredondamento são os dois testes seguintes.
      expect(NoRoutePayment.paidValue(249.90, 40), 99.96);
    });

    test('o caso que a ordem das operações não salva', () {
      // `1234.56 * 40 / 100` dá 493.82399999999996 em IEEE754. Sem arredondar,
      // este teste é vermelho.
      expect(NoRoutePayment.paidValue(1234.56, 40), 493.82);
    });

    test('meio centavo vai para cima, e não para onde o float mandar', () {
      // 87,45 × 30% = 26,235 — exatamente no meio. Com `(x*100).round()/100` a
      // direção passaria a ser decidida por ruído de float; com inteiros, é
      // regra.
      expect(NoRoutePayment.paidValue(87.45, 30), 26.24);
      // 249,90 × 35% = 87,465.
      expect(NoRoutePayment.paidValue(249.90, 35), 87.47);
    });

    test('100% devolve o valor cheio', () {
      expect(NoRoutePayment.paidValue(250, 100), 250.0);
      expect(NoRoutePayment.paidValue(187.33, 100), 187.33);
    });

    test('valor ou percentual não positivo não vira número negativo', () {
      expect(NoRoutePayment.paidValue(0, 40), 0);
      expect(NoRoutePayment.paidValue(-250, 40), 0);
      expect(NoRoutePayment.paidValue(250, 0), 0);
    });

    test('o piso: uma rota de centavos pode arredondar para zero', () {
      // Registrado em vez de escondido. R$ 0,01 a 40% são 0,4 centavo, e o
      // resultado é R$ 0,00 — que faria a rota perder a provisão. O formulário
      // é quem recusa valor que não seja positivo; aqui a conta só não mente.
      expect(NoRoutePayment.paidValue(0.01, 40), 0);
    });

    test('o getter e a função estática dão o mesmo número', () {
      // A invariante `route.value == payment.paid` é igualdade exata de
      // `double`: ela só se sustenta porque os dois lados passam por aqui.
      const payment = NoRoutePayment(
        grossValue: 1234.56,
        percent: 40,
        appliedAt: '2026-08-10T10:00:00.000',
      );

      expect(payment.paid, NoRoutePayment.paidValue(1234.56, 40));
      expect(payment.paid, 493.82);
    });
  });

  group('travessia', () {
    test('ida e volta preserva os três campos', () {
      const original = NoRoutePayment(
        grossValue: 249.90,
        percent: 40,
        appliedAt: '2026-08-10T10:00:00.000',
      );

      final volta = NoRoutePayment.fromMap(original.toMap());

      expect(volta.grossValue, 249.90);
      expect(volta.percent, 40);
      expect(volta.appliedAt, '2026-08-10T10:00:00.000');
      expect(volta.paid, 99.96);
    });

    test('número redondo volta do Firestore como int e não lança', () {
      // O Firestore devolve `int` quando o valor gravado não tem casa decimal.
      // Um cast cru aqui derrubaria a leitura, e o `try/catch` por documento de
      // `RouteController._parseAll` faria a rota **sumir da lista sem log**.
      final volta = NoRoutePayment.fromMap({
        'grossValue': 250,
        'percent': 40,
        'appliedAt': '2026-08-10T10:00:00.000',
      });

      expect(volta.grossValue, 250.0);
      expect(volta.paid, 100.0);
    });

    test('documento corrompido não lança', () {
      final volta = NoRoutePayment.fromMap({});

      expect(volta.grossValue, 0);
      expect(volta.percent, 0);
      expect(volta.appliedAt, '');
      expect(volta.paid, 0);
    });
  });

  group('resolveNoRoutePayment — o que congela e o que recalcula', () {
    const junho = NoRoutePayment(
      grossValue: 250,
      percent: 40,
      appliedAt: '2026-06-15T10:00:00.000',
    );

    final hoje = DateTime(2026, 8, 10, 20);

    NoRoutePayment? resolve({
      StatusRoute status = StatusRoute.semRota,
      Company company = Company.mercadolivre,
      double grossValue = 250,
      NoRoutePayment? existing,
      Company? existingCompany,
      int? currentPercent = 40,
    }) => resolveNoRoutePayment(
      status: status,
      company: company,
      grossValue: grossValue,
      existing: existing,
      existingCompany: existingCompany,
      currentPercent: currentPercent,
      now: hoje,
    );

    test('rota que não é Sem Rota não tem pagamento', () {
      for (final status in StatusRoute.values) {
        if (status == StatusRoute.semRota) continue;

        expect(
          resolve(status: status, existing: junho, existingCompany: Company.mercadolivre),
          isNull,
          reason: 'status $status não pode carregar bloco de Sem Rota',
        );
      }
    });

    test('sem bloco anterior, aplica a regra de hoje', () {
      final payment = resolve(currentPercent: 40)!;

      expect(payment.percent, 40);
      expect(payment.grossValue, 250);
      expect(payment.paid, 100);
      expect(payment.appliedAt, hoje.toIso8601String());
    });

    test('MESMA empresa: o percentual congelado manda, e o carimbo também', () {
      // O pilar. A regra global virou 30 desde junho; corrigir o valor daquela
      // ida não pode restampá-la com o percentual de hoje.
      final payment = resolve(
        existing: junho,
        existingCompany: Company.mercadolivre,
        currentPercent: 30,
        grossValue: 300,
      )!;

      expect(payment.percent, 40);
      expect(payment.grossValue, 300);
      expect(payment.paid, 120);
      // Manter o percentual e trocar o carimbo faria a rota dizer que foi
      // recalculada hoje, que é justamente o que não aconteceu.
      expect(payment.appliedAt, '2026-06-15T10:00:00.000');
    });

    test('editar sem tocar em nada devolve exatamente o que estava', () {
      final payment = resolve(
        existing: junho,
        existingCompany: Company.mercadolivre,
        currentPercent: 30,
      )!;

      expect(payment.percent, 40);
      expect(payment.grossValue, 250);
      expect(payment.paid, 100);
    });

    test('empresa mudou: o percentual antigo não descreve mais nada', () {
      final payment = resolve(
        company: Company.amazon,
        existing: junho,
        existingCompany: Company.mercadolivre,
        currentPercent: 100,
      )!;

      expect(payment.percent, 100);
      expect(payment.paid, 250);
      expect(payment.appliedAt, hoje.toIso8601String());
    });

    test('editar uma ida antiga funciona sem a regra carregada', () {
      // `_fillFromRoute` roda no `initState` e não busca nada, então corrigir
      // uma rota de junho chega ao formulário sem percentual em mãos — e
      // offline nunca terá. O bloco congelado já responde a pergunta.
      final payment = resolve(
        existing: junho,
        existingCompany: Company.mercadolivre,
        currentPercent: null,
      )!;

      expect(payment.percent, 40);
      expect(payment.paid, 100);
    });

    test('sem percentual em lugar nenhum, não há pagamento', () {
      expect(resolve(currentPercent: null), isNull);
    });

    test('empresa nova sem regra recusa, mesmo com bloco antigo', () {
      // Trocar uma ida do Mercado Livre para a Shopee, que não tem documento.
      expect(
        resolve(
          company: Company.shopee,
          existing: junho,
          existingCompany: Company.mercadolivre,
          currentPercent: null,
        ),
        isNull,
      );
    });

    test('valor cheio não positivo não vira pagamento', () {
      expect(resolve(grossValue: 0), isNull);
      expect(resolve(grossValue: -10), isNull);
    });

    test('bloco corrompido cai na regra de hoje em vez de travar a rota', () {
      // Recusar aqui deixaria o dono sem como corrigir o próprio documento.
      const quebrado = NoRoutePayment(
        grossValue: 250,
        percent: 0,
        appliedAt: '2026-06-15T10:00:00.000',
      );

      final payment = resolve(
        existing: quebrado,
        existingCompany: Company.mercadolivre,
        currentPercent: 40,
      )!;

      expect(payment.percent, 40);
      expect(payment.appliedAt, hoje.toIso8601String());
    });
  });

  group('a invariante que liga o bloco ao campo value', () {
    test('value gravado é exatamente payment.paid', () {
      // É a conferência que o card e o Firestore não conseguem fazer:
      // `toStringAsFixed(2)` mostraria "R$ 493,82" para os dois lados mesmo se
      // um deles carregasse lixo de float.
      final payment = resolveNoRoutePayment(
        status: StatusRoute.semRota,
        company: Company.mercadolivre,
        grossValue: 1234.56,
        existing: null,
        existingCompany: null,
        currentPercent: 40,
        now: DateTime(2026, 8, 10),
      )!;

      final route = NewRouteModal(
        id: 'r1',
        company: Company.mercadolivre,
        dateRoute: '10/08/2026',
        weekday: 1,
        status: StatusRoute.semRota,
        value: payment.paid,
        startAt: DateTime(2026, 8, 10, 8),
        noRoutePayment: payment,
        createdAt: '2026-08-10T08:00:00.000',
      );

      expect(route.value, route.noRoutePayment!.paid);
      expect(route.value, 493.82);
    });

    test('withProvision não apaga o bloco congelado', () {
      // `withProvision` reconstrói a rota campo a campo com parâmetros
      // opcionais, e `addIter` o chama em **todo** save. Omitir o campo lá não
      // gera erro de compilação: o estrago só apareceria na edição seguinte,
      // aplicando o percentual sobre um valor já descontado.
      const payment = NoRoutePayment(
        grossValue: 250,
        percent: 40,
        appliedAt: '2026-08-10T10:00:00.000',
      );

      final route = NewRouteModal(
        id: 'r1',
        company: Company.mercadolivre,
        dateRoute: '10/08/2026',
        weekday: 1,
        status: StatusRoute.semRota,
        value: 100,
        startAt: DateTime(2026, 8, 10, 8),
        noRoutePayment: payment,
        createdAt: '2026-08-10T08:00:00.000',
      );

      final salva = route.withProvision(null);

      expect(salva.noRoutePayment, isNotNull);
      expect(salva.noRoutePayment!.grossValue, 250);
      expect(salva.noRoutePayment!.percent, 40);
    });

    test('o documento leva o bloco para o Firestore e o traz de volta', () {
      final route = NewRouteModal(
        id: 'r1',
        company: Company.amazon,
        dateRoute: '10/08/2026',
        weekday: 1,
        status: StatusRoute.semRota,
        value: 250,
        startAt: DateTime(2026, 8, 10, 8),
        noRoutePayment: const NoRoutePayment(
          grossValue: 250,
          percent: 100,
          appliedAt: '2026-08-10T10:00:00.000',
        ),
        createdAt: '2026-08-10T08:00:00.000',
      );

      final map = route.toMap();
      expect(map['status'], 'semRota');

      final volta = NewRouteModal.fromMap(map);

      expect(volta.status, StatusRoute.semRota);
      expect(volta.noRoutePayment!.percent, 100);
      expect(volta.noRoutePayment!.grossValue, 250);
      expect(volta.value, volta.noRoutePayment!.paid);
    });

    test('rota normal não carrega bloco nenhum', () {
      final route = NewRouteModal(
        id: 'r1',
        company: Company.amazon,
        dateRoute: '10/08/2026',
        weekday: 1,
        status: StatusRoute.pago,
        value: 250,
        startAt: DateTime(2026, 8, 10, 8),
        createdAt: '2026-08-10T08:00:00.000',
      );

      expect(NewRouteModal.fromMap(route.toMap()).noRoutePayment, isNull);
    });

    test('rota gravada antes deste campo continua legível', () {
      final map = NewRouteModal(
        id: 'r1',
        company: Company.amazon,
        dateRoute: '10/08/2026',
        weekday: 1,
        status: StatusRoute.pago,
        value: 250,
        startAt: DateTime(2026, 8, 10, 8),
        createdAt: '2026-08-10T08:00:00.000',
      ).toMap()..remove('noRoutePayment');

      expect(NewRouteModal.fromMap(map).noRoutePayment, isNull);
    });
  });

  group('hasRun — rodou não é o mesmo que foi uma rota', () {
    NewRouteModal routeWith(StatusRoute status) => NewRouteModal(
      id: 'r1',
      company: Company.mercadolivre,
      dateRoute: '10/08/2026',
      weekday: 1,
      status: status,
      value: 100,
      startAt: DateTime(2026, 8, 10, 8),
      createdAt: '2026-08-10T08:00:00.000',
    );

    test('a ida ao CD rodou: queimou gasolina', () {
      expect(routeWith(StatusRoute.semRota).hasRun, isTrue);
      expect(routeWith(StatusRoute.concluido).hasRun, isTrue);
      expect(routeWith(StatusRoute.pago).hasRun, isTrue);
    });

    test('o que ainda não saiu não rodou', () {
      expect(routeWith(StatusRoute.agendado).hasRun, isFalse);
      expect(routeWith(StatusRoute.andamento).hasRun, isFalse);
    });
  });
}
