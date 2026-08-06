import 'package:flutter_test/flutter_test.dart';
import 'package:iter/services/overpass.dart';

/// Resposta real da Overpass, capturada em 05/08/2026 para um raio de 1,2 km
/// do Centro de Fortaleza.
///
/// Os dois elementos foram escolhidos a dedo: o `node` tem **só marca, sem
/// nome** (a maioria dos postos do OSM é assim) e o `way` tem `center`, que é
/// como polígono ganha coordenada.
const _real = '''
{
 "elements": [
  {
   "type": "node",
   "id": 6303387822,
   "lat": -3.732484,
   "lon": -38.5339943,
   "tags": {
    "addr:city": "Fortaleza",
    "amenity": "fuel",
    "brand": "Ipiranga"
   }
  },
  {
   "type": "way",
   "id": 243218168,
   "center": { "lat": -3.7238357, "lon": -38.5197446 },
   "tags": {
    "amenity": "fuel",
    "brand": "Shell",
    "name": "Posto Prainha"
   }
  }
 ]
}
''';

// Centro de Fortaleza — a origem das distâncias conferidas abaixo.
const _lat = -3.7319;
const _lng = -38.5267;

void main() {
  group('a query — onde a primeira versão perdeu 80% dos postos', () {
    test('pergunta por nwr, não só por node', () {
      // Com `node` a consulta devolveu 5 postos no Centro; com `nwr`, 60 —
      // porque 49 deles são polígonos.
      final query = overpassQuery(_lat, _lng, 3000);

      expect(query, contains('nwr'));
      expect(query, isNot(contains('node["amenity"')));
    });

    test('pede out center, senão polígono volta sem coordenada', () {
      expect(overpassQuery(_lat, _lng, 3000), contains('out center'));
    });

    test('leva o raio e as coordenadas pedidos', () {
      final query = overpassQuery(_lat, _lng, 5000);

      expect(query, contains('around:5000'));
      expect(query, contains('-3.7319'));
      expect(query, contains('-38.5267'));
    });
  });

  group('distância', () {
    test('confere com um valor conhecido', () {
      // Um grau de latitude no equador ≈ 111,2 km.
      expect(distanceMeters(0, 0, 1, 0), closeTo(111195, 50));
    });

    test('mesma coordenada é zero', () {
      expect(distanceMeters(_lat, _lng, _lat, _lng), closeTo(0, 0.001));
    });
  });

  group('parse da resposta real', () {
    test('lê node e way na mesma passada', () {
      final stations = parseStations(_real, lat: _lat, lng: _lng)!;

      expect(stations.length, 2);
    });

    test('tira a coordenada de center quando o elemento é polígono', () {
      final stations = parseStations(_real, lat: _lat, lng: _lng)!;
      final prainha = stations.firstWhere((s) => s.station.id == 'way-243218168');

      expect(prainha.station.lat, closeTo(-3.7238357, 1e-9));
      expect(prainha.station.lng, closeTo(-38.5197446, 1e-9));
    });

    test('o id carrega o tipo junto, para ser global e estável', () {
      // `way-243218168` é o mesmo id para qualquer usuário do app: é o que
      // permite dois entregadores escreverem no mesmo documento de `gastop`.
      final ids = parseStations(_real, lat: _lat, lng: _lng)!
          .map((s) => s.station.id)
          .toList();

      expect(ids, containsAll(['node-6303387822', 'way-243218168']));
    });

    test('posto sem nome cai na marca', () {
      final stations = parseStations(_real, lat: _lat, lng: _lng)!;
      final semNome = stations.firstWhere(
        (s) => s.station.id == 'node-6303387822',
      );

      expect(semNome.station.name, isEmpty);
      expect(semNome.station.label, 'Ipiranga');
    });

    test('calcula a distância de cada posto', () {
      final stations = parseStations(_real, lat: _lat, lng: _lng)!;
      final byId = {for (final s in stations) s.station.id: s.meters};

      expect(byId['node-6303387822'], closeTo(812, 2));
      expect(byId['way-243218168'], closeTo(1183, 2));
    });

    test('o mais próximo vem primeiro', () {
      // É o requisito do usuário: "o primeiro da lista seria o mais próximo,
      // provavelmente em cima da localização".
      final stations = parseStations(_real, lat: _lat, lng: _lng)!;

      expect(stations.first.station.id, 'node-6303387822');
      expect(stations.first.meters, lessThan(stations.last.meters));
    });
  });

  group('respostas problemáticas', () {
    test('lista vazia é resposta válida, não erro', () {
      expect(parseStations('{"elements":[]}', lat: _lat, lng: _lng), isEmpty);
    });

    test('corpo ilegível devolve null — "falhou" não é "não tem posto"', () {
      // A Overpass responde 429 e 504 com HTML sob carga. Colapsar isso em
      // lista vazia diria "não há posto por perto" no meio da cidade.
      expect(parseStations('<html>rate limited</html>', lat: _lat, lng: _lng), isNull);
      expect(parseStations('', lat: _lat, lng: _lng), isNull);
      expect(parseStations('[]', lat: _lat, lng: _lng), isNull);
    });

    test('elemento sem coordenada é pulado, não derruba a lista', () {
      // `way` sem `center` acontece quando a query esquece o `out center`.
      const body = '''
      {"elements":[
        {"type":"way","id":1,"tags":{"name":"Sem coordenada"}},
        {"type":"node","id":2,"lat":-3.7319,"lon":-38.5267,"tags":{"name":"Ok"}}
      ]}
      ''';

      final stations = parseStations(body, lat: _lat, lng: _lng)!;

      expect(stations.length, 1);
      expect(stations.first.station.name, 'Ok');
    });

    test('elemento sem tags vira posto sem nome, e não some', () {
      const body = '''
      {"elements":[{"type":"node","id":9,"lat":-3.7319,"lon":-38.5267}]}
      ''';

      final stations = parseStations(body, lat: _lat, lng: _lng)!;

      expect(stations.length, 1);
      expect(stations.first.station.label, 'Posto sem nome');
    });
  });

  test('o User-Agent identifica o app — sem ele a Overpass responde 406', () {
    // Aconteceu no teste com cliente genérico. A política de uso da Overpass
    // pede que a aplicação se identifique.
    expect(overpassUserAgent, contains('iter'));
    expect(overpassUserAgent.length, greaterThan(10));
  });
}
