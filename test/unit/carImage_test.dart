import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/carImage.dart';
import 'package:iter/model/vehicle.dart';

void main() {
  group('imaginMake — nome da FIPE vira o que a CDN entende', () {
    test('tira a sigla que a FIPE prega na frente', () {
      expect(imaginMake('GM - Chevrolet'), 'chevrolet');
      expect(imaginMake('VW - VolksWagen'), 'volkswagen');
    });

    test('marca sem sigla passa direto', () {
      expect(imaginMake('Fiat'), 'fiat');
      expect(imaginMake('Renault'), 'renault');
    });

    test('acento é removido, não escapado', () {
      expect(imaginMake('Citroën'), 'citroen');
    });

    test('espaço interno some', () {
      expect(imaginMake('Land Rover'), 'landrover');
    });

    test('vazio devolve null', () {
      expect(imaginMake(''), isNull);
      expect(imaginMake('   '), isNull);
    });
  });

  group('imaginModelFamily — versão da FIPE vira família', () {
    test('pega só a primeira palavra do nome longo da FIPE', () {
      expect(imaginModelFamily('Strada Adventure 1.8 mpi Flex CE'), 'strada');
      expect(imaginModelFamily('Fiorino Endurance 1.3 Flex 8V 2p'), 'fiorino');
      expect(imaginModelFamily('Saveiro Robust 1.6 Flex 8V CD'), 'saveiro');
    });

    test('modelo que já é alfanumérico é preservado', () {
      expect(imaginModelFamily('HB20 1.0 Comfort'), 'hb20');
    });

    test('modelo que começa com número é preservado', () {
      expect(imaginModelFamily('500 Cult 1.4 Flex 8V EVO'), '500');
      expect(imaginModelFamily('147 C/ CL'), '147');
    });

    test('pontuação colada some', () {
      expect(imaginModelFamily('Fiorino Furg.1.5/1.3'), 'fiorino');
    });

    test('vazio devolve null', () {
      expect(imaginModelFamily(''), isNull);
      expect(imaginModelFamily('  1.0  '), isNull);
    });
  });

  group('carImageUrl', () {
    test('monta a URL da CDN com marca e família', () {
      final url = carImageUrl(
        type: VehicleType.carro,
        brandName: 'Fiat',
        modelName: 'Fiorino Endurance 1.3 Flex 8V 2p',
      )!;

      expect(url, startsWith('https://cdn.imagin.studio/getimage?'));
      expect(url, contains('make=fiat'));
      expect(url, contains('modelFamily=fiorino'));
      expect(url, contains('customer=img'));
    });

    test('moto devolve null — a CDN não cobre e responde com um SUV', () {
      // Testado na API real: `honda/cg` volta com `found=true` resolvendo para
      // um Honda Pilot. Não pedir é melhor que pedir e receber o carro errado.
      expect(
        carImageUrl(
          type: VehicleType.moto,
          brandName: 'Honda',
          modelName: 'CG 160 Titan',
        ),
        isNull,
      );
    });

    test('marca ou modelo em branco devolve null', () {
      expect(
        carImageUrl(type: VehicleType.carro, brandName: '', modelName: 'Onix'),
        isNull,
      );
      expect(
        carImageUrl(type: VehicleType.carro, brandName: 'GM - Chevrolet', modelName: ''),
        isNull,
      );
    });

    test('largura entra na URL', () {
      final url = carImageUrl(
        type: VehicleType.carro,
        brandName: 'Fiat',
        modelName: 'Toro',
        width: 96,
      )!;

      expect(url, contains('width=96'));
    });

    test('o mesmo veículo sempre gera a mesma URL', () {
      // A URL é gravada no documento: se ela variasse, a imagem trocaria
      // sozinha entre uma abertura e outra.
      String url() => carImageUrl(
        type: VehicleType.carro,
        brandName: 'GM - Chevrolet',
        modelName: 'Onix Plus 1.0',
      )!;

      expect(url(), url());
    });
  });
}
