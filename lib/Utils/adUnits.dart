/// Qual bloco de anúncio o app pede: o de demonstração do Google ou o real.
///
/// **O real só existe num build de release feito com
/// `--dart-define=ANUNCIOS_REAIS=true`.** Sem a flag, todo build — debug,
/// profile, e o release que vai para o teste fechado — usa os blocos de
/// demonstração, que "are not associated with your AdMob account, so there's
/// no risk of your account generating invalid traffic". Ver
/// `docs/specs/anuncios-no-feed.md`.
///
/// Duas travas, e não uma, pela razão que a spec registra: o risco dominante
/// deste app é o tráfego de anúncio ser o próprio dono e as pessoas que ele
/// conhece. `kReleaseMode` sozinho mandaria anúncio real aos doze testadores do
/// teste fechado, que são conhecidos e clicam "para ajudar" — o padrão exato que
/// o antifraude pune com suspensão. A flag sozinha deixaria um
/// `flutter run --dart-define=ANUNCIOS_REAIS=true` pedir anúncio real no
/// aparelho do dono.
library;

import 'package:flutter/foundation.dart';

/// Pedido explícito de anúncio real, vindo do comando de build.
const bool kAnunciosReaisPedidos = bool.fromEnvironment('ANUNCIOS_REAIS');

/// A altura máxima do banner do feed, e a que o slot reserva antes de ele
/// chegar.
///
/// O mesmo número nos dois lados de propósito. O banner inline adaptativo tem
/// altura escolhida pelo servidor; pedindo com este teto, o anúncio nunca chega
/// **maior** que o espaço reservado, e a lista não salta para baixo debaixo do
/// dedo de quem rola. Pode chegar menor — aí o conteúdo abaixo sobe, que
/// incomoda muito menos.
const double kFeedBannerMaxHeight = 100;

/// Os blocos do banner do feed na conta AdMob do iter. Não são segredo — vão
/// dentro do binário —; o que os protege é a política, não o sigilo.
const Map<TargetPlatform, String> _feedBannerReal = {
  TargetPlatform.android: 'ca-app-pub-8153139669866970/9628305478',
  TargetPlatform.iOS: 'ca-app-pub-8153139669866970/7820399787',
};

/// Os blocos de demonstração do Google para banner adaptativo.
const Map<TargetPlatform, String> _feedBannerDemo = {
  TargetPlatform.android: 'ca-app-pub-3940256099942544/9214589741',
  TargetPlatform.iOS: 'ca-app-pub-3940256099942544/2435281174',
};

/// O bloco do banner do feed para [platform], ou `null` onde o AdMob não
/// existe (web, desktop) — e aí o slot simplesmente não aparece.
///
/// Os parâmetros com padrão existem para o teste alcançar as quatro
/// combinações sem compilar o app quatro vezes.
String? feedBannerUnit(
  TargetPlatform platform, {
  bool release = kReleaseMode,
  bool realRequested = kAnunciosReaisPedidos,
}) {
  final real = release && realRequested;
  return (real ? _feedBannerReal : _feedBannerDemo)[platform];
}

/// Se o build está pedindo anúncio real. Só para dizer isso no log da
/// abertura, que é onde um build de produção feito sem a flag aparece.
bool usingRealAds({
  bool release = kReleaseMode,
  bool realRequested = kAnunciosReaisPedidos,
}) => release && realRequested;
