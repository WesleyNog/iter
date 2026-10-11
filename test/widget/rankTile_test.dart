import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/ranking.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/rankTile.dart';

RankRow _row({
  String uid = 'wesley',
  double? value = 5.7,
  int routes = 17,
  int sampleRoutes = 12,
  int? sampleUnits = 506,
  bool ranked = true,
}) {
  return RankRow(
    uid: uid,
    value: value,
    routes: routes,
    sampleRoutes: sampleRoutes,
    sampleUnits: sampleUnits,
    ranked: ranked,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  RankRow? row,
  RankCriterion criterion = RankCriterion.ritmo,
  int? position = 1,
  bool isMe = false,
  String name = 'Wesley Nogueira',
  double width = 360,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: RankTile(
              row: row ?? _row(),
              criterion: criterion,
              profile: PublicProfile(
                uid: 'wesley',
                name: name,
                nickName: 'wesley-efmg',
                updatedAt: '2026-08-24T10:00:00.000',
              ),
              position: position,
              isMe: isMe,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('o número do critério, com a amostra que o formou', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('5,7 min/parada'), findsOneWidget);
    expect(find.text('506 paradas · 12 rotas'), findsOneWidget);
    expect(find.text('Wesley Nogueira'), findsOneWidget);
  });

  testWidgets('a amostra é a do critério, não as rotas do mês', (tester) async {
    // O defeito literal que `RankRow.sampleRoutes` existe para consertar: 40
    // rotas no mês, uma cronometrada, e a linha anunciando "40 rotas" embaixo
    // de um número tirado de uma. Trocar `sampleRoutes` por `routes` no widget
    // deixa este teste vermelho — antes desta extração, deixava a suíte
    // inteira verde, porque a linha morava num `State` privado que abre o
    // Firestore e nenhum teste alcançava.
    await _pump(
      tester,
      row: _row(routes: 40, sampleRoutes: 12, sampleUnits: 506),
    );

    expect(find.text('506 paradas · 12 rotas'), findsOneWidget);
    expect(find.textContaining('40 rotas'), findsNothing);
  });

  testWidgets('sem amostra, cai nas rotas do mês em vez de dois zeros', (
    tester,
  ) async {
    await _pump(
      tester,
      row: _row(value: null, routes: 17, sampleRoutes: 0, sampleUnits: 0),
      position: null,
    );

    expect(find.text('—'), findsNWidgets(2)); // a posição e o valor
    expect(find.text('17 rotas'), findsOneWidget);
    expect(find.textContaining('0 paradas'), findsNothing);
  });

  testWidgets('cada critério formata o próprio número', (tester) async {
    await _pump(
      tester,
      criterion: RankCriterion.rotas,
      row: _row(value: 17, sampleUnits: null),
    );
    expect(find.text('17'), findsOneWidget);

    await _pump(
      tester,
      criterion: RankCriterion.insucesso,
      row: _row(value: 1.44, sampleUnits: 573),
    );
    // Vírgula decimal, como o resto do app.
    expect(find.text('1,4%'), findsOneWidget);
    expect(find.text('573 pacotes · 12 rotas'), findsOneWidget);
  });

  testWidgets('o número nunca é espremido pelo nome', (tester) async {
    // A **causa**, não o sintoma: o valor é o filho sem `flex` da `Row`, então
    // ele se serve de largura antes do nome. Um nome absurdo tem de encolher o
    // nome, nunca o número — o inverso é o que acontecia quando a amostra
    // ficava empilhada à direita, e aí quem encolhia era o nome de todo mundo.
    const nomeEnorme = 'Maria Eduarda Rodrigues do Nascimento Albuquerque';

    await _pump(tester, name: nomeEnorme, width: 320);
    await tester.pumpAndSettle();

    final numero = tester.getSize(find.text('5,7 min/parada'));
    final nome = tester.getSize(find.text(nomeEnorme));

    // O número desenha inteiro (uma linha, largura própria)... O limite é
    // "menos de duas linhas" do número, que é 17 px: uma só, na fonte do
    // teste, já mede 24.
    expect(numero.width, greaterThan(0));
    expect(numero.height, lessThan(2 * 17));
    // ...e é o nome que cede, com reticências em vez de quebrar linha.
    expect(nome.height, lessThan(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a medalha só vai até o terceiro lugar', (tester) async {
    for (final lugar in [1, 2, 3]) {
      await _pump(tester, position: lugar);
      expect(find.byType(Image), findsOneWidget, reason: 'lugar $lugar');
    }

    await _pump(tester, position: 4);
    expect(find.byType(Image), findsNothing);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('a própria linha se identifica sem precisar ler o nome', (
    tester,
  ) async {
    await _pump(tester, isMe: true);

    expect(find.text('Wesley Nogueira (você)'), findsOneWidget);
    // Gradiente, não só cor: o `blue.shade50` de antes sumia numa lista de
    // vinte.
    expect(_fundo(tester).gradient, isNotNull);

    await _pump(tester, isMe: false);
    expect(_fundo(tester).gradient, isNull);
  });

  testWidgets('número grande e unidade pequena, do mesmo formatPace', (
    tester,
  ) async {
    await _pump(tester);

    // Continua um texto só para quem procura por ele...
    expect(find.text('5,7 min/parada'), findsOneWidget);

    // ...em duas partes cortadas do mesmo texto, e não numa segunda
    // formatação do ritmo.
    final partes = _partes(tester, '5,7 min/parada');
    expect(partes.map((p) => p.text), ['5,7', ' min/parada']);
    expect(partes[0].style!.fontSize!, greaterThan(partes[1].style!.fontSize!));
  });

  testWidgets('o número do rodapé perde a força do número da disputa', (
    tester,
  ) async {
    await _pump(tester, position: 1);
    final disputa = _partes(tester, '5,7 min/parada').first.style!;

    await _pump(tester, position: null, row: _row(ranked: false));
    final rodape = _partes(tester, '5,7 min/parada').first.style!;

    // Em negrito, o 4,6 do rodapé era o número mais forte da tela e parecia
    // estar ganhando do primeiro lugar.
    expect(rodape.fontWeight, isNot(disputa.fontWeight));
    expect(rodape.color, isNot(disputa.color));
  });

  testWidgets('a própria linha no rodapé continua legível', (tester) async {
    await _pump(tester, position: null, isMe: true, row: _row(ranked: false));

    // O cinza do rodapé sobre o gradiente azul seria o número sumindo
    // justamente na linha de quem está olhando.
    final cor = _partes(tester, '5,7 min/parada').first.style!.color!;
    expect((cor.r, cor.g, cor.b), (1.0, 1.0, 1.0));
    expect(cor.a, greaterThan(0.6));
  });

  for (final escala in [1.0, 1.3, 1.6]) {
    testWidgets('cabe na altura que ela mesma mede, com fonte $escala×', (
      tester,
    ) async {
      // O `RankingBoard` posiciona cada linha com esta altura. Se a medida
      // errar para menos, a linha estoura — e é a fonte grande do sistema que
      // revela isso.
      //
      // 600 px de largura de propósito: o assunto aqui é a **altura**. A fonte
      // do teste tem todo glifo de 1 em de largura, e a 1,6× ela estoura na
      // horizontal uma linha que no aparelho cabe — o teste mediria a fonte
      // errada e ficaria vermelho pelo motivo errado.
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(600, 800),
              textScaler: TextScaler.linear(escala),
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => SizedBox(
                  width: 600,
                  height: RankTile.heightFor(context),
                  child: RankTile(
                    row: _row(),
                    criterion: RankCriterion.ritmo,
                    profile: null,
                    position: 1,
                    isMe: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }
}

/// O fundo da linha: o `Container` mais próximo acima do `Row`.
BoxDecoration _fundo(WidgetTester tester) {
  final fundo = tester.widget<Container>(
    find.ancestor(of: find.byType(Row), matching: find.byType(Container)).first,
  );
  return fundo.decoration! as BoxDecoration;
}

/// As partes do `Text.rich` do número.
List<TextSpan> _partes(WidgetTester tester, String texto) {
  final widget = tester.widget<Text>(find.text(texto));
  return (widget.textSpan! as TextSpan).children!.cast<TextSpan>();
}
