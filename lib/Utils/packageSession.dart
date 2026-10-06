/// A contagem de uma leitura de carga: o que a barra mostra enquanto o
/// entregador lê e o que a revisão grava ao finalizar.
///
/// Pura, como [readLabel]: a tela da câmera só chama [PackageSession.add] e
/// redesenha. As regras que quebrariam em silêncio moram aqui e têm teste — a
/// mesma etiqueta contada duas vezes, um tipo escolhido à mão sobrescrito pela
/// leitura seguinte, um bairro fora da lista entrando na rota. Ver
/// `docs/specs/leitor-de-pacotes.md`.
///
/// Vive só na memória da tela. O número do envio e a chave de parada (CEP +
/// número da casa) existem para deduplicar e agrupar, e morrem com ela.
library;

import 'package:iter/Utils/insucessoBairro.dart';
import 'package:iter/Utils/packageLabel.dart';

/// Um pacote lido nesta sessão.
class PackageEntry {
  const PackageEntry({
    required this.shipmentId,
    this.type,
    this.bairro,
    this.rawBairro,
    this.stopKey,
  });

  factory PackageEntry.fromRead(LabelRead read) => PackageEntry(
    shipmentId: read.shipmentId,
    type: read.type,
    bairro: read.bairro,
    rawBairro: read.rawBairro,
    stopKey: read.stopKey,
  );

  final String shipmentId;

  /// `null` = a letra não foi lida e ninguém escolheu ainda: o "?" da barra.
  final PackageType? type;

  /// Sempre um nome de `fortaleza_bairros`, ou `null`.
  final String? bairro;

  final String? rawBairro;
  final String? stopKey;

  PackageEntry _with({PackageType? type}) => PackageEntry(
    shipmentId: shipmentId,
    type: type ?? this.type,
    bairro: bairro,
    rawBairro: rawBairro,
    stopKey: stopKey,
  );

  /// Preenche **só o que faltava** com uma leitura nova do mesmo pacote.
  ///
  /// Nunca troca o que já existe: a câmera relê a etiqueta enquanto ela segue
  /// enquadrada, e uma segunda leitura pior — ou o "R" que finalmente apareceu
  /// depois de o entregador ter tocado em "A" — não pode desfazer a primeira.
  /// Bairro e texto lido andam juntos, para a revisão nunca mostrar um bairro
  /// de uma leitura com o texto bruto de outra.
  PackageEntry _filledFrom(LabelRead read) {
    final takeBairro = bairro == null && read.bairro != null;
    final takeRaw = bairro == null && rawBairro == null;

    return PackageEntry(
      shipmentId: shipmentId,
      type: type ?? read.type,
      bairro: takeBairro ? read.bairro : bairro,
      rawBairro: takeBairro || takeRaw ? read.rawBairro : rawBairro,
      stopKey: stopKey ?? read.stopKey,
    );
  }

  bool _sameAs(PackageEntry other) =>
      type == other.type &&
      bairro == other.bairro &&
      rawBairro == other.rawBairro &&
      stopKey == other.stopKey;
}

/// O que aconteceu com uma leitura.
enum ReadOutcome {
  /// Pacote novo: conta, vibra, mostra o cartão.
  added,

  /// Pacote já contado, mas a leitura trouxe o que faltava (a letra, o
  /// bairro). Não conta de novo.
  completed,

  /// Nada de novo: o "Já lido".
  repeated,
}

class PackageSession {
  /// Ordem de inserção: a lista da sessão mostra do mais recente para o mais
  /// antigo, e "o último lido" é o que os botões R/C/A corrigem.
  final Map<String, PackageEntry> _entries = {};

  ReadOutcome add(LabelRead read) {
    final current = _entries[read.shipmentId];
    if (current == null) {
      _entries[read.shipmentId] = PackageEntry.fromRead(read);
      return ReadOutcome.added;
    }

    final filled = current._filledFrom(read);
    if (filled._sameAs(current)) return ReadOutcome.repeated;

    _entries[read.shipmentId] = filled;
    return ReadOutcome.completed;
  }

  /// A escolha do entregador — nos botões do cartão ou na lista. Sobrescreve
  /// a leitura, que é o que corrigir quer dizer.
  void setType(String shipmentId, PackageType type) {
    final current = _entries[shipmentId];
    if (current == null) return;
    _entries[shipmentId] = current._with(type: type);
  }

  /// A agência fechada saindo da carga, ou uma leitura que não era deste
  /// pacote.
  void remove(String shipmentId) => _entries.remove(shipmentId);

  PackageEntry? operator [](String shipmentId) => _entries[shipmentId];

  /// Do mais recente para o mais antigo.
  List<PackageEntry> get entries => _entries.values.toList().reversed.toList();

  bool get isEmpty => _entries.isEmpty;

  int get total => _entries.length;

  int count(PackageType type) =>
      _entries.values.where((entry) => entry.type == type).length;

  /// Os "?": contam no total e em nenhum tipo.
  int get untyped =>
      _entries.values.where((entry) => entry.type == null).length;

  /// Mesmo prédio é uma parada. Pacote sem chave é parada própria — o erro
  /// vai para o lado de **mais** paradas, que a revisão mostra e deixa
  /// corrigir, em vez de juntar dois endereços num só.
  int get stops {
    final keys = <String>{};
    var alone = 0;
    for (final entry in _entries.values) {
      final key = entry.stopKey;
      if (key == null) {
        alone++;
      } else {
        keys.add(key);
      }
    }
    return keys.length + alone;
  }

  /// Bairro → pacotes, do que mais recebeu para o que menos recebeu; empate
  /// pelo nome, para a ordem não dançar entre dois redesenhos.
  ///
  /// É a ordem que vai para `adress`: `reconcileDistribution` corta a partir
  /// do **fim** quando precisa, e o fim é o bairro de menos pacotes.
  Map<String, int> get pacotesPorBairro {
    final counts = <String, int>{};
    for (final entry in _entries.values) {
      final bairro = entry.bairro;
      if (bairro == null) continue;
      counts.update(bairro, (value) => value + 1, ifAbsent: () => 1);
    }

    final ordered = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return {for (final entry in ordered) entry.key: entry.value};
  }

  List<String> get bairros => pacotesPorBairro.keys.toList();

  /// Pacotes que contam e não têm bairro da lista.
  int get withoutBairro =>
      _entries.values.where((entry) => entry.bairro == null).length;

  /// O que o OCR leu e não casou com a lista, com quantos pacotes cada — para
  /// a revisão dizer "2 pacotes em 'Água Fria'" em vez de esconder o buraco.
  /// Quando o leiaute da etiqueta mudar, é este número que avisa.
  Map<String, int> get unmatchedBairros {
    final counts = <String, int>{};
    for (final entry in _entries.values) {
      final raw = entry.rawBairro;
      if (entry.bairro != null || raw == null) continue;
      counts.update(raw, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

/// O que a revisão manda gravar na rota.
class PackageLoad {
  const PackageLoad({
    required this.packages,
    required this.stops,
    required this.bairros,
    required this.pacotesPorBairro,
  });

  final int packages;
  final int stops;

  /// Vai para `adress` e **substitui** os bairros do agendamento.
  final List<String> bairros;

  final Map<String, int> pacotesPorBairro;
}

/// A carga como a revisão a deixou: os números que o entregador conferiu e os
/// bairros que ele manteve.
///
/// A contagem por bairro passa por [reconcileDistribution], a mesma regra que
/// o formulário aplica depois: bairro tirado na revisão leva a parte dele para
/// o rateio, e um total corrigido para baixo corta a partir do bairro de menos
/// pacotes. Sem isso, a rota sairia daqui gravando 87 pacotes "medidos" numa
/// carga que o entregador acabou de dizer que tem 85.
PackageLoad loadOf(
  PackageSession session, {
  required int packages,
  required int stops,
  required List<String> bairros,
}) => PackageLoad(
  packages: packages,
  stops: stops,
  bairros: List.unmodifiable(bairros),
  pacotesPorBairro: reconcileDistribution(
    distribution: session.pacotesPorBairro,
    bairros: bairros,
    total: packages,
  ),
);
