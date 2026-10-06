import 'package:flutter_test/flutter_test.dart';
import 'package:iter/controller/stationController.dart';
import 'package:iter/controller/supplyController.dart';
import 'package:iter/model/supply.dart';

Supply _supply({
  String id = 's1',
  String date = '2026-08-05T21:00:00.000',
  double value = 250,
  double? liters = 40,
  SupplyFuel fuel = SupplyFuel.gasolina,
  FuelStation? station,
}) {
  return Supply(
    id: id,
    value: value,
    liters: liters,
    fuel: fuel,
    station: station,
    date: date,
    createdAt: date,
  );
}

const _fromSource = FuelStation(
  id: 'way-243218168',
  name: 'Posto Prainha',
  brand: 'Shell',
  lat: -3.7238,
  lng: -38.5197,
);

/// Posto digitado à mão: sem id, porque não veio do OpenStreetMap.
const _typedByHand = FuelStation(id: '', name: 'Posto do Zé', lat: 0, lng: 0);

void main() {
  group('sortByDate — do mais recente para o mais antigo', () {
    test('ordena pela data do abastecimento', () {
      final sorted = SupplyController.sortByDate([
        _supply(id: 'meio', date: '2026-08-03T10:00:00.000'),
        _supply(id: 'novo', date: '2026-08-05T10:00:00.000'),
        _supply(id: 'velho', date: '2026-08-01T10:00:00.000'),
      ]);

      expect(sorted.map((s) => s.id), ['novo', 'meio', 'velho']);
    });

    test('ISO ordena como texto na mesma ordem que como data', () {
      // É por isso que `date` é ISO e não `dd/MM/yyyy` — aquele formato põe
      // 02/01/2027 antes de 31/12/2026, a armadilha que a lista de rotas teve
      // de contornar ordenando em memória.
      final sorted = SupplyController.sortByDate([
        _supply(id: 'dez', date: '2026-12-31T10:00:00.000'),
        _supply(id: 'jan', date: '2027-01-02T10:00:00.000'),
      ]);

      expect(sorted.first.id, 'jan');
    });

    test('data vazia vai para o fim em vez de lançar', () {
      final sorted = SupplyController.sortByDate([
        _supply(id: 'corrompido', date: ''),
        _supply(id: 'ok', date: '2026-08-01T10:00:00.000'),
      ]);

      expect(sorted.map((s) => s.id), ['ok', 'corrompido']);
    });

    test('empate desempata pelo id, para a ordem não dançar', () {
      final a = SupplyController.sortByDate([
        _supply(id: 'z', date: '2026-08-01T10:00:00.000'),
        _supply(id: 'a', date: '2026-08-01T10:00:00.000'),
      ]);

      expect(a.map((s) => s.id), ['a', 'z']);
    });

    test('não altera a lista recebida', () {
      final original = [
        _supply(id: 'velho', date: '2026-08-01T10:00:00.000'),
        _supply(id: 'novo', date: '2026-08-05T10:00:00.000'),
      ];
      SupplyController.sortByDate(original);

      expect(original.map((s) => s.id), ['velho', 'novo']);
    });
  });

  group('canReport — o que pode sujar a coleção compartilhada', () {
    test('posto da fonte com preço calculável pode relatar', () {
      expect(
        StationController.canReport(_supply(station: _fromSource)),
        isTrue,
      );
    });

    test('sem posto nenhum não relata', () {
      expect(StationController.canReport(_supply()), isFalse);
    });

    test('posto digitado à mão não relata', () {
      // Sem id do OSM, "Posto do Zé" viraria dez documentos que ninguém
      // consegue reconciliar como sendo o mesmo lugar.
      expect(
        StationController.canReport(_supply(station: _typedByHand)),
        isFalse,
      );
    });

    test('sem litros não relata — não há preço do litro', () {
      expect(
        StationController.canReport(
          _supply(station: _fromSource, liters: null),
        ),
        isFalse,
      );
    });

    test('litros zero não relata, e não vira divisão por zero', () {
      expect(
        StationController.canReport(_supply(station: _fromSource, liters: 0)),
        isFalse,
      );
    });

    test('valor zero não relata', () {
      expect(
        StationController.canReport(_supply(station: _fromSource, value: 0)),
        isFalse,
      );
    });

    test('sem data legível não relata — preço sem quando não é relato', () {
      // `pricedAt` e `precos.at` saem da data do abastecimento; sem ela, a
      // idade na tela seria inventada.
      expect(
        StationController.canReport(_supply(station: _fromSource, date: '')),
        isFalse,
      );
    });
  });

  group('o relato carrega a data do abastecimento, não a do registro', () {
    // Abasteceu na segunda às 8h, registrou na quarta à noite.
    final segunda = _supply(
      date: '2026-10-05T12:00:00.000',
      station: _fromSource,
      fuel: SupplyFuel.etanol,
    );

    test('pricedAt do combustível é a data do abastecimento', () {
      final fields = StationController.stationFields(
        segunda,
        'u1',
        now: DateTime(2026, 10, 7, 21),
      );

      expect(fields['prices'], {'etanol': 6.25});
      expect(fields['pricedAt'], {'etanol': '2026-10-05T12:00:00.000'});
    });

    test('updatedAt continua sendo quando o documento foi escrito', () {
      final fields = StationController.stationFields(
        segunda,
        'u1',
        now: DateTime(2026, 10, 7, 21),
      );

      expect(fields['updatedAt'], DateTime(2026, 10, 7, 21).toIso8601String());
      // A regra de segurança exige que seja o próprio autor.
      expect(fields['updatedBy'], 'u1');
    });

    test('o relato imutável também leva a data do abastecimento', () {
      final report = StationController.priceReport(segunda, 'u1');

      expect(report, {
        'price': 6.25,
        'fuel': 'etanol',
        'uid': 'u1',
        'at': '2026-10-05T12:00:00.000',
      });
    });

    test('sem trocar o preço, o posto é escrito sem prices nem pricedAt', () {
      final fields = StationController.stationFields(
        segunda,
        'u1',
        now: DateTime(2026, 10, 7, 21),
        withPrice: false,
      );

      expect(fields.containsKey('prices'), isFalse);
      expect(fields.containsKey('pricedAt'), isFalse);
      expect(fields['id'], 'way-243218168');
    });
  });

  group('shouldReplacePrice — preço velho não apaga preço novo', () {
    final terca = DateTime(2026, 10, 6, 15);

    test('sem preço guardado, troca', () {
      expect(
        StationController.shouldReplacePrice(stored: null, reported: terca),
        isTrue,
      );
    });

    test('relato mais novo troca', () {
      expect(
        StationController.shouldReplacePrice(
          stored: DateTime(2026, 10, 5, 12),
          reported: terca,
        ),
        isTrue,
      );
    });

    test('relato mais velho não troca', () {
      // O de segunda, registrado na quarta, não apaga o de terça.
      expect(
        StationController.shouldReplacePrice(
          stored: terca,
          reported: DateTime(2026, 10, 5, 12),
        ),
        isFalse,
      );
    });

    test('mesmo instante não troca — não há o que ganhar reescrevendo', () {
      expect(
        StationController.shouldReplacePrice(stored: terca, reported: terca),
        isFalse,
      );
    });
  });

  group('reportsPastDay — qual caminho o relato toma', () {
    final quarta = DateTime(2026, 10, 7, 21);

    test('abastecimento de hoje vai pelo batch, que funciona sem sinal', () {
      final hoje = _supply(date: '2026-10-07T08:00:00.000');

      expect(StationController.reportsPastDay(hoje, now: quarta), isFalse);
    });

    test('abastecimento de outro dia vai pela transação', () {
      final segunda = _supply(date: '2026-10-05T12:00:00.000');

      expect(StationController.reportsPastDay(segunda, now: quarta), isTrue);
    });

    test('ontem às 23h59 já é outro dia', () {
      final ontem = _supply(date: '2026-10-06T23:59:00.000');

      expect(StationController.reportsPastDay(ontem, now: quarta), isTrue);
    });

    test('data ilegível vai pela transação — é o caminho que compara', () {
      expect(
        StationController.reportsPastDay(_supply(date: ''), now: quarta),
        isTrue,
      );
    });
  });
}
