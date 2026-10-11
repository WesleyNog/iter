import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/carImage.dart';
import 'package:iter/model/vehicle.dart';

/// Decodifica a foto gravada, devolvendo `null` quando o texto não é base64.
///
/// `base64Decode` **lança**, e lança antes de qualquer `errorBuilder` rodar —
/// um único documento com o campo corrompido derrubaria a lista inteira de
/// veículos, que é exatamente o que o `try/catch` por documento do controller
/// existe para impedir.
Uint8List? decodePhoto(String? raw) {
  if (raw == null || raw.isEmpty) return null;

  try {
    return base64Decode(raw);
  } catch (e) {
    debugPrint('Veículo: foto em base64 ilegível: $e');
    return null;
  }
}

/// A imagem do veículo, com a mesma precedência em toda tela do app.
///
/// Existe para essa precedência viver em **um** lugar: o card da lista e o
/// ícone da `AppBar` mostram o mesmo veículo, e duas implementações acabariam
/// discordando sobre qual imagem vale.
///
/// Ordem: foto do dono → render da CDN → silhueta. A foto ganha porque é a do
/// carro dele; o render é um palpite que ele apenas confirmou.
class VehicleThumb extends StatelessWidget {
  const VehicleThumb({
    super.key,
    required this.vehicle,
    this.size = 56,
    this.radius = 12,
    this.background,
    this.renderFit = BoxFit.cover,
    this.framedRender = false,
  });

  final Vehicle? vehicle;
  final double size;
  final double radius;

  /// `null` usa o cinza do card. A `AppBar` passa transparente: lá o fundo é o
  /// vidro do botão, e um quadrado cinza dentro dele seria uma moldura a mais.
  final Color? background;

  /// Como o **render** da CDN ocupa o quadrado. A foto do dono sempre cobre —
  /// é uma foto, e foto com faixa vazia em volta parece erro.
  ///
  /// O render é um carro largo sobre fundo transparente: `cover` corta a
  /// frente e a traseira, e num quadrado pequeno sobra o meio da porta. A
  /// `AppBar` pede `contain` para o carro aparecer inteiro.
  final BoxFit renderFit;

  /// Pede à CDN o render enquadrado no carro (`framedCarImageUrl`). Só onde o
  /// quadrado é pequeno: no cabeçalho do formulário o carro com margem é o
  /// enquadramento que o usuário confirmou.
  final bool framedRender;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: background ?? Colors.grey.shade200,
        child: _content(),
      ),
    );
  }

  Widget _content() {
    final v = vehicle;
    if (v == null) return _silhouette(VehicleType.carro);

    final photo = decodePhoto(v.photoBase64);
    if (photo != null) {
      return Image.memory(
        photo,
        fit: BoxFit.cover,
        // Bytes válidos em base64 mas que não são imagem.
        errorBuilder: (_, _, _) => _silhouette(v.type),
      );
    }

    final url = v.imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        framedRender ? framedCarImageUrl(url) : url,
        fit: renderFit,
        errorBuilder: (_, _, _) => _silhouette(v.type),
      );
    }

    return _silhouette(v.type);
  }

  Widget _silhouette(VehicleType type) => Icon(
    type == VehicleType.moto
        ? Icons.two_wheeler_outlined
        : Icons.directions_car_outlined,
    size: size * 0.55,
    color: Colors.grey.shade500,
  );
}
