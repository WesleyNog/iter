/// Uma manutenção: peça trocada ou consertada, e quanto custou.
///
/// Como o abastecimento, é **gasto real do bolso** — não se soma nem se subtrai
/// do lucro da rota, que já cobra peças como provisão. Ver
/// `docs/specs/manutencao.md`.
library;

import 'package:iter/Utils/dated.dart';
import 'package:iter/Utils/mapRead.dart';

/// O que passou pela manutenção.
///
/// Lista fixa, como a de bairros: o entregador escolhe, não digita. Digitar
/// deixaria "pneu", "Pneu" e "pneus" como três coisas diferentes, e aí nenhuma
/// delas conseguiria corrigir o preço no cadastro do veículo.
enum MaintenanceItem {
  pneu,
  motor,
  oleoMotor,
  oleoFreio,
  pastilhaFreio,
  bateria,
  amortecedor,
  embreagem,
  correia,
  filtros,
  revisao,
  funilaria,
  outros;

  String get label => switch (this) {
    MaintenanceItem.pneu => 'Pneu',
    MaintenanceItem.motor => 'Motor',
    MaintenanceItem.oleoMotor => 'Óleo do motor',
    MaintenanceItem.oleoFreio => 'Óleo de freio',
    MaintenanceItem.pastilhaFreio => 'Pastilha de freio',
    MaintenanceItem.bateria => 'Bateria',
    MaintenanceItem.amortecedor => 'Amortecedor',
    MaintenanceItem.embreagem => 'Embreagem',
    MaintenanceItem.correia => 'Correia',
    MaintenanceItem.filtros => 'Filtros',
    MaintenanceItem.revisao => 'Revisão',
    MaintenanceItem.funilaria => 'Funilaria',
    MaintenanceItem.outros => 'Outros',
  };

  /// Nome da peça correspondente no cadastro do veículo, ou `null` quando não
  /// há correspondência.
  ///
  /// É o que permite uma substituição corrigir o preço que hoje é chute. Os
  /// nomes batem com [Vehicle.defaultParts] — há teste garantindo isso, porque
  /// renomear uma peça padrão sem atualizar este mapa faria a oferta de
  /// correção sumir **em silêncio**.
  ///
  /// `null` na maioria de propósito: funilaria e revisão não são peça de lista
  /// nenhuma, e óleo de freio não é item provisionado.
  String? get vehiclePartName => switch (this) {
    MaintenanceItem.pneu => 'Pneu',
    MaintenanceItem.oleoMotor => 'Óleo',
    MaintenanceItem.pastilhaFreio => 'Freio',
    MaintenanceItem.bateria => 'Bateria',
    _ => null,
  };
}

/// O que foi feito com o item.
///
/// A distinção existe para o preço: consertar um pneu por R$ 80 não é o preço
/// de um pneu novo, e só a **substituição** pode corrigir o cadastro.
enum MaintenanceAction {
  reparo,
  substituicao;

  String get label => switch (this) {
    MaintenanceAction.reparo => 'Reparo',
    MaintenanceAction.substituicao => 'Substituição',
  };
}

class Maintenance implements Dated {
  const Maintenance({
    required this.id,
    this.vehicleId,
    this.item = MaintenanceItem.outros,
    this.action = MaintenanceAction.reparo,
    required this.value,
    this.workshop,
    this.description,
    this.odometer,
    required this.date,
    required this.createdAt,
  });

  @override
  final String id;

  /// Qual veículo passou pela manutenção. `null` quando não havia nenhum
  /// cadastrado.
  final String? vehicleId;

  final MaintenanceItem item;
  final MaintenanceAction action;

  /// Quanto saiu do bolso. Único campo obrigatório do formulário.
  final double value;

  /// Oficina, texto livre. Não há lista fixa nem coleção global: parceria com
  /// oficina é ideia de futuro, não desta entrega.
  final String? workshop;

  final String? description;

  /// KM do painel. Semente do lembrete "faltam 2.300 km para o óleo" — o
  /// veículo já sabe que o óleo dura 10.000 km; faltava saber quando foi a
  /// última troca.
  final double? odometer;

  @override
  final String date;
  final String createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'vehicleId': vehicleId,
    'item': item.name,
    'action': action.name,
    'value': value,
    'workshop': workshop,
    'description': description,
    'odometer': odometer,
    'date': date,
    'createdAt': createdAt,
  };

  factory Maintenance.fromMap(Map<String, dynamic> map) {
    return Maintenance(
      id: map['id'] as String? ?? '',
      vehicleId: map['vehicleId'] as String?,
      item: readEnum(MaintenanceItem.values, map['item'], MaintenanceItem.outros),
      // Padrão `reparo` e não `substituicao` porque é o conservador: reparo
      // nunca dispara a oferta de corrigir o preço da peça, então um documento
      // estranho não consegue mexer no cadastro do veículo.
      action: readEnum(
        MaintenanceAction.values,
        map['action'],
        MaintenanceAction.reparo,
      ),
      value: readDouble(map['value']) ?? 0,
      workshop: map['workshop'] as String?,
      description: map['description'] as String?,
      odometer: readDouble(map['odometer']),
      date: map['date'] as String? ?? '',
      createdAt: map['createdAt'] as String? ?? '',
    );
  }
}
