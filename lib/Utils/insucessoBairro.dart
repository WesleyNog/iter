/// Regras da distribuição de insucessos entre os bairros de uma rota.
///
/// Na memória a distribuição é um `Map<String, int>` (bairro → quantidade); no
/// Firestore vira array de map, `[{'bairro': 'Aldeota', 'qnt': 2}]`. Array e
/// não mapa porque chave com ponto quebra field path no Firestore — nenhum
/// bairro tem hoje, mas um "Pref. José Walter" entrando na lista amanhã viraria
/// bug silencioso.
///
/// Este arquivo **não conhece `NewRouteModal`** de propósito: quem importa é o
/// modelo, e o contrário fecharia um ciclo. Aqui só entram `Map` e `List`.
///
/// As mesmas regras valem em três lugares — no sheet enquanto o usuário mexe,
/// no `addIter` ao salvar e no `routeStats` ao ler documento antigo. Três
/// cópias divergiriam no primeiro ajuste.
library;

int _sum(Map<String, int> distribution) =>
    distribution.values.fold(0, (total, qnt) => total + qnt);

/// Quantos insucessos ainda não têm bairro. Nunca negativo.
int remainingFailures(int total, Map<String, int> distribution) {
  final left = total - _sum(distribution);
  return left < 0 ? 0 : left;
}

/// Ajusta a distribuição ao estado atual da rota.
///
/// A distribuição pode ficar inconsistente **sem o usuário mexer nela**: basta
/// remover um bairro de "Bairros" ou baixar a quantidade de insucessos depois
/// de já ter distribuído. Daí esta função ser chamada também na leitura — o que
/// está gravado não é digno de confiança.
///
/// - bairro fora de [bairros] é descartado, e a quantidade dele volta a ser
///   "não distribuída" (vai para o rateio);
/// - quantidade zero ou negativa não vira registro;
/// - soma acima de [total] é cortada **a partir do último** bairro da lista,
///   preservando o começo do que já foi marcado;
/// - a ordem do resultado segue [bairros], não a de entrada.
Map<String, int> reconcileDistribution({
  required Map<String, int> distribution,
  required List<String> bairros,
  required int total,
}) {
  if (total <= 0 || bairros.isEmpty) return <String, int>{};

  final result = <String, int>{};
  for (final bairro in bairros) {
    final qnt = distribution[bairro] ?? 0;
    if (qnt > 0) result[bairro] = qnt;
  }

  var excess = _sum(result) - total;
  if (excess <= 0) return result;

  for (final bairro in bairros.reversed) {
    if (excess <= 0) break;

    final qnt = result[bairro];
    if (qnt == null) continue;

    final cut = qnt < excess ? qnt : excess;
    // Atualizar a chave existente mantém a posição dela no mapa; remover e
    // recolocar jogaria o bairro para o fim da ordem.
    if (qnt - cut == 0) {
      result.remove(bairro);
    } else {
      result[bairro] = qnt - cut;
    }
    excess -= cut;
  }

  return result;
}

/// Para o Firestore. Bairro zerado não vira registro.
List<Map<String, dynamic>> distributionToList(Map<String, int> distribution) => [
  for (final entry in distribution.entries)
    if (entry.value > 0) {'bairro': entry.key, 'qnt': entry.value},
];

/// Do Firestore. Aceita `null` (campo ausente, que é o caso de todo documento
/// gravado antes desta funcionalidade) e ignora entrada malformada em vez de
/// lançar — um registro estranho não pode derrubar a leitura da rota inteira.
Map<String, int> distributionFromList(dynamic raw) {
  final result = <String, int>{};
  if (raw is! List) return result;

  for (final item in raw) {
    if (item is! Map) continue;

    final bairro = item['bairro'];
    final qnt = item['qnt'];
    if (bairro is! String || bairro.isEmpty) continue;
    if (qnt is! int || qnt <= 0) continue;

    // Bairro repetido soma: descartar o segundo perderia insucesso.
    result.update(bairro, (value) => value + qnt, ifAbsent: () => qnt);
  }

  return result;
}
