import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/stationFlag.dart';
import 'package:iter/model/supply.dart';

FuelStation _station({String name = '', String? brand}) => FuelStation(
  id: 'node-1',
  name: name,
  brand: brand,
  lat: -3.73,
  lng: -38.52,
);

void main() {
  group('brand reconhecida decide', () {
    test('as quatro bandeiras com logo', () {
      expect(flagOf(_station(brand: 'BR')), StationFlag.br);
      expect(flagOf(_station(brand: 'Shell')), StationFlag.shell);
      expect(flagOf(_station(brand: 'Ipiranga')), StationFlag.ipiranga);
      expect(flagOf(_station(brand: 'Ale')), StationFlag.ale);
    });

    test('Petrobras é a BR, com ou sem acento', () {
      // Medido na RMF: 72 postos com `BR` e 6 com `Petrobras`. É a mesma placa.
      expect(flagOf(_station(brand: 'Petrobras')), StationFlag.br);
      expect(flagOf(_station(brand: 'Petrobrás')), StationFlag.br);
    });

    test('caixa não importa', () {
      expect(flagOf(_station(brand: 'ALE')), StationFlag.ale);
      expect(flagOf(_station(brand: 'shell')), StationFlag.shell);
      expect(flagOf(_station(brand: 'Alesat')), StationFlag.ale);
    });

    test('a bandeira dentro de um nome maior, como palavra', () {
      expect(flagOf(_station(brand: 'BR Distribuidora')), StationFlag.br);
    });

    test('vence o nome', () {
      expect(
        flagOf(_station(name: 'Posto Ipiranga Centro', brand: 'Shell')),
        StationFlag.shell,
      );
    });
  });

  group('brand presente mas desconhecida', () {
    test('é sem bandeira, mesmo que o nome cite outra', () {
      // A tag de bandeira é quem afirma a bandeira. "Posto Shell" com
      // `brand=SP` é dado contraditório, e o desenho neutro é o erro que não
      // afirma nada.
      expect(
        flagOf(_station(name: 'Posto Shell', brand: 'SP')),
        StationFlag.semBandeira,
      );
      expect(flagOf(_station(brand: 'OM')), StationFlag.semBandeira);
    });

    test('brand só com espaço conta como ausente', () {
      expect(
        flagOf(_station(name: 'Posto Shell', brand: '  ')),
        StationFlag.shell,
      );
    });
  });

  group('sem brand, o nome', () {
    test('cita a bandeira como palavra inteira', () {
      // Os 8 postos da RMF que só ganham logo por aqui são deste formato.
      expect(flagOf(_station(name: 'Posto BR (Bonsucesso)')), StationFlag.br);
      expect(
        flagOf(_station(name: 'Posto Shell (Granja Lisboa)')),
        StationFlag.shell,
      );
      expect(flagOf(_station(name: 'Ipiranga')), StationFlag.ipiranga);
    });

    test('trecho de palavra não conta', () {
      // `contains` acharia "br" dentro de "Brasil" e "ale" dentro de "Vale".
      expect(flagOf(_station(name: 'Posto Brasil')), StationFlag.semBandeira);
      expect(
        flagOf(_station(name: 'Posto Vale Verde')),
        StationFlag.semBandeira,
      );
      expect(flagOf(_station(name: 'Posto Iparana')), StationFlag.semBandeira);
    });

    test('nome sem bandeira nenhuma', () {
      expect(flagOf(_station(name: 'Posto Del Rey')), StationFlag.semBandeira);
    });

    test('sem nome e sem brand', () {
      expect(flagOf(_station()), StationFlag.semBandeira);
    });
  });

  test('todo logo aponta para um arquivo que existe', () {
    // Um asset renomeado não falha na compilação: lança dentro do
    // `Image.asset`, na tela, no meio da lista de postos.
    for (final flag in StationFlag.values) {
      expect(File(flag.asset).existsSync(), isTrue, reason: flag.asset);
    }
  });

  test('só a BR preenche o círculo', () {
    // As outras perdem a forma quando cortadas: a concha, o oval da ALE.
    expect(StationFlag.values.where((f) => f.fillsCircle), [StationFlag.br]);
  });
}
