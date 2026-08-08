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

  /// Menor tempo médio por rota — a mesma média que o dialog de perfil mostra
  /// como "Tempo médio", só que recortada no mês.
  tempo,

  /// Menor taxa de insucesso sobre os pacotes.
  insucesso;

  String get label => switch (this) {
    rotas => 'Rotas',
    tempo => 'Tempo',
    insucesso => 'Insucesso',
  };

  /// O que a linha diz embaixo do número, para ninguém confundir "menor é
  /// melhor" com "maior é melhor".
  String get hint => switch (this) {
    rotas => 'Quem mais rodou no mês',
    tempo => 'Menor tempo médio por rota',
    insucesso => 'Menor insucesso sobre os pacotes',
  };
}

/// Uma linha do ranking.
class RankRow {
  const RankRow({
    required this.uid,
    required this.value,
    required this.routes,
    required this.ranked,
  });

  final String uid;

  /// Rotas, minutos ou percentual, conforme o critério.
  ///
  /// `null` é **"não dá para calcular"** — quem nunca preenche hora de fim não
  /// tem tempo médio, quem nunca preenche pacotes não tem taxa. Colapsar em
  /// zero coroaria campeão quem não entregou nada.
  final double? value;

  /// Rotas realizadas no mês: a amostra de onde [value] saiu.
  final int routes;

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

/// Quantas rotas no mês uma média precisa ter para disputar.
///
/// Sem isto, quem rodou **uma** rota de 8 pacotes sem insucesso fica com 0% e
/// ganha de quem rodou 40 rotas e 3.000 pacotes com 1,4%. É o mesmo remédio do
/// `_minimumFills` do consumo real, que exige três abastecimentos antes de
/// confiar no km/l: a média de uma amostra pequena não é um número melhor, é
/// um número que ainda não existe.
///
/// **Não vale para [RankCriterion.rotas]** — lá a contagem é o próprio placar,
/// e exigir amostra mínima seria esconder justamente quem rodou pouco.
const int minimumRoutes = 5;

/// Monta a classificação de um critério.
///
/// Ordena por [value] na direção que o critério pede, desempata pelo número de
/// rotas (mais amostra na frente) e depois pelo uid, para a ordem não dançar
/// entre dois rebuilds com os mesmos dados.
///
/// Quem não disputa vem no fim, ordenado por rotas.
List<RankRow> rankBy(
  RankCriterion criterion,
  Map<String, MonthStats> buckets,
) {
  final rows = <RankRow>[];

  for (final entry in buckets.entries) {
    final stats = entry.value;
    final value = _valueOf(criterion, stats);

    rows.add(
      RankRow(
        uid: entry.key,
        value: value,
        routes: stats.routes,
        ranked: value != null && _hasSample(criterion, stats),
      ),
    );
  }

  final disputa = rows.where((row) => row.ranked).toList()
    ..sort((a, b) => _compare(criterion, a, b));

  final fora = rows.where((row) => !row.ranked).toList()
    ..sort((a, b) {
      final byRoutes = b.routes.compareTo(a.routes);
      return byRoutes != 0 ? byRoutes : a.uid.compareTo(b.uid);
    });

  return [...disputa, ...fora];
}

double? _valueOf(RankCriterion criterion, MonthStats stats) => switch (criterion) {
  // Zero rota é um número honesto aqui: a pessoa não rodou no mês.
  RankCriterion.rotas => stats.routes.toDouble(),
  RankCriterion.tempo => stats.minutesPerRoute,
  RankCriterion.insucesso => stats.failureRate,
};

bool _hasSample(RankCriterion criterion, MonthStats stats) =>
    criterion == RankCriterion.rotas || stats.routes >= minimumRoutes;

int _compare(RankCriterion criterion, RankRow a, RankRow b) {
  // Em rotas, maior é melhor. Em tempo e insucesso, menor é melhor.
  final byValue = criterion == RankCriterion.rotas
      ? b.value!.compareTo(a.value!)
      : a.value!.compareTo(b.value!);
  if (byValue != 0) return byValue;

  // Empate no número: quem tem mais amostra sustenta melhor o mesmo valor.
  final byRoutes = b.routes.compareTo(a.routes);
  return byRoutes != 0 ? byRoutes : a.uid.compareTo(b.uid);
}

/// Se a disputa tem alguém — para a tela dizer "ainda não dá" em vez de
/// desenhar uma lista só de rodapé.
bool hasCompetition(List<RankRow> rows) => rows.any((row) => row.ranked);
