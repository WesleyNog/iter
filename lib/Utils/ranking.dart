/// O ranking entre amigos, a partir dos baldes mensais publicados.
///
/// Puro sobre `Map<uid, MonthStats>`: quem busca os baldes é a tela, e é o que
/// permite testar as três disputas sem Firestore. Ver `docs/specs/amigos.md`.
library;

import 'package:iter/Utils/monthStats.dart';

/// As três disputas que o usuário pediu.
enum RankCriterion {
  /// Mais rotas feitas no mês, do maior para o menor.
  rotas,

  /// **Menor tempo por parada.** Já foi o tempo médio por rota, e a troca é a
  /// razão de este enum ter mudado de nome: aquela média não distinguia
  /// tamanho de rota, então quem pegava 30 pacotes em 2h aparecia na frente de
  /// quem pegava 200 em 8h — tendo sido bem menos produtivo. Dividir pela
  /// quantidade de paradas é o que torna as duas rotas comparáveis.
  ///
  /// A duração cheia não sumiu do app: ela é o que o card da rota e o dialog
  /// de perfil mostram, onde a pergunta é "quanto durou" e não "quem foi mais
  /// rápido". Ver `Utils/routePace.dart`.
  ritmo,

  /// Menor taxa de insucesso sobre os pacotes.
  insucesso;

  String get label => switch (this) {
    rotas => 'Rotas',
    ritmo => 'Ritmo',
    insucesso => 'Insucesso',
  };

  /// O que a linha diz embaixo do número, para ninguém confundir "menor é
  /// melhor" com "maior é melhor".
  String get hint => switch (this) {
    rotas => 'Quem mais rodou no mês',
    ritmo => 'Menor tempo por parada',
    insucesso => 'Menor insucesso sobre os pacotes',
  };

  /// O nome do denominador, para a linha mostrar de quantas paradas (ou
  /// pacotes) o número saiu. `null` em [rotas], onde o número **é** a amostra.
  ///
  /// Recebe a quantidade porque "1 paradas" é o tipo de erro que ninguém vê em
  /// teste — o caso de uma unidade só existe justamente em quem tem amostra
  /// pequena, que é quem o rodapé desenha.
  String? sampleUnitFor(int count) => switch (this) {
    rotas => null,
    ritmo => count == 1 ? 'parada' : 'paradas',
    insucesso => count == 1 ? 'pacote' : 'pacotes',
  };

  /// Como a tela descreve a amostra que falta quando ninguém alcança o mínimo.
  ///
  /// Dizer "ninguém tem 5 rotas" seria falso desde que a porta deixou de olhar
  /// [MonthStats.routes]: a pessoa pode ter vinte rotas no mês e nenhuma com
  /// hora de fim.
  String get sampleName => switch (this) {
    rotas => 'rotas',
    ritmo => 'rotas com hora de fim e paradas',
    insucesso => 'rotas com pacotes informados',
  };
}

/// Uma linha do ranking.
class RankRow {
  const RankRow({
    required this.uid,
    required this.value,
    required this.routes,
    required this.sampleRoutes,
    required this.sampleUnits,
    required this.ranked,
  });

  final String uid;

  /// Rotas, minutos ou percentual, conforme o critério.
  ///
  /// `null` é **"não dá para calcular"** — quem nunca preenche hora de fim não
  /// tem tempo médio, quem nunca preenche pacotes não tem taxa. Colapsar em
  /// zero coroaria campeão quem não entregou nada.
  final double? value;

  /// Rotas realizadas no mês, todas elas.
  ///
  /// **Não é a amostra de [value]** — é o que a linha mostra quando não há
  /// amostra nenhuma, e o que ordena o rodapé. Confundir os dois é o defeito
  /// que [sampleRoutes] conserta.
  final int routes;

  /// As rotas que **formaram** [value]: com hora de fim e paradas no ritmo,
  /// com pacotes no insucesso, todas na contagem de rotas.
  ///
  /// É esta que a amostra mínima cobra e que a linha mostra. Antes o mínimo
  /// olhava [routes] enquanto a média saía de outro conjunto, e quem tinha 40
  /// rotas com uma só cronometrada disputava com amostra de uma — anunciando
  /// "40 rotas" embaixo do número.
  final int sampleRoutes;

  /// O denominador de [value]: paradas no ritmo, pacotes no insucesso. `null`
  /// na contagem de rotas, onde o número é a própria amostra.
  ///
  /// Vai para a tela junto com [sampleRoutes] porque é onde mora o peso: `1,4%`
  /// de 3.000 pacotes e de 40 pacotes são o mesmo texto e não são a mesma
  /// informação.
  final int? sampleUnits;

  /// Se entrou na disputa. `false` vai para o rodapé, com o número visível
  /// mas fora da classificação.
  final bool ranked;
}

/// Quem entra no ranking: **você e seus amigos**, nesta ordem, sem repetir.
///
/// Existe como função e não como duas listas montadas em dois lugares porque
/// foi exatamente assim que a primeira versão quebrou: a tela buscava os
/// baldes de `[eu, ...amigos]` e o prefetch de perfis só dos amigos. O dono
/// aparecia no ranking como "Entregador", sem nome nem foto — o único
/// participante que o app conhecia melhor do que todos os outros.
List<String> rankingParticipants(String me, Iterable<String> friends) {
  return <String>{me, ...friends}.toList();
}

/// Quantas rotas **da população da média** ela precisa ter para disputar.
///
/// Sem isto, quem rodou **uma** rota de 8 pacotes sem insucesso fica com 0% e
/// ganha de quem rodou 40 rotas e 3.000 pacotes com 1,4%. É o mesmo remédio do
/// `_minimumFills` do consumo real, que exige três abastecimentos antes de
/// confiar no km/l: a média de uma amostra pequena não é um número melhor, é
/// um número que ainda não existe.
///
/// "Da população da média" é a correção que veio junto com o ritmo: a porta
/// contava as rotas do mês, e o número saía de um subconjunto delas. Quarenta
/// rotas com uma cronometrada passavam pelo mínimo com amostra de uma.
///
/// **Não vale para [RankCriterion.rotas]** — lá a contagem é o próprio placar,
/// e exigir amostra mínima seria esconder justamente quem rodou pouco.
const int minimumRoutes = 5;

/// Monta a classificação de um critério.
///
/// Ordena por [value] na direção que o critério pede, desempata pela amostra
/// do critério (mais amostra na frente) e depois pelo uid, para a ordem não
/// dançar entre dois rebuilds com os mesmos dados.
///
/// Quem não disputa vem no fim, ordenado pelas rotas do mês.
List<RankRow> rankBy(RankCriterion criterion, Map<String, MonthStats> buckets) {
  final rows = <RankRow>[];

  for (final entry in buckets.entries) {
    final stats = entry.value;
    final value = _valueOf(criterion, stats);
    final sampleRoutes = _sampleRoutesOf(criterion, stats);

    rows.add(
      RankRow(
        uid: entry.key,
        value: value,
        routes: stats.routes,
        sampleRoutes: sampleRoutes,
        sampleUnits: _sampleUnitsOf(criterion, stats),
        ranked:
            value != null &&
            (criterion == RankCriterion.rotas || sampleRoutes >= minimumRoutes),
      ),
    );
  }

  final disputa = rows.where((row) => row.ranked).toList()
    ..sort((a, b) => _compare(criterion, a, b));

  // O rodapé ordena pelas rotas do **mês**, não pela amostra: quem está aqui
  // costuma ter amostra zero, e ordenar por zero devolveria a lista ao acaso
  // do uid. "Quem rodou mais" continua sendo a leitura útil de quem está fora.
  final fora = rows.where((row) => !row.ranked).toList()
    ..sort((a, b) {
      final byRoutes = b.routes.compareTo(a.routes);
      return byRoutes != 0 ? byRoutes : a.uid.compareTo(b.uid);
    });

  return [...disputa, ...fora];
}

double? _valueOf(RankCriterion criterion, MonthStats stats) =>
    switch (criterion) {
      // Zero rota é um número honesto aqui: a pessoa não rodou no mês.
      RankCriterion.rotas => stats.routes.toDouble(),
      RankCriterion.ritmo => stats.minutesPerStop,
      RankCriterion.insucesso => stats.failureRate,
    };

/// As rotas que formaram o número — **não** as do mês.
int _sampleRoutesOf(RankCriterion criterion, MonthStats stats) =>
    switch (criterion) {
      RankCriterion.rotas => stats.routes,
      RankCriterion.ritmo => stats.pacedRoutes,
      RankCriterion.insucesso => stats.packagedRoutes,
    };

int? _sampleUnitsOf(RankCriterion criterion, MonthStats stats) =>
    switch (criterion) {
      RankCriterion.rotas => null,
      RankCriterion.ritmo => stats.pacedStops,
      RankCriterion.insucesso => stats.packages,
    };

int _compare(RankCriterion criterion, RankRow a, RankRow b) {
  // Em rotas, maior é melhor. Em ritmo e insucesso, menor é melhor.
  final byValue = criterion == RankCriterion.rotas
      ? b.value!.compareTo(a.value!)
      : a.value!.compareTo(b.value!);
  if (byValue != 0) return byValue;

  // Empate no número: quem tem mais amostra sustenta melhor o mesmo valor —
  // e a amostra é a do critério, não a do mês.
  final byRoutes = b.sampleRoutes.compareTo(a.sampleRoutes);
  if (byRoutes != 0) return byRoutes;

  // Mesmo número de rotas: 1% de 1.000 pacotes sustenta melhor que 1% de 100.
  final byUnits = (b.sampleUnits ?? 0).compareTo(a.sampleUnits ?? 0);
  return byUnits != 0 ? byUnits : a.uid.compareTo(b.uid);
}

/// Se a disputa tem alguém — para a tela dizer "ainda não dá" em vez de
/// desenhar uma lista só de rodapé.
bool hasCompetition(List<RankRow> rows) => rows.any((row) => row.ranked);

/// A legenda da amostra, embaixo do nome: `506 paradas · 12 rotas`.
///
/// Mora aqui e não na tela porque é decisão, não desenho — e porque decisão em
/// `State` privado não tem como ser testada: a `RankingTab` abre o Firestore no
/// `initState`. É o mesmo caminho que `pendingOnly` e `FriendTile` já fizeram,
/// registrado na estratégia de teste da spec.
///
/// **Sem amostra, cai nas rotas do mês.** Vale para os dois lados do par, e o
/// zero do denominador é o que escapou na primeira versão: um balde antigo
/// devolve `packagedRoutes` pelas rotas do mês e `packages` zerado, e a linha
/// afirmava "0 pacotes · 17 rotas" — as duas metades da frase se contradizendo.
/// Sob o cabeçalho "AINDA SEM AMOSTRA", "17 rotas" é o que sobra de verdadeiro.
String sampleLabel(RankCriterion criterion, RankRow row) {
  final units = row.sampleUnits;
  final unit = units == null ? null : criterion.sampleUnitFor(units);

  if (unit == null || units == 0 || row.sampleRoutes == 0) {
    return routesLabel(row.routes);
  }

  return '$units $unit · ${routesLabel(row.sampleRoutes)}';
}

/// `1 rota` / `12 rotas`.
String routesLabel(int count) => count == 1 ? '1 rota' : '$count rotas';
