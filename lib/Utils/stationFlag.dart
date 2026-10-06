/// A bandeira de um posto, para desenhar o logo.
///
/// Os logos são **assets do app**: nenhuma requisição e nada baixado da
/// internet. O caminho Wikidata → Commons foi avaliado e recusado em
/// `docs/specs/abastecimento.md` — a Petrobras nem tem logo cadastrado lá.
///
/// Derivada, **nunca gravada**, como o `pricePerLiter`: é uma função de `brand`
/// e `name`, e uma bandeira gravada um dia discorda da regra que a produziu.
/// Ver `docs/specs/postos-da-regiao.md`.
library;

import 'package:iter/Utils/text.dart';
import 'package:iter/model/supply.dart';

/// A bandeira que o app sabe desenhar.
enum StationFlag {
  br('assets/images/POSTO-BR.png', {'br', 'petrobras'}, fillsCircle: true),
  shell('assets/images/POSTO-SHELL.png', {'shell'}),
  ipiranga('assets/images/POSTO-IPIRANGA.png', {'ipiranga'}),
  ale('assets/images/POSTO-ALE.png', {'ale', 'alesat'}),
  semBandeira('assets/images/POSTO-SEMBANDEIRA.png', {});

  const StationFlag(this.asset, this.aliases, {this.fillsCircle = false});

  final String asset;

  /// As palavras, já normalizadas, que significam esta bandeira. Servem a
  /// [flagOf] e ao filtro da lista — quem busca "petrobras" quer a BR.
  final Set<String> aliases;

  /// O logo da BR é um quadrado e cabe cortado no círculo, como no print de
  /// referência. Os outros perdem a forma cortados — a concha, o oval da ALE —
  /// e entram inteiros.
  final bool fillsCircle;
}

final _byAlias = {
  for (final flag in StationFlag.values)
    for (final alias in flag.aliases) alias: flag,
};

/// A bandeira deste posto.
///
/// `brand` decide quando existe; o nome só é consultado quando ninguém disse.
/// Uma `brand` desconhecida (SP, OM) **não** cai no nome: "Posto Shell" com
/// `brand=SP` é dado contraditório, e o desenho neutro é o erro que não afirma
/// nada.
///
/// Medido na região metropolitana em 06/10/2026: 206 de 379 postos ganham logo.
StationFlag flagOf(FuelStation station) {
  final brand = station.brand?.trim() ?? '';
  if (brand.isNotEmpty) return _flagIn(brand) ?? StationFlag.semBandeira;

  return _flagIn(station.name) ?? StationFlag.semBandeira;
}

/// A primeira palavra de [text] que é uma bandeira conhecida.
///
/// Palavra inteira e não trecho, a mesma armadilha que `FuelStation.label` já
/// evita: com `contains`, "BR" casaria dentro de "Posto **Br**asil".
StationFlag? _flagIn(String text) {
  for (final word in text.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))) {
    final flag = _byAlias[normalizeKey(word)];
    if (flag != null) return flag;
  }
  return null;
}
