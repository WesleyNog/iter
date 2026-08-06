/// Leitura defensiva de mapas vindos do Firestore.
///
/// Existe porque um documento fora do formato não pode derrubar a leitura da
/// coleção inteira — a mesma razão do `try/catch` por documento em
/// `RouteController._parseAll`.
library;

/// Lê um número que pode ter vindo como `int`.
///
/// O Firestore devolve `int` quando o valor gravado não tem casa decimal, então
/// `map['price'] as double?` lança em um documento que guardou `500` e não
/// `500.0`.
double? readDouble(Object? raw) => (raw as num?)?.toDouble();

int? readInt(Object? raw) => (raw as num?)?.toInt();

/// Lê um enum gravado como string bare, caindo em [fallback] no desconhecido.
///
/// `firstWhere` sem `orElse` — o jeito que `NewRouteModal` faz com `Company` e
/// `StatusRoute` — lança quando o valor não existe mais no enum, e um único
/// documento assim derrubaria toda a coleção.
T readEnum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}
