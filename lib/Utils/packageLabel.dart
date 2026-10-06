/// O que uma etiqueta do Mercado Livre diz, a partir do QR e do texto lido
/// pela câmera.
///
/// Função pura, sem tipo de câmera nem de ML Kit na assinatura — o mesmo
/// desenho de `nicknameFromScan` no convite por QR. A tela entrega texto com
/// posição ([OcrLine]); as regras moram aqui e são testadas com as linhas
/// reais das fotos que motivaram a feature. Ver `docs/specs/leitor-de-pacotes.md`.
///
/// **O QR não traz endereço nem tipo.** O conteúdo inteiro é
/// `{"id":"47806623578","t":"lm"}` — o número do envio. Ele é a identidade do
/// pacote (o que impede contar a mesma etiqueta duas vezes); bairro e letra
/// vêm do texto impresso.
///
/// A etiqueta carrega dados de **terceiros**: nome, rua, CEP e complemento de
/// quem vai receber. Daqui só sai o bairro, a letra e uma chave de parada que
/// vive na memória da sessão — nada disso vai para log nem para o banco.
library;

import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:iter/Utils/bairros.dart';
import 'package:iter/Utils/text.dart';

/// A letra na tarja preta abaixo do QR.
enum PackageType { residencial, comercial, agencia }

/// A letra como a etiqueta imprime — e como o entregador lança no app do
/// Mercado Livre.
String packageTypeLetter(PackageType type) {
  switch (type) {
    case PackageType.residencial:
      return 'R';
    case PackageType.comercial:
      return 'C';
    case PackageType.agencia:
      return 'A';
  }
}

String packageTypeLabel(PackageType type) {
  switch (type) {
    case PackageType.residencial:
      return 'Residencial';
    case PackageType.comercial:
      return 'Comercial';
    case PackageType.agencia:
      return 'Agência';
  }
}

/// Um trecho de texto com a posição dele no quadro, no mesmo sistema de
/// coordenadas dos cantos do QR.
///
/// Tipo próprio para o parser ser testado sem câmera. [elements] espelha as
/// palavras de uma linha do ML Kit: a letra do tipo pode chegar **grudada** na
/// linha vizinha da mesma altura (na foto 2 ela fica na altura de "Cidade de
/// destino"), e aí só a palavra tem a posição certa.
class OcrLine {
  const OcrLine(this.text, this.box, {this.elements = const []});

  final String text;
  final Rect box;
  final List<OcrLine> elements;
}

/// O que uma etiqueta disse, já sem nada que identifique quem vai receber.
class LabelRead {
  const LabelRead({
    required this.shipmentId,
    this.type,
    this.bairro,
    this.rawBairro,
    this.stopKey,
  });

  final String shipmentId;

  /// `null` = a letra não foi lida. **Nunca um palpite**: um A contado como R
  /// é a agência fechada que ninguém tira da rota.
  final PackageType? type;

  /// Sempre um nome de `fortaleza_bairros`, ou `null`.
  final String? bairro;

  /// O que o OCR leu depois da última vírgula do endereço, para a revisão
  /// mostrar o que não casou com a lista.
  final String? rawBairro;

  /// CEP + número da casa: mesmo prédio, qualquer apartamento, é uma parada —
  /// como o app do Mercado Livre conta. Só existe na memória da sessão.
  final String? stopKey;
}

final _shipmentId = RegExp(r'^\d{6,20}$');

/// O número do envio, ou `null` se o QR não for uma etiqueta do Mercado Livre.
///
/// Recusar é o caso comum de quem aponta a câmera para a caixa errada — o QR
/// do convite do iter, um cartaz, a DANFE. Quem chama diz o que o código
/// **é**, para ninguém concluir que o leitor está quebrado.
String? shipmentIdFromQr(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw.trim());
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  final id = decoded['id'];
  final text = id is int ? id.toString() : id;
  if (text is! String || !_shipmentId.hasMatch(text)) return null;
  return text;
}

LabelRead readLabel({
  required String shipmentId,
  required List<Offset> qrCorners,
  required List<OcrLine> lines,
}) {
  final address = _addressOf(lines);
  final rawBairro = address == null ? null : _bairroText(address.text);

  return LabelRead(
    shipmentId: shipmentId,
    type: _typeOf(qrCorners, lines),
    bairro: rawBairro == null ? null : matchBairro(rawBairro),
    rawBairro: rawBairro,
    stopKey: address == null ? null : _stopKeyOf(address, lines),
  );
}

// ---------------------------------------------------------------------------
// Letra

/// Até onde, abaixo do QR, a tarja pode estar — em alturas do QR.
///
/// Nas duas fotos o centro da letra fica a ~0,2 e ~0,3 alturas da borda de
/// baixo. 0,6 dá folga para a câmera inclinada sem alcançar o código de barras
/// da DANFE, que fica bem mais abaixo.
const _letterReach = 0.6;

const _letters = {
  'R': PackageType.residencial,
  'C': PackageType.comercial,
  'A': PackageType.agencia,
};

/// A letra é a que está **logo abaixo do QR** — e só ela.
///
/// Sem a âncora geométrica, qualquer letra solta na etiqueta viraria tipo. Duas
/// letras diferentes na janela é ambiguidade, e ambiguidade é `null`.
PackageType? _typeOf(List<Offset> corners, List<OcrLine> lines) {
  if (corners.length < 3) return null;

  final qr = _bounds(corners);
  final window = Rect.fromLTRB(
    qr.left - qr.width * 0.1,
    qr.bottom - qr.height * 0.05,
    qr.right + qr.width * 0.1,
    qr.bottom + qr.height * _letterReach,
  );

  final found = <PackageType>{};
  for (final line in lines) {
    for (final piece in [line, ...line.elements]) {
      final type = _letterOf(piece.text);
      if (type != null && window.contains(piece.box.center)) found.add(type);
    }
  }

  return found.length == 1 ? found.single : null;
}

/// `R`, `R.`, `|R|` — a borda da tarja às vezes vira pontuação no OCR.
PackageType? _letterOf(String text) {
  final letters = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return letters.length == 1 ? _letters[letters] : null;
}

Rect _bounds(List<Offset> points) {
  var left = points.first.dx, right = left;
  var top = points.first.dy, bottom = top;
  for (final point in points) {
    if (point.dx < left) left = point.dx;
    if (point.dx > right) right = point.dx;
    if (point.dy < top) top = point.dy;
    if (point.dy > bottom) bottom = point.dy;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

// ---------------------------------------------------------------------------
// Endereço

class _Address {
  const _Address(this.text, this.anchor);

  /// O endereço do destinatário, sem o rótulo "Endereço:", com as linhas
  /// quebradas já juntadas.
  final String text;

  /// A linha do rótulo — o CEP do destinatário é o primeiro **abaixo** dela.
  final OcrLine anchor;
}

/// O bloco do endereço: a linha que começa com "Endereço:" e as que seguem
/// alinhadas à esquerda, até o CEP.
///
/// Bloco e não linha porque o bairro quebra: na foto 1 o endereço termina em
/// "575," e "Papicu" está na linha de baixo. Linhas de outra coluna (a letra,
/// o horário) não interrompem o bloco — são puladas.
///
/// Sem a âncora não há endereço: o remetente também tem rua, vírgula e bairro
/// ("Rodovia Presidente Dutra 4674, Centro"), e "Centro" está na lista.
_Address? _addressOf(List<OcrLine> lines) {
  final sorted = [...lines]..sort((a, b) => a.box.top.compareTo(b.box.top));

  final start = sorted.indexWhere((line) => _isAnchor(line.text));
  if (start < 0) return null;

  final anchor = sorted[start];
  final lineHeight = anchor.box.height;
  final parts = [_withoutLabel(anchor.text)];
  var bottom = anchor.box.bottom;

  for (final line in sorted.skip(start + 1)) {
    final aligned = (line.box.left - anchor.box.left).abs() <= lineHeight * 1.5;
    if (!aligned) continue;
    if (_isTerminator(line.text)) break;
    if (line.box.top > bottom + lineHeight * 1.2) break;

    parts.add(line.text.trim());
    bottom = line.box.bottom;
  }

  return _Address(parts.join(' '), anchor);
}

/// O que vem depois da **última** vírgula: "Rua Pereira de Miranda 575,
/// Papicu" → "Papicu".
String? _bairroText(String address) {
  final comma = address.lastIndexOf(',');
  if (comma < 0) return null;

  final text = address
      .substring(comma + 1)
      .replaceAll(RegExp(r'[\s.,;:]+$'), '')
      .trim();
  return text.isEmpty ? null : text;
}

/// CEP + número da casa. Faltando um dos dois, `null` — e o pacote vira parada
/// própria: o erro vai para o lado de **mais** paradas, que a revisão mostra,
/// em vez de juntar dois endereços diferentes num só.
String? _stopKeyOf(_Address address, List<OcrLine> lines) {
  final comma = address.text.lastIndexOf(',');
  if (comma < 0) return null;

  final digits = RegExp(r'\d+').allMatches(address.text.substring(0, comma));
  if (digits.isEmpty) return null;
  final number = digits.last.group(0)!;

  final cep = _cepBelow(address.anchor, lines);
  if (cep == null) return null;

  return '$cep $number';
}

/// Rótulo de até 3 letras colado a 8 dígitos, depois de [normalizeKey]:
/// "CEP: 60175045" e "CEF. 60165090" viram `cep60175045` e `cef60165090`.
final _cepLine = RegExp(r'^([a-z]{2,3})(\d{8})');

/// O CEP, se [text] for a linha do CEP.
///
/// Exige os 8 dígitos logo depois do rótulo, e não só o rótulo parecido: com
/// uma letra de tolerância, "Cen" de "Centro" passaria por "CEP" — e um bairro
/// quebrado na linha de baixo encerraria o próprio endereço.
String? _cepOf(String text) {
  final match = _cepLine.firstMatch(normalizeKey(text));
  if (match == null || _distance(match.group(1)!, 'cep') > 1) return null;
  return match.group(2);
}

/// O CEP do destinatário: a primeira linha de CEP abaixo do endereço. Abaixo
/// porque o remetente também tem CEP, sem rótulo, no topo da etiqueta.
String? _cepBelow(OcrLine anchor, List<OcrLine> lines) {
  final below = lines.where((line) => line.box.top > anchor.box.top).toList()
    ..sort((a, b) => a.box.top.compareTo(b.box.top));

  for (final line in below) {
    final cep = _cepOf(line.text);
    if (cep != null) return cep;
  }
  return null;
}

/// "Endereço:", e também "Endereco" e "Enderego" — a cedilha é o primeiro
/// caractere que a impressão térmica gasta come.
bool _isAnchor(String text) => _startsLike(text, 'endereco', 2);

/// O que vem depois do endereço. "CEF." é CEP (foto 2), "Complemeato" é
/// Complemento.
///
/// "Cidade de destino" é comparado **inteiro**: só "Cidade" encerraria o
/// endereço de quem mora na Cidade 2000 ou na Cidade dos Funcionários, com o
/// bairro quebrado na linha de baixo.
bool _isTerminator(String text) =>
    _cepOf(text) != null ||
    _startsLike(text, 'cidadededestino', 3) ||
    _startsLike(text, 'complemento', 2);

/// [text] começa com [phrase] (já normalizada), tolerando [maxDistance] letras
/// trocadas.
///
/// Compara o começo do texto **normalizado** com o tamanho da frase, e não a
/// primeira palavra: assim "Cidade de destino" vale como uma frase só, e um
/// rótulo colado ao valor ("CEP60175045") não escapa.
bool _startsLike(String text, String phrase, int maxDistance) {
  final key = normalizeKey(text);
  if (key.length < phrase.length - maxDistance) return false;

  final head = key.substring(
    0,
    key.length < phrase.length ? key.length : phrase.length,
  );
  return _distance(head, phrase) <= maxDistance;
}

String _withoutLabel(String anchorText) {
  final colon = anchorText.indexOf(':');
  if (colon >= 0) return anchorText.substring(colon + 1).trim();

  // Sem os dois-pontos, o rótulo é a primeira palavra.
  final space = anchorText.indexOf(' ');
  return space < 0 ? '' : anchorText.substring(space + 1).trim();
}

// ---------------------------------------------------------------------------
// Bairro

/// Chave normalizada → nome como está em `fortaleza_bairros`.
final Map<String, String> _bairroKeys = {
  for (final bairro in fortaleza_bairros) normalizeKey(bairro): bairro,
};

/// O nome da lista que [raw] quer dizer, ou `null`.
///
/// Um nome fora da lista **nunca** sai daqui: os rankings agrupam bairro por
/// texto exato, e um "Meirelles" viraria um bairro novo no gráfico.
///
/// Primeiro o igual depois de [normalizeKey]; depois o parecido — até 1 letra
/// de diferença em nome de até 6 letras, até 2 acima. E o parecido tem de ser
/// **o único** dentro dessa tolerância, não só o mais perto: cinco pares da
/// lista ficam a 1 ou 2 letras um do outro (Praia do Futuro I/II, Conjunto
/// Ceará I/II, Bela Vista/Boa Vista, Damas/Dunas, Itaperi/Vila Peri). Com
/// "o mais perto", um "Praia do Futuro" sem o numeral virava "Praia do Futuro
/// I" — que é chutar metade das vezes.
String? matchBairro(String raw) {
  final key = normalizeKey(raw);
  if (key.isEmpty) return null;

  final exact = _bairroKeys[key];
  if (exact != null) return exact;

  final limit = key.length <= 6 ? 1 : 2;
  String? match;
  for (final entry in _bairroKeys.entries) {
    if (_distance(key, entry.key) > limit) continue;
    if (match != null) return null;
    match = entry.value;
  }
  return match;
}

/// Distância de edição (Levenshtein): quantas letras inserir, apagar ou trocar
/// para ir de [a] a [b].
int _distance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);

  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final swap = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final delete = previous[j] + 1;
      final insert = current[j - 1] + 1;
      current[j] = [swap, delete, insert].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }

  return previous[b.length];
}
