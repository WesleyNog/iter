import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/vehicle.dart';

Maintenance _maintenance({
  String? vehicleId = 'v1',
  MaintenanceItem item = MaintenanceItem.pneu,
  MaintenanceAction action = MaintenanceAction.substituicao,
  double value = 2400,
  String? workshop = 'Auto Center do Zé',
  String? description = 'Quatro pneus novos',
  double? odometer = 128500,
}) {
  return Maintenance(
    id: 'm1',
    vehicleId: vehicleId,
    item: item,
    action: action,
    value: value,
    workshop: workshop,
    description: description,
    odometer: odometer,
    date: '2026-08-06T10:00:00.000',
    createdAt: '2026-08-06T10:05:00.000',
  );
}

void main() {
  group('ida e volta', () {
    test('preserva todos os campos', () {
      final back = Maintenance.fromMap(_maintenance().toMap());

      expect(back.id, 'm1');
      expect(back.vehicleId, 'v1');
      expect(back.item, MaintenanceItem.pneu);
      expect(back.action, MaintenanceAction.substituicao);
      expect(back.value, 2400);
      expect(back.workshop, 'Auto Center do Zé');
      expect(back.description, 'Quatro pneus novos');
      expect(back.odometer, 128500);
      expect(back.date, '2026-08-06T10:00:00.000');
      expect(back.createdAt, '2026-08-06T10:05:00.000');
    });

    test('enums vão como string bare', () {
      final map = _maintenance(
        item: MaintenanceItem.oleoMotor,
        action: MaintenanceAction.reparo,
      ).toMap();

      expect(map['item'], 'oleoMotor');
      expect(map['action'], 'reparo');
    });

    test('campos opcionais ausentes voltam nulos', () {
      final back = Maintenance.fromMap(
        _maintenance(
          vehicleId: null,
          workshop: null,
          description: null,
          odometer: null,
        ).toMap(),
      );

      expect(back.vehicleId, isNull);
      expect(back.workshop, isNull);
      expect(back.description, isNull);
      expect(back.odometer, isNull);
    });
  });

  group('leitura defensiva', () {
    test('mapa vazio não lança', () {
      expect(() => Maintenance.fromMap(const {}), returnsNormally);
      expect(Maintenance.fromMap(const {}).value, 0);
    });

    test('item desconhecido cai em Outros, não derruba a lista', () {
      // Um documento gravado por versão futura não pode quebrar o extrato.
      final m = Maintenance.fromMap(const {
        'id': 'm1',
        'item': 'turbina',
        'value': 100,
        'date': '2026-08-06T10:00:00.000',
      });

      expect(m.item, MaintenanceItem.outros);
    });

    test('ação desconhecida cai em Reparo', () {
      // O padrão mais conservador: reparo **não** oferece corrigir o preço da
      // peça, então um documento estranho nunca dispara essa oferta.
      final m = Maintenance.fromMap(const {
        'id': 'm1',
        'action': 'sei-la',
        'value': 100,
        'date': '2026-08-06T10:00:00.000',
      });

      expect(m.action, MaintenanceAction.reparo);
    });

    test('inteiro do Firestore vira double', () {
      final m = Maintenance.fromMap(const {
        'id': 'm1',
        'value': 2400,
        'odometer': 128500,
        'date': '2026-08-06T10:00:00.000',
      });

      expect(m.value, isA<double>());
      expect(m.odometer, isA<double>());
    });
  });

  group('MaintenanceItem', () {
    test('os treze itens têm rótulo em pt-BR e nenhum repete', () {
      final labels = MaintenanceItem.values.map((i) => i.label).toList();

      expect(MaintenanceItem.values.length, 13);
      expect(labels.toSet().length, 13);
      expect(labels, everyElement(isNotEmpty));
    });

    test('os rótulos são os que o usuário pediu', () {
      expect(MaintenanceItem.pneu.label, 'Pneu');
      expect(MaintenanceItem.oleoMotor.label, 'Óleo do motor');
      expect(MaintenanceItem.oleoFreio.label, 'Óleo de freio');
      expect(MaintenanceItem.pastilhaFreio.label, 'Pastilha de freio');
      expect(MaintenanceItem.funilaria.label, 'Funilaria');
      expect(MaintenanceItem.outros.label, 'Outros');
    });

    test('quatro itens mapeiam para peças do cadastro do veículo', () {
      expect(MaintenanceItem.pneu.vehiclePartName, 'Pneu');
      expect(MaintenanceItem.oleoMotor.vehiclePartName, 'Óleo');
      expect(MaintenanceItem.pastilhaFreio.vehiclePartName, 'Freio');
      expect(MaintenanceItem.bateria.vehiclePartName, 'Bateria');
    });

    test('os que não têm peça correspondente devolvem null', () {
      // Sem correspondência não há preço a corrigir — funilaria e revisão não
      // são peça de nenhuma lista.
      for (final item in [
        MaintenanceItem.motor,
        MaintenanceItem.oleoFreio,
        MaintenanceItem.amortecedor,
        MaintenanceItem.embreagem,
        MaintenanceItem.correia,
        MaintenanceItem.filtros,
        MaintenanceItem.revisao,
        MaintenanceItem.funilaria,
        MaintenanceItem.outros,
      ]) {
        expect(item.vehiclePartName, isNull, reason: item.name);
      }
    });

    test('todo nome mapeado existe nas peças padrão do veículo', () {
      // Se alguém renomear uma peça padrão sem atualizar o mapa, a oferta de
      // correção deixaria de aparecer em silêncio. Este teste denuncia.
      final padrao = Vehicle.defaultParts(VehicleType.carro)
          .map((p) => p.name)
          .toSet();

      final mapeados = MaintenanceItem.values
          .map((i) => i.vehiclePartName)
          .whereType<String>();

      for (final nome in mapeados) {
        expect(padrao, contains(nome));
      }
    });
  });

  group('MaintenanceAction', () {
    test('são duas, com rótulo', () {
      expect(MaintenanceAction.values.length, 2);
      expect(MaintenanceAction.reparo.label, 'Reparo');
      expect(MaintenanceAction.substituicao.label, 'Substituição');
    });
  });
}
