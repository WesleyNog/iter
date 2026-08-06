/// Veículo do entregador e os parâmetros de custo que ele carrega.
///
/// Existe para alimentar a provisão por rota: cada campo aqui ou entra na conta
/// de `Utils/vehicleCost.dart`, ou identifica o veículo na lista. Placa, cor e
/// valor FIPE ficaram de fora justamente por não fazerem nem uma coisa nem
/// outra — ver `docs/specs/cadastro-veiculo.md`.
library;

import 'package:iter/Utils/mapRead.dart';

enum VehicleType { carro, moto }

enum FuelType { flex, gasolina, etanol, diesel, eletrico }

/// Uma peça e o que ela custa por quilômetro rodado.
///
/// O raciocínio é o da planilha: **preço real da peça ÷ quilômetros que ela
/// dura**. Óleo e filtro custam R$ 200 e duram 10 000 km, então cada quilômetro
/// consome R$ 0,02. Nunca uma fração do ganho da rota.
class MaintenancePart {
  const MaintenancePart({
    required this.name,
    this.price,
    this.lifeKm,
    this.quantity = 1,
    this.fixedRate,
  });

  final String name;

  /// Preço de **uma** peça. O carro que gasta quatro pneus de uma vez informa
  /// 500 aqui e 4 em [quantity], não 2000 — ver [quantity].
  final double? price;

  /// Quantos quilômetros a peça dura.
  final double? lifeKm;

  /// Quantas peças o veículo troca de uma vez.
  ///
  /// Existe por causa do `*4` que a planilha esconde dentro da fórmula de pneu
  /// e freio (`=(X11/Y11)*4`): são as quatro rodas. Sem este campo, "pneu de
  /// R$ 500" provisionaria R$ 0,01/km em vez dos R$ 0,04/km corretos.
  final int quantity;

  /// Taxa em R$/km informada direto, sem preço nem vida útil.
  ///
  /// É a "P. Geral" da planilha (`W14 = 0,03`): a folga para o que não vale a
  /// pena detalhar. Quando presente, [price] e [lifeKm] são ignorados.
  final double? fixedRate;

  MaintenancePart copyWith({
    String? name,
    double? price,
    double? lifeKm,
    int? quantity,
    double? fixedRate,
    bool clearPrice = false,
    bool clearLifeKm = false,
    bool clearFixedRate = false,
  }) {
    return MaintenancePart(
      name: name ?? this.name,
      price: clearPrice ? null : (price ?? this.price),
      lifeKm: clearLifeKm ? null : (lifeKm ?? this.lifeKm),
      quantity: quantity ?? this.quantity,
      fixedRate: clearFixedRate ? null : (fixedRate ?? this.fixedRate),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'lifeKm': lifeKm,
    'quantity': quantity,
    'fixedRate': fixedRate,
  };

  factory MaintenancePart.fromMap(Map<String, dynamic> map) {
    return MaintenancePart(
      name: map['name'] as String? ?? '',
      price: readDouble(map['price']),
      lifeKm: readDouble(map['lifeKm']),
      // Documento gravado antes deste campo existir tem uma peça só.
      quantity: readInt(map['quantity']) ?? 1,
      fixedRate: readDouble(map['fixedRate']),
    );
  }
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.type,
    required this.brandCode,
    required this.brandName,
    required this.modelCode,
    required this.modelName,
    this.yearCode,
    this.year,
    this.nickname,
    required this.fuel,
    this.fuelPrice,
    this.consumption,
    this.imageUrl,
    this.photoBase64,
    this.parts = const [],
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final VehicleType type;

  /// Marca e modelo como a FIPE devolve, sem tratamento: `brandName` chega
  /// `"VW - VolksWagen"`. Quem precisa do rótulo limpo usa [brandLabel]; quem
  /// precisa do nome para a URL da imagem usa `Utils/carImage.dart`.
  final String brandCode;
  final String brandName;
  final String modelCode;
  final String modelName;

  final String? yearCode;
  final int? year;

  /// Como o dono chama este veículo. Serve para diferenciar dois carros na
  /// hora de trocar o ativo.
  final String? nickname;

  final FuelType fuel;

  /// R$ por litro. Entra na conta: `fuelPrice ÷ consumption` é o R$/km do
  /// combustível.
  final double? fuelPrice;

  /// km/l. É o "KM" da linha Gasolina da planilha.
  final double? consumption;

  /// URL do render da imagin.studio. **Só a URL** — a licença deles proíbe
  /// baixar, cachear e modificar os bytes.
  final String? imageUrl;

  /// Foto tirada pelo dono, em base64. Vence [imageUrl] quando existe.
  final String? photoBase64;

  final List<MaintenancePart> parts;

  final String createdAt;
  final String? updatedAt;

  bool get hasOwnPhoto => photoBase64 != null && photoBase64!.isNotEmpty;

  /// O que mostrar na lista: o apelido quando há, o modelo quando não.
  String get displayName {
    final nick = nickname?.trim() ?? '';
    return nick.isEmpty ? modelName : nick;
  }

  /// `"Fiat Fiorino Endurance 1.4 · 2020"`.
  String get subtitle {
    final brand = brandLabel(brandName);
    final base = brand.isEmpty ? modelName : '$brand $modelName';
    return year == null ? base : '$base · $year';
  }

  /// Tira o prefixo de sigla que a FIPE usa em algumas marcas:
  /// `"GM - Chevrolet"` vira `"Chevrolet"`, `"Fiat"` continua `"Fiat"`.
  static String brandLabel(String raw) {
    final parts = raw.split(' - ');
    return (parts.length > 1 ? parts.last : raw).trim();
  }

  Vehicle copyWith({
    VehicleType? type,
    String? brandCode,
    String? brandName,
    String? modelCode,
    String? modelName,
    String? yearCode,
    int? year,
    String? nickname,
    FuelType? fuel,
    double? fuelPrice,
    double? consumption,
    String? imageUrl,
    String? photoBase64,
    List<MaintenancePart>? parts,
    String? updatedAt,
    bool clearImageUrl = false,
    bool clearPhoto = false,
  }) {
    return Vehicle(
      id: id,
      type: type ?? this.type,
      brandCode: brandCode ?? this.brandCode,
      brandName: brandName ?? this.brandName,
      modelCode: modelCode ?? this.modelCode,
      modelName: modelName ?? this.modelName,
      yearCode: yearCode ?? this.yearCode,
      year: year ?? this.year,
      nickname: nickname ?? this.nickname,
      fuel: fuel ?? this.fuel,
      fuelPrice: fuelPrice ?? this.fuelPrice,
      consumption: consumption ?? this.consumption,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      photoBase64: clearPhoto ? null : (photoBase64 ?? this.photoBase64),
      parts: parts ?? this.parts,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    // Enum como string bare, igual a `NewRouteModal`. Renomear um valor do
    // enum quebra os documentos já gravados: mude os dois lados juntos.
    'type': type.name,
    'brandCode': brandCode,
    'brandName': brandName,
    'modelCode': modelCode,
    'modelName': modelName,
    'yearCode': yearCode,
    'year': year,
    'nickname': nickname,
    'fuel': fuel.name,
    'fuelPrice': fuelPrice,
    'consumption': consumption,
    'imageUrl': imageUrl,
    'photoBase64': photoBase64,
    'parts': parts.map((p) => p.toMap()).toList(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: map['id'] as String? ?? '',
      type: readEnum(VehicleType.values, map['type'], VehicleType.carro),
      brandCode: map['brandCode'] as String? ?? '',
      brandName: map['brandName'] as String? ?? '',
      modelCode: map['modelCode'] as String? ?? '',
      modelName: map['modelName'] as String? ?? '',
      yearCode: map['yearCode'] as String?,
      year: readInt(map['year']),
      nickname: map['nickname'] as String?,
      fuel: readEnum(FuelType.values, map['fuel'], FuelType.flex),
      fuelPrice: readDouble(map['fuelPrice']),
      consumption: readDouble(map['consumption']),
      imageUrl: map['imageUrl'] as String?,
      photoBase64: map['photoBase64'] as String?,
      parts: (map['parts'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((p) => MaintenancePart.fromMap(Map<String, dynamic>.from(p)))
              .toList() ??
          const [],
      createdAt: map['createdAt'] as String? ?? '',
      updatedAt: map['updatedAt'] as String?,
    );
  }

  /// As peças da planilha, já preenchidas.
  ///
  /// Cadastrar um veículo sem tocar em nada reproduz exatamente o bloco
  /// `V8:Z15` de `Entregas.xlsx` — R$ 0,1193/km de peças. Tudo é editável, e o
  /// formulário deixa somar peça nova (correia, embreagem) sem mudar o modelo.
  static List<MaintenancePart> defaultParts(VehicleType type) {
    // Moto tem duas rodas: dois pneus e dois jogos de freio por troca.
    final wheels = type == VehicleType.moto ? 2 : 4;

    return [
      const MaintenancePart(name: 'Óleo', price: 200, lifeKm: 10000),
      MaintenancePart(
        name: 'Pneu',
        price: 500,
        lifeKm: 50000,
        quantity: wheels,
      ),
      const MaintenancePart(name: 'Bateria', price: 800, lifeKm: 60000),
      MaintenancePart(
        name: 'Freio',
        price: 200,
        lifeKm: 50000,
        quantity: wheels,
      ),
      // A folga da planilha para o que não vale a pena detalhar.
      const MaintenancePart(name: 'Geral', fixedRate: 0.03),
    ];
  }
}
