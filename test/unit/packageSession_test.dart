import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/packageLabel.dart';
import 'package:iter/Utils/packageSession.dart';

LabelRead _read(
  String id, {
  PackageType? type = PackageType.residencial,
  String? bairro = 'Papicu',
  String? raw,
  String? stop,
}) => LabelRead(
  shipmentId: id,
  type: type,
  bairro: bairro,
  rawBairro: raw ?? bairro,
  stopKey: stop ?? 'cep-$id',
);

void main() {
  group('contar', () {
    test('a mesma etiqueta lida dez vezes conta uma', () {
      final session = PackageSession();

      final outcomes = [for (var i = 0; i < 10; i++) session.add(_read('1'))];

      expect(session.total, 1);
      expect(outcomes.first, ReadOutcome.added);
      expect(outcomes.skip(1), everyElement(ReadOutcome.repeated));
    });

    test('total e por tipo', () {
      final session = PackageSession()
        ..add(_read('1'))
        ..add(_read('2'))
        ..add(_read('3', type: PackageType.comercial))
        ..add(_read('4', type: PackageType.agencia));

      expect(session.total, 4);
      expect(session.count(PackageType.residencial), 2);
      expect(session.count(PackageType.comercial), 1);
      expect(session.count(PackageType.agencia), 1);
      expect(session.untyped, 0);
    });

    test('sem letra conta no total e em nenhum tipo', () {
      final session = PackageSession()
        ..add(_read('1'))
        ..add(_read('2', type: null));

      expect(session.total, 2);
      expect(session.untyped, 1);
      expect(PackageType.values.map(session.count).reduce((a, b) => a + b), 1);
    });
  });

  group('releitura do mesmo pacote', () {
    test('traz a letra que faltava sem contar de novo', () {
      final session = PackageSession()..add(_read('1', type: null));

      final outcome = session.add(_read('1'));

      expect(outcome, ReadOutcome.completed);
      expect(session.total, 1);
      expect(session['1']!.type, PackageType.residencial);
    });

    test('nunca troca o que já foi lido', () {
      final session = PackageSession()
        ..add(_read('1', type: PackageType.agencia));

      final outcome = session.add(_read('1', type: PackageType.residencial));

      expect(outcome, ReadOutcome.repeated);
      expect(session['1']!.type, PackageType.agencia);
    });

    test('nunca desfaz a escolha do entregador', () {
      final session = PackageSession()..add(_read('1', type: null));
      session.setType('1', PackageType.agencia);

      // O "R" finalmente aparece na câmera, depois do toque em "A".
      session.add(_read('1'));

      expect(session['1']!.type, PackageType.agencia);
    });

    test('bairro e texto lido vêm da mesma leitura', () {
      final session = PackageSession()
        ..add(_read('1', bairro: null, raw: 'Papicuu'));

      session.add(_read('1', bairro: 'Papicu', raw: 'Papicu'));

      expect(session['1']!.bairro, 'Papicu');
      expect(session['1']!.rawBairro, 'Papicu');
    });
  });

  group('corrigir e remover', () {
    test('corrigir o tipo move entre as contagens', () {
      final session = PackageSession()..add(_read('1'));

      session.setType('1', PackageType.comercial);

      expect(session.count(PackageType.residencial), 0);
      expect(session.count(PackageType.comercial), 1);
    });

    test('remover tira do total e o bairro que ficou sem pacote some', () {
      final session = PackageSession()
        ..add(_read('1', bairro: 'Papicu'))
        ..add(_read('2', bairro: 'Aldeota', type: PackageType.agencia));

      // A agência fechada sai da carga.
      session.remove('2');

      expect(session.total, 1);
      expect(session.count(PackageType.agencia), 0);
      expect(session.bairros, ['Papicu']);
    });

    test('a lista vem do mais recente para o mais antigo', () {
      final session = PackageSession()
        ..add(_read('1'))
        ..add(_read('2'))
        ..add(_read('3'));

      expect(session.entries.map((e) => e.shipmentId), ['3', '2', '1']);
    });
  });

  group('paradas', () {
    test('mesmo prédio é uma parada', () {
      final session = PackageSession()
        ..add(_read('1', stop: '60175045 575'))
        ..add(_read('2', stop: '60175045 575'))
        ..add(_read('3', stop: '60165090 3330'));

      expect(session.total, 3);
      expect(session.stops, 2);
    });

    test('sem chave, o pacote é parada própria', () {
      final session = PackageSession()
        ..add(const LabelRead(shipmentId: '1', type: PackageType.residencial))
        ..add(const LabelRead(shipmentId: '2', type: PackageType.residencial));

      expect(session.stops, 2);
    });
  });

  group('bairros', () {
    test('ordenados por quantidade, empate pelo nome', () {
      final session = PackageSession()
        ..add(_read('1', bairro: 'Meireles'))
        ..add(_read('2', bairro: 'Papicu'))
        ..add(_read('3', bairro: 'Papicu'))
        ..add(_read('4', bairro: 'Aldeota'));

      expect(session.pacotesPorBairro, {
        'Papicu': 2,
        'Aldeota': 1,
        'Meireles': 1,
      });
      expect(session.bairros, ['Papicu', 'Aldeota', 'Meireles']);
    });

    test('o que não casou com a lista fica fora e aparece à parte', () {
      final session = PackageSession()
        ..add(_read('1', bairro: 'Papicu'))
        ..add(_read('2', bairro: null, raw: 'Água Fria'))
        ..add(_read('3', bairro: null, raw: 'Água Fria'))
        ..add(_read('4', bairro: null, raw: null));

      expect(session.pacotesPorBairro, {'Papicu': 1});
      expect(session.unmatchedBairros, {'Água Fria': 2});
      expect(session.withoutBairro, 3);
      expect(session.total, 4);
    });
  });

  group('loadOf — o que a revisão grava', () {
    PackageSession carga() => PackageSession()
      ..add(_read('1', bairro: 'Papicu'))
      ..add(_read('2', bairro: 'Papicu'))
      ..add(_read('3', bairro: 'Meireles'));

    test('sem edição, grava o que foi lido', () {
      final session = carga();
      final load = loadOf(
        session,
        packages: session.total,
        stops: session.stops,
        bairros: session.bairros,
      );

      expect(load.packages, 3);
      expect(load.bairros, ['Papicu', 'Meireles']);
      expect(load.pacotesPorBairro, {'Papicu': 2, 'Meireles': 1});
    });

    test('bairro tirado na revisão leva a parte dele para o rateio', () {
      final load = loadOf(
        carga(),
        packages: 3,
        stops: 3,
        bairros: const ['Papicu'],
      );

      expect(load.pacotesPorBairro, {'Papicu': 2});
    });

    test('bairro posto na revisão entra sem pacote medido', () {
      final load = loadOf(
        carga(),
        packages: 3,
        stops: 3,
        bairros: const ['Papicu', 'Meireles', 'Aldeota'],
      );

      expect(load.bairros, ['Papicu', 'Meireles', 'Aldeota']);
      expect(load.pacotesPorBairro, {'Papicu': 2, 'Meireles': 1});
    });

    test('total corrigido para baixo corta do bairro de menos pacotes', () {
      final load = loadOf(
        carga(),
        packages: 2,
        stops: 2,
        bairros: const ['Papicu', 'Meireles'],
      );

      expect(load.pacotesPorBairro, {'Papicu': 2});
    });
  });
}
