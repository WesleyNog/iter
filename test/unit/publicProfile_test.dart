import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/model/publicProfile.dart';

void main() {
  group('PublicProfile — a vitrine', () {
    test('ida e volta preserva nome, apelido e foto', () {
      const original = PublicProfile(
        uid: 'abc123',
        name: 'Wesley Nogueira',
        nickName: 'wesley.n4',
        photoUrl: 'https://lh3.googleusercontent.com/foto',
        updatedAt: '2026-08-07T10:00:00.000',
      );

      final volta = PublicProfile.fromMap(original.toMap());

      expect(volta.uid, 'abc123');
      expect(volta.name, 'Wesley Nogueira');
      expect(volta.nickName, 'wesley.n4');
      expect(volta.photoUrl, 'https://lh3.googleusercontent.com/foto');
      expect(volta.updatedAt, '2026-08-07T10:00:00.000');
    });

    test('grava exatamente as cinco chaves que a regra aceita', () {
      // `firestore.rules` tem `hasOnly` com esta lista: uma chave a mais e o
      // servidor recusa a escrita inteira. É o que impede CPF de vazar por
      // descuido, então o teste guarda a lista.
      const perfil = PublicProfile(
        uid: 'abc123',
        name: 'Wesley',
        updatedAt: '2026-08-07T10:00:00.000',
      );

      expect(perfil.toMap().keys.toSet(), {
        'uid',
        'name',
        'nickName',
        'photoUrl',
        'updatedAt',
      });
    });

    test('apelido e foto ausentes voltam null', () {
      final volta = PublicProfile.fromMap({
        'uid': 'abc123',
        'name': 'Wesley',
        'updatedAt': '2026-08-07T10:00:00.000',
      });

      expect(volta.nickName, isNull);
      expect(volta.photoUrl, isNull);
    });
  });

  group('ProfileStats — a travessia dos números públicos', () {
    test('ida e volta preserva os seis números', () {
      const original = ProfileStats(
        routes: 412,
        deliveredPackages: 38400,
        stops: 9120,
        failureRate: 1.4,
        topCompany: (label: 'Mercado Livre', share: 62.5),
        averageDuration: Duration(hours: 7, minutes: 30),
      );

      final volta = ProfileStats.fromMap(original.toMap());

      expect(volta.routes, 412);
      expect(volta.deliveredPackages, 38400);
      expect(volta.stops, 9120);
      expect(volta.failureRate, 1.4);
      expect(volta.topCompany?.label, 'Mercado Livre');
      expect(volta.topCompany?.share, 62.5);
      expect(volta.averageDuration, const Duration(minutes: 450));
    });

    test('topCompany vira dois campos e volta a ser um record', () {
      const original = ProfileStats(
        routes: 10,
        deliveredPackages: 0,
        stops: 0,
        topCompany: (label: 'Shopee', share: 40),
      );

      final mapa = original.toMap();
      expect(mapa['topCompanyLabel'], 'Shopee');
      expect(mapa['topCompanyShare'], 40);

      expect(ProfileStats.fromMap(mapa).topCompany, (
        label: 'Shopee',
        share: 40.0,
      ));
    });

    test('averageDuration vira minutos, truncando os segundos', () {
      const original = ProfileStats(
        routes: 1,
        deliveredPackages: 0,
        stops: 0,
        averageDuration: Duration(minutes: 90, seconds: 45),
      );

      expect(original.toMap()['averageMinutes'], 90);
      expect(
        ProfileStats.fromMap(original.toMap()).averageDuration,
        const Duration(minutes: 90),
      );
    });

    test('taxa e duração ausentes voltam null, nunca zero', () {
      // O caso que importa: "0% de insucesso" e "ninguém preencheu pacotes"
      // são coisas diferentes, e é aqui, na travessia, que a distinção se
      // perde se alguém escorregar num `?? 0`.
      final volta = ProfileStats.fromMap({
        'routes': 5,
        'deliveredPackages': 0,
        'stops': 0,
      });

      expect(volta.failureRate, isNull);
      expect(volta.averageDuration, isNull);
      expect(volta.topCompany, isNull);
    });

    test('taxa de zero por cento sobrevive à travessia', () {
      // A contraprova do teste acima: zero é resposta quando alguém *de fato*
      // não teve insucesso, e não pode virar `null` no caminho.
      const original = ProfileStats(
        routes: 5,
        deliveredPackages: 400,
        stops: 100,
        failureRate: 0,
      );

      expect(ProfileStats.fromMap(original.toMap()).failureRate, 0);
    });

    test('meia empresa não é empresa', () {
      // Documento com o rótulo e sem a fatia (ou o contrário) não tem o que
      // mostrar; inventar 0% seria pior que omitir.
      expect(
        ProfileStats.fromMap({'topCompanyLabel': 'Amazon'}).topCompany,
        isNull,
      );
      expect(
        ProfileStats.fromMap({'topCompanyShare': 30.0}).topCompany,
        isNull,
      );
    });

    test('documento vazio vira conta nova, não conta quebrada', () {
      final volta = ProfileStats.fromMap({});

      // Contagem é zero porque zero é a resposta certa: a conta rodou zero
      // rotas mesmo. Taxa é null porque não há como calcular.
      expect(volta.routes, 0);
      expect(volta.deliveredPackages, 0);
      expect(volta.stops, 0);
      expect(volta.failureRate, isNull);
      expect(volta.topCompany, isNull);
      expect(volta.averageDuration, isNull);
    });

    test('número gravado como int não derruba a leitura', () {
      // O Firestore devolve `int` quando o valor não tem casa decimal, então
      // `map['failureRate'] as double?` lançaria num documento que guardou
      // `2` em vez de `2.0` — a armadilha que `readDouble` existe para evitar.
      final volta = ProfileStats.fromMap({
        'routes': 3,
        'deliveredPackages': 100,
        'stops': 20,
        'failureRate': 2,
        'topCompanyLabel': 'Amazon',
        'topCompanyShare': 50,
      });

      expect(volta.failureRate, 2.0);
      expect(volta.topCompany?.share, 50.0);
    });
  });
}
