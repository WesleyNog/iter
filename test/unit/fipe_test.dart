import 'package:flutter_test/flutter_test.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/services/fipe.dart';

/// Trechos capturados da API real em 05/08/2026. As formas mudam de endpoint
/// para endpoint e é justamente isso que estes testes travam.
const _marcas = '''
[{"codigo":"1","nome":"Acura"},{"codigo":"21","nome":"Fiat"},
 {"codigo":"23","nome":"GM - Chevrolet"},{"codigo":"59","nome":"VW - VolksWagen"}]
''';

/// Repare no envelope e no `codigo` **inteiro** — em `/marcas` ele é string.
const _modelos = '''
{"modelos":[{"codigo":437,"nome":"147 C/ CL"},
            {"codigo":11376,"nome":"Fiorino Endurance 1.3 Flex 8V 2p"},
            {"codigo":9194,"nome":"Fiorino Endurance EVO 1.4 Flex 8V 2p"}],
 "anos":[{"codigo":"2020-1","nome":"2020 Gasolina"}]}
''';

const _anos = '''
[{"codigo":"2014-5","nome":"2014 Flex"},{"codigo":"2013-5","nome":"2013 Flex"}]
''';

void main() {
  group('parseFipeList — marcas e anos vêm como array cru', () {
    test('lê as marcas preservando código e nome', () {
      final brands = parseFipeList(_marcas)!;

      expect(brands.length, 4);
      expect(brands[1].code, '21');
      expect(brands[1].name, 'Fiat');
      expect(brands[3].name, 'VW - VolksWagen');
    });

    test('lê os anos', () {
      final years = parseFipeList(_anos)!;

      expect(years.first.code, '2014-5');
      expect(years.first.name, '2014 Flex');
    });

    test('array vazio é resposta válida, não erro', () {
      expect(parseFipeList('[]'), isEmpty);
    });

    test('corpo ilegível devolve null — "falhou" não é "não achou nada"', () {
      // A mesma lição do clima: colapsar erro em resultado vazio esconde a
      // falha, e a tela mostraria "nenhuma marca" em vez de "tente de novo".
      expect(parseFipeList('não é json'), isNull);
      expect(parseFipeList(''), isNull);
      expect(parseFipeList('{"erro":"x"}'), isNull);
    });

    test('item fora do formato é pulado sem derrubar a lista', () {
      final list = parseFipeList('[{"codigo":"1","nome":"Fiat"},{"x":1},"lixo"]')!;

      expect(list.length, 1);
      expect(list.first.name, 'Fiat');
    });
  });

  group('parseFipeModels — envelope com codigo inteiro', () {
    test('lê os modelos de dentro do envelope', () {
      final models = parseFipeModels(_modelos)!;

      expect(models.length, 3);
      expect(models[1].name, 'Fiorino Endurance 1.3 Flex 8V 2p');
    });

    test('código inteiro vira string sem lançar', () {
      // `/marcas` devolve "21" e `/modelos` devolve 11376: um `as String` aqui
      // derrubaria a lista de modelos inteira.
      final models = parseFipeModels(_modelos)!;

      expect(models[1].code, '11376');
      expect(models[1].code, isA<String>());
    });

    test('envelope sem a chave modelos devolve null', () {
      expect(parseFipeModels('{"anos":[]}'), isNull);
    });

    test('corpo ilegível devolve null', () {
      expect(parseFipeModels('não é json'), isNull);
      expect(parseFipeModels('[]'), isNull);
    });

    test('lista de modelos vazia é resposta válida', () {
      expect(parseFipeModels('{"modelos":[]}'), isEmpty);
    });
  });

  group('FipeItem', () {
    test('duas instâncias com o mesmo código são iguais', () {
      // O DropdownButton compara valores por igualdade; sem isto, reabrir a
      // tela de edição não marcaria o item já escolhido.
      expect(
        const FipeItem(code: '21', name: 'Fiat'),
        const FipeItem(code: '21', name: 'Fiat'),
      );
    });
  });

  group('caminhos da API', () {
    test('carro e moto batem em coleções diferentes', () {
      expect(fipePath(VehicleType.carro), contains('/carros'));
      expect(fipePath(VehicleType.moto), contains('/motos'));
    });
  });
}
