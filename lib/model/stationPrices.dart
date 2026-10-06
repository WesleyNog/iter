/// O que `gastop/{stationId}` sabe dos preços de um posto.
///
/// Só **lê**. Quem grava é `StationController.report`, e o desenho do
/// documento está em `docs/specs/abastecimento.md` e
/// `docs/specs/postos-da-regiao.md`.
library;

import 'package:iter/model/supply.dart';

/// As colunas da faixa de preços do card, nessa ordem.
///
/// Os três líquidos de [SupplyFuel] que saem de uma bomba. Elétrico fica de
/// fora: não existe em posto de combustível, e a coluna seria sempre `—`.
const pumpFuels = [SupplyFuel.gasolina, SupplyFuel.etanol, SupplyFuel.diesel];

/// Um preço relatado, e quando.
///
/// [at] é `null` nos documentos gravados antes de `pricedAt` existir: o preço
/// aparece sem idade, e não com uma idade emprestada.
typedef ReportedPrice = ({double price, DateTime? at});

class StationPrices {
  const StationPrices(this._byFuel);

  final Map<SupplyFuel, ReportedPrice> _byFuel;

  /// O último preço relatado deste combustível, ou `null` quando ninguém
  /// relatou — e a tela desenha `—`.
  ReportedPrice? of(SupplyFuel fuel) => _byFuel[fuel];

  /// Leitura tolerante: chave desconhecida, preço que não é número e data
  /// ilegível são **ignorados um a um**. A coleção é escrita por qualquer
  /// usuário autenticado, e um valor ruim não pode apagar os bons do mesmo
  /// posto.
  ///
  /// A data vem de `pricedAt.{combustível}` e **nunca** de `updatedAt`: este
  /// muda quando qualquer combustível é relatado, e daria à gasolina de agosto
  /// a idade do etanol de ontem.
  factory StationPrices.fromMap(Map<String, dynamic> map) {
    final prices = map['prices'];
    final pricedAt = map['pricedAt'];
    if (prices is! Map) return const StationPrices({});

    final byFuel = <SupplyFuel, ReportedPrice>{};

    for (final fuel in SupplyFuel.values) {
      // `is num` e não `readDouble`: aquele faz `as num?` e lança com texto, e
      // um "seis reais" escrito por alguém derrubaria o posto inteiro.
      final raw = prices[fuel.name];
      final price = raw is num ? raw.toDouble() : null;
      // Preço zero não é preço: "R$ 0,00" diria que o posto dá combustível.
      if (price == null || price <= 0) continue;

      final rawAt = pricedAt is Map ? pricedAt[fuel.name] : null;
      byFuel[fuel] = (
        price: price,
        at: rawAt is String ? DateTime.tryParse(rawAt) : null,
      );
    }

    return StationPrices(byFuel);
  }
}
