/// Um abastecimento: o dinheiro que saiu do bolso na bomba.
///
/// Não confundir com a provisão de combustível da rota. Aquela é **estimativa**
/// por quilômetro rodado, congelada dentro do lucro; isto aqui é o gasto real,
/// na data em que aconteceu. Somar os dois contaria a gasolina duas vezes — ver
/// `docs/specs/abastecimento.md`.
library;

import 'package:iter/Utils/dated.dart';
import 'package:iter/Utils/mapRead.dart';
import 'package:iter/model/vehicle.dart';

/// O que foi para o tanque.
///
/// Não tem `flex`, ao contrário de [FuelType]: flex é a capacidade do carro, não
/// o líquido da bomba. Quem abastece põe gasolina **ou** etanol, e é justamente
/// por o tipo não permitir "flex" que a tela é obrigada a perguntar.
enum SupplyFuel {
  gasolina,
  etanol,
  diesel,
  eletrico;

  /// O combustível que o veículo obriga, ou `null` quando só o motorista sabe.
  ///
  /// `null` é o tipo dizendo **"pergunte"**: é dele que o seletor da tela
  /// depende, e não de um `if (vehicle.fuel == FuelType.flex)` espalhado pelo
  /// formulário.
  static SupplyFuel? fromVehicle(FuelType? fuel) => switch (fuel) {
    FuelType.gasolina => SupplyFuel.gasolina,
    FuelType.etanol => SupplyFuel.etanol,
    FuelType.diesel => SupplyFuel.diesel,
    FuelType.eletrico => SupplyFuel.eletrico,
    FuelType.flex => null,
    null => null,
  };

  String get label => switch (this) {
    SupplyFuel.gasolina => 'Gasolina',
    SupplyFuel.etanol => 'Etanol',
    SupplyFuel.diesel => 'Diesel',
    SupplyFuel.eletrico => 'Elétrico',
  };
}

/// Um posto, como o OpenStreetMap o conhece.
class FuelStation {
  const FuelStation({
    required this.id,
    required this.name,
    this.brand,
    required this.lat,
    required this.lng,
  });

  /// Id do OSM com o tipo junto: `way-123456`, `node-98765`.
  ///
  /// Vem da fonte, então dois usuários no mesmo posto escrevem no mesmo
  /// documento de `gastop` sem combinar nada.
  final String id;

  final String name;
  final String? brand;
  final double lat;
  final double lng;

  /// Muito posto no OSM não tem `name`, só `brand`.
  String get label {
    if (name.trim().isNotEmpty) return name.trim();

    final brandName = brand?.trim() ?? '';
    return brandName.isEmpty ? 'Posto sem nome' : brandName;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'brand': brand,
    'lat': lat,
    'lng': lng,
  };

  factory FuelStation.fromMap(Map<String, dynamic> map) => FuelStation(
    id: map['id'] as String? ?? '',
    name: map['name'] as String? ?? '',
    brand: map['brand'] as String?,
    lat: readDouble(map['lat']) ?? 0,
    lng: readDouble(map['lng']) ?? 0,
  );
}

class Supply implements Dated {
  const Supply({
    required this.id,
    this.vehicleId,
    required this.value,
    this.liters,
    this.fuel = SupplyFuel.gasolina,
    this.odometer,
    this.station,
    this.lat,
    this.lng,
    required this.date,
    required this.createdAt,
  });

  @override
  final String id;

  /// Qual veículo foi abastecido. `null` quando não havia nenhum cadastrado.
  final String? vehicleId;

  /// Quanto saiu do bolso. Único campo obrigatório do formulário.
  final double value;

  /// Litros da bomba. Opcional — e sem ele não há preço do litro para
  /// conferir, nem preço para relatar ao posto.
  final double? liters;

  final SupplyFuel fuel;

  /// KM do painel no momento do abastecimento.
  ///
  /// É a semente do consumo real: com o hodômetro de dois abastecimentos
  /// seguidos e os litros do segundo sai o km/l de verdade — o dado que
  /// nenhuma API brasileira fornece.
  final double? odometer;

  /// `null` quando não deu para saber o posto ou quando foi digitado à mão.
  final FuelStation? station;

  /// Onde o usuário estava. Serve para reconstruir o contexto depois.
  final double? lat;
  final double? lng;

  /// Data do abastecimento — pode ser anterior a [createdAt], para quem
  /// registra depois.
  @override
  final String date;

  final String createdAt;

  /// O número que ele confere com o painel da bomba.
  ///
  /// **Derivado, nunca gravado**: `value / liters` é uma linha, e valor
  /// derivado que se grava um dia discorda da origem. `null` — não zero e nunca
  /// infinito — quando não há litros.
  double? get pricePerLiter {
    final l = liters;
    if (l == null || l <= 0) return null;
    return value / l;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'vehicleId': vehicleId,
    'value': value,
    'liters': liters,
    'fuel': fuel.name,
    'odometer': odometer,
    'station': station?.toMap(),
    'lat': lat,
    'lng': lng,
    'date': date,
    'createdAt': createdAt,
  };

  factory Supply.fromMap(Map<String, dynamic> map) {
    final rawStation = map['station'];

    return Supply(
      id: map['id'] as String? ?? '',
      vehicleId: map['vehicleId'] as String?,
      value: readDouble(map['value']) ?? 0,
      liters: readDouble(map['liters']),
      fuel: readEnum(SupplyFuel.values, map['fuel'], SupplyFuel.gasolina),
      odometer: readDouble(map['odometer']),
      // `is Map` segura um documento corrompido sem derrubar o abastecimento
      // inteiro — o posto é o pedaço mais frágil, porque vem de fora.
      station: rawStation is Map
          ? FuelStation.fromMap(Map<String, dynamic>.from(rawStation))
          : null,
      lat: readDouble(map['lat']),
      lng: readDouble(map['lng']),
      date: map['date'] as String? ?? '',
      createdAt: map['createdAt'] as String? ?? '',
    );
  }
}
