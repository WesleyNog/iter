/// Monta a URL do render do veículo na CDN da imagin.studio.
///
/// Função pura de string, sem rede — a imagem é buscada pelo `Image.network`
/// da tela. Fica em `Utils/` e não em `services/` pelo mesmo critério que separa
/// `Utils/weather.dart` de `services/openWeather.dart`.
///
/// **A URL é montada e exibida, os bytes nunca são guardados.** A licença da
/// imagin proíbe baixar, cachear e modificar as imagens; usar direto da CDN é o
/// que mantém o app dentro dela. Ver `docs/specs/cadastro-veiculo.md`.
library;

import 'package:iter/Utils/text.dart';
import 'package:iter/model/vehicle.dart';

const _cdn = 'https://cdn.imagin.studio/getimage';

/// Cliente de demonstração da imagin. Traz marca d'água — some no ícone de
/// 32 px da AppBar, aparece no cabeçalho do formulário. Publicar na loja exige
/// uma licença paga e um `customer` próprio.
const _customer = 'img';

/// URL do render, ou `null` quando não dá para montar uma confiável.
///
/// Moto sempre devolve `null`: a CDN não cobre duas rodas e, pior, **não avisa**
/// — pedir `honda/cg` responde `found=true` entregando um Honda Pilot, um SUV.
/// Não perguntar é melhor que receber o veículo errado com cara de certo.
///
/// Mesmo para carro o resultado é um palpite: a família é extraída do nome
/// comprido da FIPE. Por isso a tela **pergunta** se é esse o carro antes de
/// gravar a URL.
String? carImageUrl({
  required VehicleType type,
  required String brandName,
  required String modelName,
  int width = 600,
}) {
  if (type == VehicleType.moto) return null;

  final make = imaginMake(brandName);
  final family = imaginModelFamily(modelName);
  if (make == null || family == null) return null;

  return '$_cdn'
      '?customer=$_customer'
      '&make=$make'
      '&modelFamily=$family'
      '&angle=01'
      '&width=$width';
}

/// `"GM - Chevrolet"` → `chevrolet`, `"Citroën"` → `citroen`.
///
/// A FIPE prega a sigla histórica na frente de algumas marcas; a CDN espera só
/// o nome, sem acento e sem espaço.
String? imaginMake(String brandName) => _slug(Vehicle.brandLabel(brandName));

/// `"Strada Adventure 1.8 mpi Flex CE"` → `strada`.
///
/// A FIPE nomeia a **versão** inteira, com motor e acabamento; a CDN quer a
/// família. A primeira palavra acerta a grande maioria dos modelos brasileiros
/// (Strada, Fiorino, Saveiro, Onix, HB20, Kwid) e erra em nomes compostos como
/// "Grand Siena" — que é exatamente o que a confirmação do usuário pega.
String? imaginModelFamily(String modelName) {
  for (final token in modelName.split(RegExp(r'\s+'))) {
    // "1.4", "1.0": cilindrada não é nome de família. Um número inteiro
    // sozinho é — Fiat 500, Fiat 147.
    if (RegExp(r'^\d+[.,]\d+$').hasMatch(token)) continue;

    final slug = _slug(token);
    if (slug != null) return slug;
  }

  return null;
}

/// Minúsculas, sem acento e só com letra e número. `null` quando não sobra
/// nada — aqui vazio significa "não dá para montar URL", diferente do
/// [normalizeKey], que devolve string vazia.
String? _slug(String raw) {
  final slug = normalizeKey(raw);
  return slug.isEmpty ? null : slug;
}
