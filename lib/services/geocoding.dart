/// Um bairro ou endereço virando coordenada, via Nominatim (OpenStreetMap).
///
/// Existe para "Outra localização" em "Postos da região": quem registra o
/// abastecimento em casa precisa da lista em volta do posto, não de si mesmo.
/// Sem chave, o mesmo ecossistema da Overpass.
///
/// A política de uso **proíbe autocompletar** e limita a 1 requisição por
/// segundo. Por isso só existe [GeocodingService.search], chamada na
/// confirmação da busca — nunca a cada letra. Ver
/// `docs/specs/postos-da-regiao.md`.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iter/services/overpass.dart';

const _endpoint = 'https://nominatim.openstreetmap.org/search';

/// O mesmo do app inteiro para o OSM: a política do Nominatim exige que a
/// aplicação se identifique, como a da Overpass.
const nominatimUserAgent = overpassUserAgent;

/// Um lugar encontrado: o que mostrar e onde fica.
///
/// [detail] carrega a cidade **sempre que existe**: "Centro" voltou em cinco
/// cidades da região metropolitana, e sem ela o de Caucaia passaria pelo de
/// Fortaleza.
typedef Place = ({String title, String detail, double lat, double lng});

/// Metade do lado da caixa que puxa os resultados para perto, em graus
/// (~28 km). Cobre a região metropolitana a partir de qualquer ponto dela.
const _bias = 0.25;

/// Fortaleza, para quando não há posição — o mesmo escopo de `bairros.dart`.
const _fortaleza = (lat: -3.7319, lng: -38.5267);

/// Monta a consulta.
///
/// O `viewbox` **puxa, não prende** (`bounded` fica de fora): sem ele,
/// "Messejana" sem cidade poderia cair em outro estado; com `bounded=1`, um
/// posto em Caucaia não apareceria para quem está em Fortaleza.
Uri nominatimUri(String query, {double? lat, double? lng}) {
  final centerLat = lat ?? _fortaleza.lat;
  final centerLng = lng ?? _fortaleza.lng;

  return Uri.parse(_endpoint).replace(
    queryParameters: {
      'q': query,
      'format': 'jsonv2',
      'countrycodes': 'br',
      'addressdetails': '1',
      'accept-language': 'pt-BR',
      'limit': '5',
      // `x1,y1,x2,y2`: longitude primeiro.
      'viewbox': [
        centerLng - _bias,
        centerLat + _bias,
        centerLng + _bias,
        centerLat - _bias,
      ].join(','),
    },
  );
}

/// Lê a resposta.
///
/// `null` significa **não deu para saber** — corpo ilegível, HTML de limite de
/// uso. Lista vazia significa só o que diz: nada com esse nome. A tela diz
/// frases diferentes para os dois.
List<Place>? parsePlaces(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return null;

    return [
      for (final item in decoded)
        if (item is Map) ?_placeFrom(item),
    ];
  } catch (e) {
    debugPrint('Nominatim: resposta ilegível: $e');
    return null;
  }
}

Place? _placeFrom(Map<dynamic, dynamic> item) {
  final lat = double.tryParse('${item['lat']}');
  final lng = double.tryParse('${item['lon']}');
  if (lat == null || lng == null) return null;

  final address = item['address'];
  if (address is Map) {
    final title = _titleFrom(item['name'], address);
    if (title != null) {
      return (
        title: title,
        detail: _detailFrom(title, address),
        lat: lat,
        lng: lng,
      );
    }
  }

  // Sem `address`: o `display_name` é "título, detalhe, …".
  final parts = _text(item['display_name'])?.split(', ') ?? const <String>[];
  if (parts.isEmpty) return null;

  return (
    title: parts.first,
    detail: parts.skip(1).take(2).join(', '),
    lat: lat,
    lng: lng,
  );
}

/// O nome, ou "Rua, número" quando o lugar é um endereço e não tem nome.
String? _titleFrom(Object? name, Map<dynamic, dynamic> address) {
  final named = _text(name);
  if (named != null) return named;

  final road = _text(address['road']);
  if (road == null) return null;

  final number = _text(address['house_number']);
  return number == null ? road : '$road, $number';
}

/// Bairro (quando não é o próprio título), cidade e estado.
///
/// Cidade cai de `city` para `town`, `village` e `municipality`: a Maraponga
/// voltou só com `municipality`.
String _detailFrom(String title, Map<dynamic, dynamic> address) {
  final suburb = _text(address['suburb']);
  final city =
      _text(address['city']) ??
      _text(address['town']) ??
      _text(address['village']) ??
      _text(address['municipality']);

  return [
    if (suburb != null && suburb != title) suburb,
    ?city,
    ?_text(address['state']),
  ].join(', ');
}

String? _text(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  return text.isEmpty ? null : text;
}

class GeocodingService {
  /// Os lugares que batem com [query], os mais perto de ([lat], [lng]) puxados
  /// para cima.
  ///
  /// `null` quando não deu para saber. Chamar **só** na confirmação da
  /// busca — autocompletar viola a política de uso.
  static Future<List<Place>?> search(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final response = await http
          .get(
            nominatimUri(trimmed, lat: lat, lng: lng),
            headers: const {'User-Agent': nominatimUserAgent},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('Nominatim: HTTP ${response.statusCode}');
        return null;
      }

      // `bodyBytes` como UTF-8: "Ceará" e "São Gerardo" chegariam em latin-1.
      return parsePlaces(utf8.decode(response.bodyBytes));
    } catch (e) {
      debugPrint('Nominatim: falha ao consultar: $e');
      return null;
    }
  }
}
