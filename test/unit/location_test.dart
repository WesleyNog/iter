import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iter/services/location.dart';

/// `currentLocation()` fala com a plataforma e não roda em teste. O que dá para
/// testar — e onde os bugs de fato moram — é a decisão a partir do estado.
void main() {
  group('failureFor — a decisão', () {
    test('permissão concedida não é falha', () {
      expect(
        failureFor(
          serviceEnabled: true,
          permission: LocationPermission.whileInUse,
        ),
        isNull,
      );
      expect(
        failureFor(serviceEnabled: true, permission: LocationPermission.always),
        isNull,
      );
    });

    test('GPS desligado vence a permissão concedida', () {
      // Com o serviço desligado, "permita a localização" seria a mensagem
      // errada: ele já permitiu, o que falta é ligar o GPS.
      expect(
        failureFor(
          serviceEnabled: false,
          permission: LocationPermission.whileInUse,
        ),
        LocationFailure.serviceDisabled,
      );
    });

    test('GPS desligado vence até a permissão negada para sempre', () {
      expect(
        failureFor(
          serviceEnabled: false,
          permission: LocationPermission.deniedForever,
        ),
        LocationFailure.serviceDisabled,
      );
    });

    test('negado agora e negado para sempre são casos diferentes', () {
      // O primeiro dá para perguntar de novo; o segundo, só pelos ajustes.
      expect(
        failureFor(serviceEnabled: true, permission: LocationPermission.denied),
        LocationFailure.denied,
      );
      expect(
        failureFor(
          serviceEnabled: true,
          permission: LocationPermission.deniedForever,
        ),
        LocationFailure.deniedForever,
      );
    });

    test('estado indeterminado vira falha genérica', () {
      expect(
        failureFor(
          serviceEnabled: true,
          permission: LocationPermission.unableToDetermine,
        ),
        LocationFailure.failed,
      );
    });
  });

  group('o que a tela mostra', () {
    test('cada falha tem a própria frase', () {
      final frases = {
        for (final f in LocationFailure.values) locationFailureMessage(f),
      };

      // Quatro frases distintas: mensagem genérica faria o usuário tentar a
      // coisa errada.
      expect(frases.length, LocationFailure.values.length);
      for (final f in LocationFailure.values) {
        expect(locationFailureMessage(f), isNotEmpty);
      }
    });

    test('só o bloqueio definitivo oferece os ajustes', () {
      // Mandar "abra os ajustes" para quem tocou em "agora não" é insistência.
      expect(opensSettings(LocationFailure.deniedForever), isTrue);
      expect(opensSettings(LocationFailure.denied), isFalse);
      expect(opensSettings(LocationFailure.serviceDisabled), isFalse);
      expect(opensSettings(LocationFailure.failed), isFalse);
    });
  });
}
