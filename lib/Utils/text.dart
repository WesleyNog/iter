/// Normalização de texto para **comparação**, não para exibição.
///
/// Existe porque a mesma tabela de acentos já estava copiada em dois lugares
/// (`Utils/carImage.dart` e `controller/nicknameController.dart`) e um terceiro
/// consumidor apareceu com as regras de manutenção. Duas cópias é descuido;
/// três é hora de extrair.
///
/// `nicknameController` **continua com a cópia dele** de propósito: a
/// normalização de apelido tem o regex espelhado em `firestore.rules` e zero
/// teste cobrindo, então mexer nela por arrumação arriscaria a reserva de
/// apelidos em troca de nada.
library;

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

final _keepable = RegExp(r'^[a-z0-9]$');

/// Minúsculas, sem acento e só com letra e número.
///
/// `"Óleo do motor"` e `"OLEO DO MOTOR"` viram a mesma chave. Devolve string
/// vazia quando não sobra nada — quem precisa distinguir "vazio" de "nada
/// aproveitável" checa `isEmpty`.
String normalizeKey(String raw) {
  final buffer = StringBuffer();

  for (final char in raw.toLowerCase().split('')) {
    final plain = _accents[char] ?? char;
    if (_keepable.hasMatch(plain)) buffer.write(plain);
  }

  return buffer.toString();
}
