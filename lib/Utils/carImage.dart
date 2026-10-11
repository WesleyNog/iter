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
/// 36 px da AppBar, aparece no cabeçalho do formulário. Publicar na loja exige
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

/// O mesmo render, **enquadrado no carro**, para onde ele aparece pequeno.
///
/// O render padrão põe o carro no meio de uma tela com margem larga em volta;
/// no botão de 36 px da `AppBar`, com `contain`, o carro ficava com menos da
/// metade do quadrado. `zoomType=fullscreen` é a própria CDN ampliando o
/// veículo até preencher a tela — um parâmetro da API, não uma edição da
/// imagem, então continua dentro da licença. A largura cai para o tamanho do
/// ícone: 600 px para desenhar 36 era banda à toa.
///
/// Recebe a URL **gravada**: os veículos confirmados antes disto guardam a URL
/// sem o parâmetro, e é na exibição que ele entra. URL que não é da imagin
/// volta como veio.
String framedCarImageUrl(String url, {int width = 240}) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.host.endsWith('imagin.studio')) return url;

  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'zoomType': 'fullscreen',
          'width': '$width',
        },
      )
      .toString();
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
