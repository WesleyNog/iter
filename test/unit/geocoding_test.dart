import 'package:flutter_test/flutter_test.dart';
import 'package:iter/services/geocoding.dart';

/// Respostas reais do Nominatim, capturadas em 06/10/2026 com
/// `addressdetails=1` e o `viewbox` de Fortaleza, cortadas nos campos que o
/// parse lê.
///
/// Os quatro foram escolhidos a dedo: um bairro **sem `city`** (só
/// `municipality`), um endereço **sem `name`** (só rua e número), e dois
/// "Centro" de cidades diferentes — a busca "Centro" devolveu cinco.
const _real = '''
[
 {
  "lat": "-3.7934337",
  "lon": "-38.5690832",
  "addresstype": "suburb",
  "name": "Maraponga",
  "display_name": "Maraponga, Fortaleza, Ceará, Região Nordeste, Brasil",
  "address": {
   "suburb": "Maraponga",
   "municipality": "Fortaleza",
   "state": "Ceará",
   "country": "Brasil"
  }
 },
 {
  "lat": "-3.7330660",
  "lon": "-38.5537620",
  "addresstype": "building",
  "name": "",
  "display_name": "1000, Avenida Bezerra de Menezes, São Gerardo, Fortaleza, Ceará, Região Nordeste, 60325-001, Brasil",
  "address": {
   "house_number": "1000",
   "road": "Avenida Bezerra de Menezes",
   "suburb": "São Gerardo",
   "city": "Fortaleza",
   "municipality": "Fortaleza",
   "state": "Ceará",
   "postcode": "60325-001",
   "country": "Brasil"
  }
 },
 {
  "lat": "-3.7281287",
  "lon": "-38.5274120",
  "addresstype": "suburb",
  "name": "Centro",
  "display_name": "Centro, Fortaleza, Ceará, Região Nordeste, Brasil",
  "address": {
   "suburb": "Centro",
   "city": "Fortaleza",
   "state": "Ceará"
  }
 },
 {
  "lat": "-3.7349987",
  "lon": "-38.6551922",
  "addresstype": "suburb",
  "name": "Centro",
  "display_name": "Centro, Caucaia, Ceará, Região Nordeste, Brasil",
  "address": {
   "suburb": "Centro",
   "city": "Caucaia",
   "state": "Ceará"
  }
 }
]
''';

void main() {
  group('parse da resposta real', () {
    test('lê os quatro, na ordem do Nominatim', () {
      final places = parsePlaces(_real)!;

      expect(places.map((p) => p.title), [
        'Maraponga',
        'Avenida Bezerra de Menezes, 1000',
        'Centro',
        'Centro',
      ]);
    });

    test('coordenada vem como texto e vira double', () {
      final maraponga = parsePlaces(_real)!.first;

      expect(maraponga.lat, closeTo(-3.7934337, 1e-9));
      expect(maraponga.lng, closeTo(-38.5690832, 1e-9));
    });

    test('bairro sem city usa municipality', () {
      expect(parsePlaces(_real)!.first.detail, 'Fortaleza, Ceará');
    });

    test('endereço sem nome vira rua e número, com o bairro no detalhe', () {
      final address = parsePlaces(_real)![1];

      expect(address.title, 'Avenida Bezerra de Menezes, 1000');
      expect(address.detail, 'São Gerardo, Fortaleza, Ceará');
    });

    test('dois "Centro" se distinguem pela cidade', () {
      // Sem a cidade no detalhe, o Centro de Caucaia passaria pelo de
      // Fortaleza e a lista de postos sairia a 13 km do lugar certo.
      final centros = parsePlaces(_real)!.where((p) => p.title == 'Centro');

      expect(centros.map((p) => p.detail), [
        'Fortaleza, Ceará',
        'Caucaia, Ceará',
      ]);
    });

    test('sem address, o display_name ainda dá título e detalhe', () {
      const body = '''
      [{"lat":"-3.7","lon":"-38.5","name":"",
        "display_name":"Rua X, Bairro Y, Fortaleza, Ceará, Brasil"}]
      ''';

      final place = parsePlaces(body)!.single;

      expect(place.title, 'Rua X');
      expect(place.detail, 'Bairro Y, Fortaleza');
    });
  });

  group('respostas problemáticas', () {
    test('lista vazia é "nada encontrado", não erro', () {
      // Capturado: a busca "xyzzy qwerty inexistente" devolve `[]`.
      expect(parsePlaces('[]'), isEmpty);
    });

    test('corpo ilegível é null — "falhou" não é "não existe"', () {
      expect(parsePlaces('<html>Bandwidth limit exceeded</html>'), isNull);
      expect(parsePlaces(''), isNull);
      expect(parsePlaces('{"error":"x"}'), isNull);
    });

    test('item sem coordenada é pulado, não derruba a lista', () {
      const body = '''
      [{"name":"Sem coordenada","display_name":"Sem coordenada"},
       {"lat":"-3.7","lon":"-38.5","name":"Ok","display_name":"Ok, Fortaleza"}]
      ''';

      expect(parsePlaces(body)!.map((p) => p.title), ['Ok']);
    });
  });

  group('a requisição', () {
    test('pede o Brasil, em português, com endereço detalhado', () {
      final params = nominatimUri('Maraponga').queryParameters;

      expect(params['q'], 'Maraponga');
      expect(params['format'], 'jsonv2');
      expect(params['countrycodes'], 'br');
      expect(params['addressdetails'], '1');
      expect(params['accept-language'], 'pt-BR');
      expect(params['limit'], '5');
    });

    test('viewbox em volta da posição, quando ela existe', () {
      // `x1,y1,x2,y2` é longitude primeiro.
      final viewbox = nominatimUri(
        'Centro',
        lat: -3.73,
        lng: -38.52,
      ).queryParameters['viewbox']!.split(',').map(double.parse).toList();

      expect(viewbox[0], lessThan(-38.52));
      expect(viewbox[2], greaterThan(-38.52));
      expect(viewbox[1], greaterThan(-3.73));
      expect(viewbox[3], lessThan(-3.73));
    });

    test('sem posição, o viewbox cai em Fortaleza', () {
      final viewbox = nominatimUri(
        'Centro',
      ).queryParameters['viewbox']!.split(',').map(double.parse).toList();

      // A Praça do Ferreira tem de estar dentro.
      expect(viewbox[0], lessThan(-38.527));
      expect(viewbox[2], greaterThan(-38.527));
      expect(viewbox[1], greaterThan(-3.727));
      expect(viewbox[3], lessThan(-3.727));
    });

    test('o viewbox puxa, não prende — um posto em Caucaia ainda aparece', () {
      expect(nominatimUri('Caucaia').queryParameters['bounded'], isNot('1'));
    });

    test('o User-Agent identifica o app', () {
      // A política de uso do Nominatim exige, como a da Overpass.
      expect(nominatimUserAgent, contains('iter'));
    });
  });
}
