/// Consulta à tabela FIPE — marcas, modelos e anos do mercado brasileiro.
///
/// Sem chave e sem cadastro, 500 requisições por dia. É o que permite o
/// entregador **escolher** o carro numa lista em vez de digitar o nome dele.
///
/// Um cadastro custa cerca de três requisições: marcas ao abrir o formulário,
/// modelos ao escolher a marca, anos ao escolher o modelo.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iter/model/vehicle.dart';

const _base = 'https://parallelum.com.br/fipe/api/v1';

/// Carro e moto são coleções diferentes na FIPE.
String fipePath(VehicleType type) =>
    type == VehicleType.moto ? '$_base/motos' : '$_base/carros';

/// Um item de qualquer uma das listas: `{codigo, nome}`.
@immutable
class FipeItem {
  const FipeItem({required this.code, required this.name});

  final String code;
  final String name;

  /// Igualdade por valor porque o `DropdownButton` compara o item escolhido
  /// com os da lista: sem isto, reabrir a tela de edição não marcaria o que já
  /// estava selecionado.
  @override
  bool operator ==(Object other) =>
      other is FipeItem && other.code == code && other.name == name;

  @override
  int get hashCode => Object.hash(code, name);

  @override
  String toString() => name;
}

/// Lê `[{codigo, nome}, …]` — o formato de `/marcas` e de `/anos`.
///
/// Devolve `null` quando o corpo não é uma lista legível. `null` e lista vazia
/// são coisas diferentes de propósito: "a consulta falhou" e "a marca não tem
/// modelo nenhum" levam a telas diferentes. Colapsar as duas foi o que escondeu
/// a falha do clima por meses.
List<FipeItem>? parseFipeList(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return null;

    return _itemsFrom(decoded);
  } catch (e) {
    debugPrint('FIPE: resposta ilegível: $e');
    return null;
  }
}

/// Lê `{"modelos": [...], "anos": [...]}` — só `/modelos` vem embrulhado assim.
///
/// Aqui o `codigo` chega como **inteiro** (`11376`), enquanto em `/marcas` ele
/// é string (`"21"`). É por isso que [_itemsFrom] converte em vez de fazer cast.
List<FipeItem>? parseFipeModels(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final models = decoded['modelos'];
    if (models is! List) return null;

    return _itemsFrom(models);
  } catch (e) {
    debugPrint('FIPE: resposta de modelos ilegível: $e');
    return null;
  }
}

/// Item fora do formato é pulado, não derruba a lista inteira.
List<FipeItem> _itemsFrom(List<dynamic> raw) {
  final items = <FipeItem>[];

  for (final entry in raw) {
    if (entry is! Map) continue;

    final code = entry['codigo'];
    final name = entry['nome'];
    if (code == null || name is! String) continue;

    // `toString()` e não cast: string em `/marcas`, int em `/modelos`.
    items.add(FipeItem(code: code.toString(), name: name));
  }

  return items;
}

/// As três chamadas que o formulário faz.
///
/// Todas devolvem `null` quando **não deu para saber** — sem rede, HTTP de
/// erro, corpo inesperado. A tela usa isso para oferecer "tentar de novo" em
/// vez de dizer que a marca não tem modelos.
class FipeService {
  static Future<List<FipeItem>?> brands(VehicleType type) =>
      _fetch('${fipePath(type)}/marcas', parseFipeList);

  static Future<List<FipeItem>?> models(VehicleType type, String brandCode) =>
      _fetch('${fipePath(type)}/marcas/$brandCode/modelos', parseFipeModels);

  static Future<List<FipeItem>?> years(
    VehicleType type,
    String brandCode,
    String modelCode,
  ) => _fetch(
    '${fipePath(type)}/marcas/$brandCode/modelos/$modelCode/anos',
    parseFipeList,
  );

  static Future<List<FipeItem>?> _fetch(
    String url,
    List<FipeItem>? Function(String) parse,
  ) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          // A FIPE é de terceiro e o cadastro não pode ficar pendurado nela:
          // estourou, a tela cai no campo de texto livre.
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        debugPrint('FIPE: HTTP ${response.statusCode} em $url');
        return null;
      }

      // `bodyBytes` decodificado como UTF-8: `response.body` assume latin-1
      // quando o servidor não manda charset, e "Citroën" viraria "CitroÃ«n".
      return parse(utf8.decode(response.bodyBytes));
    } catch (e) {
      debugPrint('FIPE: falha ao consultar $url: $e');
      return null;
    }
  }
}
