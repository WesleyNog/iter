/// Localização do aparelho, para achar os postos por perto.
///
/// Nada aqui pode bloquear o registro do abastecimento: o gasto é do usuário, e
/// GPS desligado, permissão negada ou aparelho sem sinal só custam a lista de
/// postos — o formulário continua inteiro com o campo de texto livre.
library;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Por que não deu para saber onde ele está.
///
/// Cada caso pede uma frase diferente na tela: mandar "ative nos ajustes" para
/// quem apenas tocou em "agora não" é insistência; e mandar "permitir" para
/// quem já marcou "nunca" não resolve nada, porque o app não consegue mais
/// perguntar.
enum LocationFailure {
  /// GPS desligado no aparelho.
  serviceDisabled,

  /// Negou agora — dá para perguntar de novo depois.
  denied,

  /// Negou e o sistema não deixa mais perguntar. Só pelos ajustes.
  deniedForever,

  /// Erro ou tempo esgotado ao ler a posição.
  failed,
}

/// Posição, ou o motivo de não ter dado.
typedef LocationResult = ({double? lat, double? lng, LocationFailure? failure});

/// Decide o resultado a partir do estado atual, **sem tocar na plataforma**.
///
/// Separada de [currentLocation] porque é aqui que mora a lógica — e é a única
/// parte testável sem aparelho.
LocationFailure? failureFor({
  required bool serviceEnabled,
  required LocationPermission permission,
}) {
  // O serviço vem primeiro: com o GPS desligado, permissão concedida não
  // adianta nada, e "permita a localização" seria a mensagem errada.
  if (!serviceEnabled) return LocationFailure.serviceDisabled;

  return switch (permission) {
    LocationPermission.deniedForever => LocationFailure.deniedForever,
    LocationPermission.denied => LocationFailure.denied,
    LocationPermission.unableToDetermine => LocationFailure.failed,
    LocationPermission.whileInUse || LocationPermission.always => null,
  };
}

/// O que dizer ao usuário em cada caso.
String locationFailureMessage(LocationFailure failure) => switch (failure) {
  LocationFailure.serviceDisabled =>
    'Ative a localização do aparelho para ver os postos por perto.',
  LocationFailure.denied =>
    'Sem a localização não dá para listar os postos. Você pode digitar o nome.',
  LocationFailure.deniedForever =>
    'A localização está bloqueada para o iter nos ajustes do aparelho.',
  LocationFailure.failed =>
    'Não foi possível obter sua localização agora.',
};

/// Só neste caso vale oferecer o atalho para os ajustes — nos outros, o próprio
/// app ainda consegue resolver.
bool opensSettings(LocationFailure failure) =>
    failure == LocationFailure.deniedForever;

/// Abre os ajustes do app no sistema.
///
/// É a única saída quando a permissão está em `deniedForever`: dali o app não
/// consegue mais nem mostrar o diálogo.
Future<void> openLocationSettings() => Geolocator.openAppSettings();

/// Onde o usuário está agora.
///
/// Precisão **média** de propósito: achar o posto certo pede uns 100 m, e
/// `best` liga o GPS de alta precisão, demora mais e come bateria de quem usa o
/// celular o dia inteiro rodando.
Future<LocationResult> currentLocation() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    var permission = await Geolocator.checkPermission();
    // Só pergunta quando ainda dá: com `deniedForever` o sistema nem mostra o
    // diálogo, e insistir seria um toque que não faz nada.
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final failure = failureFor(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
    if (failure != null) return (lat: null, lng: null, failure: failure);

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );

    return (
      lat: position.latitude,
      lng: position.longitude,
      failure: null,
    );
  } catch (e) {
    debugPrint('Localização: falha ao obter a posição: $e');
    return (lat: null, lng: null, failure: LocationFailure.failed);
  }
}
