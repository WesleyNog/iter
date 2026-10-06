/// O campo "Buscar por nome, bairro ou bandeira" de "Postos da região".
///
/// Filtra só a lista **já carregada** — o raio em volta do centro atual. Achar
/// um posto em outro bairro é trabalho de "Outra localização", que move o
/// centro; o filtro nunca vai à rede.
library;

import 'package:iter/Utils/stationFlag.dart';
import 'package:iter/Utils/text.dart';
import 'package:iter/services/overpass.dart';

/// Os postos que batem com [query], **na ordem recebida**.
///
/// Quem ordena é `parseStations`, por distância. Reordenar aqui seria uma
/// segunda noção de "mais próximo", e as duas acabariam discordando.
///
/// Cada palavra da consulta tem de aparecer em algum campo — "shell serrinha"
/// acha o Shell da Serrinha, e não todo Shell mais todo posto da Serrinha.
/// Trecho de palavra vale, porque a busca ainda está sendo digitada: "marap"
/// já acha a Maraponga.
List<NearbyStation> filterStations(List<NearbyStation> stations, String query) {
  final words = query
      .split(RegExp(r'\s+'))
      .map(normalizeKey)
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return stations;

  return [
    for (final nearby in stations)
      if (_matchesAll(_fieldsOf(nearby), words)) nearby,
  ];
}

/// Os textos onde procurar, já normalizados.
///
/// A bandeira entra pelos apelidos da bandeira **derivada**, e não só pelo
/// texto da tag: o posto com `brand=Petrobras` mostra o logo da BR, e quem
/// busca "BR" pelo logo que está vendo tem de achá-lo.
List<String> _fieldsOf(NearbyStation nearby) {
  final station = nearby.station;

  return [
    normalizeKey(station.name),
    normalizeKey(station.brand ?? ''),
    normalizeKey(station.suburb ?? ''),
    // A rua é o título de quem não tem nome: tem de ser achável pelo que se
    // está vendo.
    normalizeKey(station.address ?? ''),
    ...flagOf(station).aliases,
  ];
}

bool _matchesAll(List<String> fields, List<String> words) =>
    words.every((word) => fields.any((field) => field.contains(word)));
