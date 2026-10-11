import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/monthStats.dart';
import 'package:iter/Utils/ranking.dart';
import 'package:iter/widget/rankTile.dart';
import 'package:iter/widget/rankingBoard.dart';

/// Um mês com cinco participantes em que as três disputas dão ordens
/// diferentes: em Rotas todos disputam, em Ritmo dois vão para o rodapé.
const _outubro = {
  'carla': MonthStats(
    routes: 9,
    pacedRoutes: 9,
    pacedStops: 401,
    pacedMinutes: 2566, // 6,4 min/parada
    packagedRoutes: 9,
    packages: 1890,
    failures: 26,
  ),
  'diego': MonthStats(
    routes: 7,
    pacedRoutes: 7,
    pacedStops: 310,
    pacedMinutes: 1829, // 5,9
    packagedRoutes: 7,
    packages: 1420,
    failures: 13,
  ),
  'wesley': MonthStats(
    routes: 5,
    pacedRoutes: 5,
    pacedStops: 146,
    pacedMinutes: 759, // 5,2
    packagedRoutes: 5,
    packages: 760,
    failures: 16,
  ),
  'jonas': MonthStats(
    routes: 3,
    pacedRoutes: 3,
    pacedStops: 73,
    pacedMinutes: 336, // 4,6 — melhor que todos, e sem amostra
    packagedRoutes: 3,
    packages: 390,
  ),
  'patricia': MonthStats(),
};

Future<void> _pump(
  WidgetTester tester, {
  RankCriterion criterion = RankCriterion.rotas,
  Map<String, MonthStats>? buckets = _outubro,
  bool loading = false,
  bool failed = false,
  bool hasFriends = true,
  bool semAnimacao = false,
  double escala = 1,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  VoidCallback? onRetry,
  ValueChanged<RankCriterion>? onCriterion,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: semAnimacao,
            textScaler: TextScaler.linear(escala),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RankingBoard(
                month: DateTime(2026, 10),
                criterion: criterion,
                onCriterion: onCriterion ?? (_) {},
                onPrevious: onPrevious,
                onNext: onNext,
                rows: buckets == null ? null : rankBy(criterion, buckets),
                profiles: const {},
                me: 'wesley',
                hasFriends: hasFriends,
                loading: loading,
                failed: failed,
                onRetry: onRetry,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

double _y(WidgetTester tester, String uid) =>
    tester.getTopLeft(find.byKey(ValueKey('rank-$uid'))).dy;

/// Os uids na ordem em que aparecem de cima para baixo.
List<String> _ordemNaTela(WidgetTester tester) {
  final uids = _outubro.keys.toList()
    ..sort((a, b) => _y(tester, a).compareTo(_y(tester, b)));
  return uids;
}

void main() {
  testWidgets('a ordem de cima para baixo é a de rankBy', (tester) async {
    for (final criterio in RankCriterion.values) {
      await _pump(tester, criterion: criterio);
      await tester.pumpAndSettle();

      // Comparado com `rankBy`, e não com uma lista escrita aqui: o teste não
      // reimplementa a regra que o card só desenha.
      expect(
        _ordemNaTela(tester),
        rankBy(criterio, _outubro).map((r) => r.uid).toList(),
        reason: criterio.name,
      );
    }
  });

  testWidgets('trocar de critério anima o lugar e não o número', (
    tester,
  ) async {
    await _pump(tester, criterion: RankCriterion.rotas);
    await tester.pumpAndSettle();
    final emRotas = _y(tester, 'wesley'); // 3º

    await _pump(tester, criterion: RankCriterion.ritmo);
    await tester.pump(const Duration(milliseconds: 100));

    // O número já é o novo no primeiro quadro...
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('rank-wesley')),
        matching: find.text('5,2 min/parada'),
      ),
      findsOneWidget,
    );

    // ...enquanto a linha ainda está no caminho do 3º para o 1º lugar.
    final noCaminho = _y(tester, 'wesley');
    await tester.pumpAndSettle();
    final emRitmo = _y(tester, 'wesley');

    expect(emRitmo, lessThan(emRotas));
    expect(noCaminho, lessThan(emRotas));
    expect(noCaminho, greaterThan(emRitmo));
  });

  testWidgets('quem pediu menos movimento recebe a lista já no lugar', (
    tester,
  ) async {
    await _pump(tester, semAnimacao: true);
    await _pump(tester, criterion: RankCriterion.ritmo, semAnimacao: true);
    await tester.pump();

    expect(
      _ordemNaTela(tester),
      rankBy(RankCriterion.ritmo, _outubro).map((r) => r.uid).toList(),
    );
  });

  testWidgets('o cabeçalho do rodapé só existe quando há rodapé', (
    tester,
  ) async {
    // Em Rotas todo mundo disputa — zero rota é placar honesto.
    await _pump(tester, criterion: RankCriterion.rotas);
    await tester.pumpAndSettle();
    expect(find.text('AINDA SEM AMOSTRA'), findsNothing);

    await _pump(tester, criterion: RankCriterion.ritmo);
    await tester.pumpAndSettle();
    expect(find.text('AINDA SEM AMOSTRA'), findsOneWidget);

    // E fica entre a disputa e quem está fora dela.
    final secao = tester.getTopLeft(find.text('AINDA SEM AMOSTRA')).dy;
    expect(secao, greaterThan(_y(tester, 'carla')));
    expect(secao, lessThan(_y(tester, 'jonas')));
  });

  testWidgets(
    'buscando o mês novo, a lista velha esmaece e o progresso aparece',
    (tester) async {
      await _pump(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // `pump` e não `pumpAndSettle`: o progresso indeterminado nunca assenta.
      await _pump(tester, loading: true);
      await tester.pump();

      // Os números na tela são do mês anterior; com opacidade cheia eles
      // passariam por números do mês do título.
      final corpo = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('ranking-corpo')),
      );
      expect(corpo.opacity, lessThan(1));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    },
  );

  testWidgets('a primeira busca desenha o esqueleto, não um spinner solto', (
    tester,
  ) async {
    await _pump(tester, buckets: null, loading: true);
    await tester.pump();

    expect(find.byKey(const ValueKey('ranking-esqueleto')), findsOneWidget);
    expect(find.byType(RankTile), findsNothing);
  });

  testWidgets('sem amigos, o aviso e nenhuma linha', (tester) async {
    await _pump(tester, hasFriends: false);

    expect(
      find.textContaining('Adicione amigos para comparar'),
      findsOneWidget,
    );
    expect(find.byType(RankTile), findsNothing);
  });

  testWidgets('ninguém na disputa: o aviso nomeia a amostra, e o rodapé fica', (
    tester,
  ) async {
    await _pump(
      tester,
      criterion: RankCriterion.ritmo,
      buckets: const {
        'wesley': MonthStats(
          routes: 20,
          pacedRoutes: 1,
          pacedStops: 30,
          pacedMinutes: 150,
        ),
        'jonas': MonthStats(routes: 3),
      },
    );
    await tester.pumpAndSettle();

    // "Ninguém tem 5 rotas" seria falso na cara de quem tem vinte.
    expect(
      find.textContaining('Ninguém tem 5 rotas com hora de fim e paradas'),
      findsOneWidget,
    );
    expect(find.byType(RankTile), findsNWidgets(2));
  });

  testWidgets('a falha diz o que houve e deixa tentar de novo', (tester) async {
    var tentativas = 0;
    await _pump(tester, failed: true, onRetry: () => tentativas++);

    expect(find.text('Não foi possível carregar o ranking.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ranking-tentar-de-novo')));
    expect(tentativas, 1);
  });

  testWidgets(
    'as setas do mês seguem os callbacks, e o critério avisa o toque',
    (tester) async {
      var seguinte = 0;
      final criterios = <RankCriterion>[];
      await _pump(
        tester,
        onPrevious: null,
        onNext: () => seguinte++,
        onCriterion: criterios.add,
      );

      final anterior = tester.widget<IconButton>(
        find.byKey(const ValueKey('mes-anterior')),
      );
      expect(anterior.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('mes-seguinte')));
      await tester.tap(find.byKey(const ValueKey('criterio-insucesso')));
      expect(seguinte, 1);
      expect(criterios, [RankCriterion.insucesso]);
      expect(find.text('OUTUBRO 2026'), findsOneWidget);
    },
  );

  testWidgets('com a fonte grande do sistema, nenhuma linha estoura', (
    tester,
  ) async {
    await _pump(tester, criterion: RankCriterion.ritmo, escala: 1.3);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // As linhas não se sobrepõem: a medida acompanhou a fonte.
    final ordem = _ordemNaTela(tester);
    for (var i = 1; i < ordem.length; i++) {
      final acima = tester.getRect(
        find.byKey(ValueKey('rank-${ordem[i - 1]}')),
      );
      final abaixo = tester.getRect(find.byKey(ValueKey('rank-${ordem[i]}')));
      expect(abaixo.top, greaterThanOrEqualTo(acima.bottom));
    }
  });
}
