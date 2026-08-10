import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/screens/addIter.dart';

/// O formulário de rota, na parte que a Sem Rota acrescentou.
///
/// A tela não tinha teste nenhum, e é onde mora a armadilha mais cara da
/// feature: `value` guarda o **líquido**, e um formulário que reabrisse com ele
/// aplicaria o percentual de novo a cada edição — R$ 250 virando R$ 100 e
/// depois R$ 40, sem exceção, sem log e sem teste vermelho.
///
/// Nada aqui toca Firestore: o percentual entra por `ruleLoader`.

NewRouteModal _semRota({
  Company company = Company.mercadolivre,
  double grossValue = 250,
  int percent = 40,
}) {
  final payment = NoRoutePayment(
    grossValue: grossValue,
    percent: percent,
    appliedAt: '2026-06-15T10:00:00.000',
  );

  return NewRouteModal(
    id: 'r1',
    company: company,
    dateRoute: '15/06/2026',
    weekday: 1,
    status: StatusRoute.semRota,
    value: payment.paid,
    startAt: DateTime(2026, 6, 15, 8),
    noRoutePayment: payment,
    createdAt: '2026-06-15T08:00:00.000',
  );
}

/// Uma rota Concluída de verdade: com pacotes, paradas, bairro e insucesso.
///
/// Serve de ponto de partida para os testes de save porque a edição preenche a
/// hora de início — campo obrigatório que só a roleta do Cupertino escreve.
NewRouteModal _concluida() => NewRouteModal(
  id: 'r1',
  company: Company.mercadolivre,
  dateRoute: '15/06/2026',
  weekday: 1,
  status: StatusRoute.concluido,
  value: 250,
  packages: 120,
  stops: 45,
  adress: const ['Aldeota'],
  isInsucesso: true,
  insucessoQnt: 3,
  startAt: DateTime(2026, 6, 15, 8),
  createdAt: '2026-06-15T08:00:00.000',
);

Future<void> _pump(
  WidgetTester tester, {
  NewRouteModal? route,
  Future<int?> Function(Company)? ruleLoader,
  Future<void> Function(String, NewRouteModal)? saver,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AddIter(
        uid: 'u1',
        route: route,
        ruleLoader: ruleLoader ?? (_) async => 40,
        saver: saver,
      ),
      // O caminho de salvamento passa por `EasyLoading.show`, e o overlay dele
      // é instalado por este builder — como em `main.dart`.
      builder: EasyLoading.init(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Captura o que o formulário manda gravar, sem tocar no Firestore.
class _Gravacao {
  NewRouteModal? route;
  int chamadas = 0;

  Future<void> call(String uid, NewRouteModal saved) async {
    chamadas++;
    route = saved;
  }
}

Future<void> _tapSave(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Escolhe um status no dropdown pelo rótulo.
Future<void> _pickStatus(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<StatusRoute>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

String _line(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('no-route-line'))).data!;

String _valueField(WidgetTester tester) => tester
    .widget<TextFormField>(
      find.ancestor(
        of: find.text('Valor cheio'),
        matching: find.byType(TextFormField),
      ),
    )
    .controller!
    .text;

void main() {
  group('o menu de status', () {
    testWidgets('tem os cinco, e o rótulo vem de statusLabel', (tester) async {
      await _pump(tester);

      await tester.tap(find.byType(DropdownButtonFormField<StatusRoute>));
      await tester.pumpAndSettle();

      for (final label in [
        'Agendado',
        'Em rota',
        'Concluído',
        'Pago',
        'Sem Rota',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label sumiu do menu');
      }
    });

    testWidgets('o botão ganha o verbo do status escolhido', (tester) async {
      await _pump(tester);
      expect(find.text('Agendar Rota'), findsOneWidget);

      await _pickStatus(tester, 'Sem Rota');

      // "Desconhecido Rota" é o que apareceria com o `default` que existia no
      // switch sobre String.
      expect(find.text('Registrar Rota'), findsOneWidget);
      expect(find.textContaining('Desconhecido'), findsNothing);
    });
  });

  group('a linha do valor líquido', () {
    testWidgets('só existe na Sem Rota', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('no-route-line')), findsNothing);

      await _pickStatus(tester, 'Sem Rota');
      expect(find.byKey(const Key('no-route-line')), findsOneWidget);

      await _pickStatus(tester, 'Pago');
      expect(find.byKey(const Key('no-route-line')), findsNothing);
    });

    testWidgets('mostra a empresa, o percentual e o que entra no bolso', (
      tester,
    ) async {
      await _pump(tester, ruleLoader: (_) async => 40);

      await tester.enterText(find.byType(TextFormField).first, '25000');
      await _pickStatus(tester, 'Sem Rota');

      expect(_line(tester), 'Sem rota: a Mercado Livre paga 40% → R\$ 100,00');
    });

    testWidgets('acompanha a digitação em vez de ficar um caractere atrás', (
      tester,
    ) async {
      // Sem `onChanged` no campo, nada reconstrói a tela enquanto se digita: a
      // linha nasceria certa e mostraria R$ 25,00 para quem digitou 250.
      await _pump(tester, ruleLoader: (_) async => 40);
      await _pickStatus(tester, 'Sem Rota');

      await tester.enterText(find.byType(TextFormField).first, '25000');
      await tester.pump();
      expect(_line(tester), contains('R\$ 100,00'));

      await tester.enterText(find.byType(TextFormField).first, '50000');
      await tester.pump();
      expect(_line(tester), contains('R\$ 200,00'));
    });

    testWidgets('sem valor digitado, pede o valor em vez de mostrar zero', (
      tester,
    ) async {
      await _pump(tester);
      await _pickStatus(tester, 'Sem Rota');

      expect(_line(tester), contains('Informe o valor cheio'));
    });

    testWidgets('enquanto a busca está em voo, NÃO acusa falta de regra', (
      tester,
    ) async {
      // O caso mais provável dos quatro: numa conexão ruim a leitura demora
      // segundos, e a primeira leitura desta coleção num aparelho nunca vem do
      // cache. Cair na frase final aqui mandaria cadastrar no console uma regra
      // que existe e está chegando — em vermelho.
      final resposta = Completer<int?>();
      await _pump(tester, ruleLoader: (_) => resposta.future);

      await tester.enterText(find.byType(TextFormField).first, '25000');
      await _pickStatus(tester, 'Sem Rota');

      expect(_line(tester), 'Buscando a regra de pagamento…');
      expect(_line(tester), isNot(contains('cadastrada')));

      resposta.complete(40);
      await tester.pumpAndSettle();

      expect(_line(tester), contains('paga 40% → R\$ 100,00'));
    });

    testWidgets('durante a busca o save não grava nem libera', (tester) async {
      final resposta = Completer<int?>();
      final gravacao = _Gravacao();
      await _pump(
        tester,
        route: _concluida(),
        ruleLoader: (_) => resposta.future,
        saver: gravacao.call,
      );

      await _pickStatus(tester, 'Sem Rota');
      await _tapSave(tester, 'Salvar alterações');

      expect(gravacao.chamadas, 0);

      resposta.complete(40);
      await tester.pumpAndSettle();
    });

    testWidgets('empresa sem regra diz o que falta cadastrar', (tester) async {
      // A Shopee não tem documento em `norouterule`.
      await _pump(tester, ruleLoader: (_) async => null);
      await tester.enterText(find.byType(TextFormField).first, '25000');
      await _pickStatus(tester, 'Sem Rota');

      expect(_line(tester), contains('Sem regra de pagamento cadastrada'));
    });

    testWidgets('falha de leitura NÃO vira "sem regra cadastrada"', (
      tester,
    ) async {
      // A distinção que a feature inteira depende: um manda cadastrar no
      // console, o outro manda tentar de novo. Offline é o caso comum — a
      // primeira leitura desta coleção nunca vem do cache.
      await _pump(
        tester,
        ruleLoader: (_) async => throw Exception('sem rede'),
      );
      await tester.enterText(find.byType(TextFormField).first, '25000');
      await _pickStatus(tester, 'Sem Rota');

      expect(_line(tester), contains('Não foi possível ler a regra'));
      expect(_line(tester), isNot(contains('cadastrada')));
    });

    testWidgets('trocar de empresa rebusca a regra', (tester) async {
      // O seletor de empresa são três `GestureDetector` separados. Instrumentar
      // dois e esquecer um deixaria o percentual da empresa anterior na tela e
      // no documento gravado.
      await _pump(
        tester,
        ruleLoader: (company) async =>
            company == Company.amazon ? 100 : 40,
      );

      await tester.enterText(find.byType(TextFormField).first, '25000');
      await _pickStatus(tester, 'Sem Rota');
      expect(_line(tester), contains('Mercado Livre paga 40%'));

      await tester.tap(find.byType(Image).at(1)); // Amazon
      await tester.pumpAndSettle();

      expect(_line(tester), contains('Amazon paga 100%'));
      expect(_line(tester), contains('R\$ 250,00'));

      await tester.tap(find.byType(Image).at(2)); // Shopee
      await tester.pumpAndSettle();

      expect(_line(tester), contains('Shopee paga 40%'));
    });
  });

  group('editar uma ida já gravada', () {
    testWidgets('O TESTE DO PERCENTUAL APLICADO DUAS VEZES: reabre com o '
        'valor CHEIO', (tester) async {
      // `route.value` é R$ 100 (o líquido). Se o campo abrisse com ele, salvar
      // sem tocar em nada gravaria R$ 40 — e de novo R$ 16 na edição seguinte.
      await _pump(tester, route: _semRota());

      expect(_valueField(tester), 'R\$ 250,00');
    });

    testWidgets('a linha usa o percentual CONGELADO, não o de hoje', (
      tester,
    ) async {
      // O pilar do app. A regra global virou 30 desde junho; a ida de junho
      // continua valendo 40%.
      await _pump(tester, route: _semRota(), ruleLoader: (_) async => 30);

      expect(_line(tester), 'Sem rota: a Mercado Livre paga 40% → R\$ 100,00');
    });

    testWidgets('editar funciona mesmo com a leitura da regra falhando', (
      tester,
    ) async {
      // O bloco congelado já responde qual percentual vale, então corrigir uma
      // rota antiga offline não pode ficar impossível.
      await _pump(
        tester,
        route: _semRota(),
        ruleLoader: (_) async => throw Exception('sem rede'),
      );

      expect(_line(tester), contains('paga 40%'));
      expect(_line(tester), contains('R\$ 100,00'));
    });

    testWidgets('trocar de empresa larga o percentual congelado', (
      tester,
    ) async {
      // O percentual do Mercado Livre não descreve uma ida da Amazon.
      await _pump(
        tester,
        route: _semRota(),
        ruleLoader: (company) async =>
            company == Company.amazon ? 100 : 40,
      );

      await tester.tap(find.byType(Image).at(1)); // Amazon
      await tester.pumpAndSettle();

      expect(_line(tester), contains('Amazon paga 100%'));
      expect(_line(tester), contains('R\$ 250,00'));
    });

    testWidgets('salvar sem tocar em nada NÃO reaplica o percentual', (
      tester,
    ) async {
      // O ciclo completo da armadilha: reabrir uma ida de R$ 250 (gravada como
      // R$ 100) e salvar. Se o campo tivesse reaberto com o líquido, ou se o
      // save gravasse `gross` em vez de `payment.paid`, isto daria R$ 40.
      final gravacao = _Gravacao();
      await _pump(
        tester,
        route: _semRota(),
        ruleLoader: (_) async => 40,
        saver: gravacao.call,
      );

      await _tapSave(tester, 'Salvar alterações');

      expect(gravacao.chamadas, 1);
      expect(gravacao.route!.value, 100.0);
      expect(gravacao.route!.noRoutePayment!.grossValue, 250.0);
      expect(gravacao.route!.noRoutePayment!.percent, 40);
      // A invariante, em igualdade exata.
      expect(gravacao.route!.value, gravacao.route!.noRoutePayment!.paid);
    });

    testWidgets('salvar duas vezes seguidas não compõe o desconto', (
      tester,
    ) async {
      // O defeito era composto: cada edição aplicava de novo. Salvar, reabrir o
      // que foi gravado e salvar outra vez tem de dar o mesmo número.
      final primeira = _Gravacao();
      await _pump(
        tester,
        route: _semRota(),
        ruleLoader: (_) async => 40,
        saver: primeira.call,
      );
      await _tapSave(tester, 'Salvar alterações');

      final segunda = _Gravacao();
      await _pump(
        tester,
        route: primeira.route,
        ruleLoader: (_) async => 40,
        saver: segunda.call,
      );
      await _tapSave(tester, 'Salvar alterações');

      expect(segunda.route!.value, 100.0);
      expect(segunda.route!.noRoutePayment!.grossValue, 250.0);
    });

    testWidgets('o percentual congelado é o que vai para o banco', (
      tester,
    ) async {
      // A regra global virou 30; a ida de junho continua gravando 40%.
      final gravacao = _Gravacao();
      await _pump(
        tester,
        route: _semRota(),
        ruleLoader: (_) async => 30,
        saver: gravacao.call,
      );

      await _tapSave(tester, 'Salvar alterações');

      expect(gravacao.route!.noRoutePayment!.percent, 40);
      expect(gravacao.route!.value, 100.0);
      expect(
        gravacao.route!.noRoutePayment!.appliedAt,
        '2026-06-15T10:00:00.000',
      );
    });

    testWidgets('trocar de Sem Rota para Pago larga o bloco e o valor cheio', (
      tester,
    ) async {
      // Sem isto, uma rota `pago` ficaria com `value` líquido e um bloco vivo —
      // e reabrir mostraria o valor cheio num status que não aplica percentual.
      final gravacao = _Gravacao();
      await _pump(tester, route: _semRota(), saver: gravacao.call);

      await _pickStatus(tester, 'Pago');
      await _tapSave(tester, 'Salvar alterações');

      expect(gravacao.route!.noRoutePayment, isNull);
      // O campo mostra R$ 250,00 e é isso que a rota paga passa a valer.
      expect(gravacao.route!.value, 250.0);
    });
  });

  group('o que o save recusa', () {
    testWidgets('empresa sem regra não grava nada', (tester) async {
      final gravacao = _Gravacao();
      await _pump(
        tester,
        route: _concluida(),
        ruleLoader: (_) async => null,
        saver: gravacao.call,
      );

      await _pickStatus(tester, 'Sem Rota');
      await _tapSave(tester, 'Salvar alterações');

      expect(gravacao.chamadas, 0);
    });

    testWidgets('falha de leitura também não grava', (tester) async {
      final gravacao = _Gravacao();
      await _pump(
        tester,
        route: _concluida(),
        ruleLoader: (_) async => throw Exception('sem rede'),
        saver: gravacao.call,
      );

      await _pickStatus(tester, 'Sem Rota');
      await _tapSave(tester, 'Salvar alterações');

      expect(gravacao.chamadas, 0);
    });

    testWidgets('a rota normal continua salvando normalmente', (tester) async {
      // O contrapeso dos dois acima: os guardas novos só valem na Sem Rota.
      final gravacao = _Gravacao();
      await _pump(
        tester,
        route: _concluida(),
        ruleLoader: (_) async => null,
        saver: gravacao.call,
      );

      await _tapSave(tester, 'Salvar alterações');

      expect(gravacao.chamadas, 1);
      expect(gravacao.route!.value, 250.0);
      expect(gravacao.route!.packages, 120);
    });
  });

  group('campos que não existem numa ida sem rota', () {
    testWidgets('pacotes, paradas, bairros e insucesso não são gravados', (
      tester,
    ) async {
      // Reabrir uma rota Concluída com 120 pacotes e trocar para Sem Rota:
      // `_fillFromRoute` deixou os controllers cheios, e sem a guarda o card
      // passaria a exibir "Pacotes: 120" embaixo do chip "Sem Rota".
      final gravacao = _Gravacao();
      await _pump(
        tester,
        route: _concluida(),
        ruleLoader: (_) async => 40,
        saver: gravacao.call,
      );

      await _pickStatus(tester, 'Sem Rota');
      await _tapSave(tester, 'Salvar alterações');

      final salva = gravacao.route!;
      expect(salva.status, StatusRoute.semRota);
      expect(salva.value, 100.0);
      expect(salva.packages, isNull);
      expect(salva.stops, isNull);
      expect(salva.adress, isEmpty);
      expect(salva.isInsucesso, isFalse);
      expect(salva.insucessoQnt, isNull);
      expect(salva.insucessoPorBairro, isEmpty);
    });
  });

  group('reabrir', () {
    testWidgets('rota normal reabre com o próprio valor', (tester) async {
      final paga = NewRouteModal(
        id: 'r1',
        company: Company.amazon,
        dateRoute: '15/06/2026',
        weekday: 1,
        status: StatusRoute.pago,
        value: 250,
        startAt: DateTime(2026, 6, 15, 8),
        createdAt: '2026-06-15T08:00:00.000',
      );

      await _pump(tester, route: paga);

      // O campo se chama "Valor" fora da Sem Rota.
      expect(find.text('Valor'), findsOneWidget);
      expect(find.byKey(const Key('no-route-line')), findsNothing);
    });
  });
}
