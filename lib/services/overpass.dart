/// Postos de combustível por proximidade, via Overpass API (OpenStreetMap).
///
/// Sem chave e sem cadastro. Medido em Fortaleza: 25 a 60 postos num raio de
/// 3 km, o mais próximo entre 245 e 570 m — cobertura suficiente para o
/// entregador escolher de uma lista em vez de digitar.
///
/// A Overpass é serviço comunitário mantido por doação. Uma consulta por
/// abastecimento é uso doméstico e cabe folgado na política de uso; qualquer
/// coisa além disso pede instância própria.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iter/model/supply.dart';

const _endpoint = 'https://overpass-api.de/api/interpreter';

/// A Overpass recusa cliente genérico com `406 Not Acceptable` — a política de
/// uso pede que a aplicação se identifique. Não é opcional.
const overpassUserAgent = 'iter-app/1.0 (Flutter; controle de rotas de entrega)';

/// Um posto e a que distância ele está de quem perguntou.
typedef NearbyStation = ({FuelStation station, double meters});

/// Monta a consulta.
///
/// Duas coisas aqui não são estilo, são requisito:
///
/// - **`nwr`** e não `node`. Consultando só nós, o Centro de Fortaleza devolveu
///   5 postos; com `nwr`, 60 — **49 deles são polígonos** (`way`). Perder 80%
///   dos postos foi exatamente o que a primeira versão fez.
/// - **`out center`**, senão polígono volta sem `lat`/`lon` e não há como
///   ordenar por distância.
String overpassQuery(double lat, double lng, int radius) {
  return '[out:json][timeout:25];'
      'nwr["amenity"="fuel"](around:$radius,$lat,$lng);'
      'out center tags;';
}

/// Distância em metros entre duas coordenadas (haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;

  final dLat = _radians(lat2 - lat1);
  final dLng = _radians(lng2 - lng1);

  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.pow(math.sin(dLng / 2), 2);

  return 2 * earthRadius * math.asin(math.sqrt(a));
}

double _radians(double degrees) => degrees * math.pi / 180;

/// Lê a resposta e devolve os postos **do mais próximo para o mais distante**.
///
/// `null` significa **não deu para saber** — corpo ilegível, HTML de `429` ou
/// `504`. Lista vazia significa só o que diz: não há posto no raio. Colapsar as
/// duas coisas diria "nenhum posto por perto" no meio da cidade.
List<NearbyStation>? parseStations(
  String body, {
  required double lat,
  required double lng,
}) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final elements = decoded['elements'];
    if (elements is! List) return null;

    final stations = <NearbyStation>[];

    for (final element in elements) {
      if (element is! Map) continue;

      final station = _stationFrom(element);
      // Sem coordenada não dá para ordenar nem para gravar em `gastop`; um
      // elemento assim é pulado em vez de derrubar a lista inteira.
      if (station == null) continue;

      stations.add((
        station: station,
        meters: distanceMeters(lat, lng, station.lat, station.lng),
      ));
    }

    // O requisito é literal: o primeiro da lista é o mais próximo, quase
    // sempre o posto em que ele está parado.
    stations.sort((a, b) => a.meters.compareTo(b.meters));
    return stations;
  } catch (e) {
    debugPrint('Overpass: resposta ilegível: $e');
    return null;
  }
}

FuelStation? _stationFrom(Map<dynamic, dynamic> element) {
  final type = element['type'];
  final id = element['id'];
  if (type is! String || id == null) return null;

  // Nó traz `lat`/`lon` na raiz; polígono e relação trazem em `center`.
  final center = element['center'];
  final lat = _readCoord(center is Map ? center['lat'] : element['lat']);
  final lng = _readCoord(center is Map ? center['lon'] : element['lon']);
  if (lat == null || lng == null) return null;

  final tags = element['tags'];
  final map = tags is Map ? tags : const {};

  return FuelStation(
    // O tipo entra no id porque `node/1` e `way/1` são postos diferentes. Com
    // hífen em vez de barra: é chave de documento no Firestore, e barra ali
    // separa coleção de documento.
    id: '$type-$id',
    name: map['name'] as String? ?? '',
    brand: map['brand'] as String?,
    lat: lat,
    lng: lng,
  );
}

double? _readCoord(Object? raw) => (raw as num?)?.toDouble();

class OverpassService {
  /// Postos num raio de [radius] metros, do mais próximo ao mais distante.
  ///
  /// `null` quando não deu para saber — a tela usa isso para oferecer "tentar
  /// de novo" e o campo de texto livre, em vez de dizer que não há posto.
  static Future<List<NearbyStation>?> stationsNear(
    double lat,
    double lng, {
    int radius = 3000,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: const {'User-Agent': overpassUserAgent},
            body: overpassQuery(lat, lng, radius),
          )
          // Serviço de terceiro sob carga: o cadastro não pode ficar pendurado
          // nele. Estourou, a tela cai no texto livre.
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        debugPrint('Overpass: HTTP ${response.statusCode}');
        return null;
      }

      // `bodyBytes` como UTF-8: nome de posto tem acento, e `response.body`
      // assume latin-1 quando o servidor não manda charset.
      return parseStations(
        utf8.decode(response.bodyBytes),
        lat: lat,
        lng: lng,
      );
    } catch (e) {
      debugPrint('Overpass: falha ao consultar: $e');
      return null;
    }
  }
}
