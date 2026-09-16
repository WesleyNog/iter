import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/adUnits.dart';

const _demoAndroid = 'ca-app-pub-3940256099942544/9214589741';
const _demoIos = 'ca-app-pub-3940256099942544/2435281174';
const _realAndroid = 'ca-app-pub-8153139669866970/9628305478';
const _realIos = 'ca-app-pub-8153139669866970/7820399787';

void main() {
  group('o bloco real exige as DUAS travas', () {
    test('release COM a flag: real', () {
      expect(
        feedBannerUnit(TargetPlatform.android, release: true, realRequested: true),
        _realAndroid,
      );
      expect(
        feedBannerUnit(TargetPlatform.iOS, release: true, realRequested: true),
        _realIos,
      );
    });

    test('release SEM a flag — o build do teste fechado — continua demonstração', () {
      // É o caso que a flag existe para cobrir: os doze testadores são
      // conhecidos do dono, e anúncio real na mão deles é tráfego inválido.
      expect(
        feedBannerUnit(TargetPlatform.android, release: true, realRequested: false),
        _demoAndroid,
      );
      expect(usingRealAds(release: true, realRequested: false), isFalse);
    });

    test('debug COM a flag continua demonstração', () {
      // `flutter run --dart-define=ANUNCIOS_REAIS=true` no aparelho do dono
      // não pode pedir anúncio real.
      expect(
        feedBannerUnit(TargetPlatform.iOS, release: false, realRequested: true),
        _demoIos,
      );
      expect(usingRealAds(release: false, realRequested: true), isFalse);
    });

    test('debug sem a flag: demonstração', () {
      expect(
        feedBannerUnit(TargetPlatform.android, release: false, realRequested: false),
        _demoAndroid,
      );
    });
  });

  test('plataforma sem AdMob não tem bloco', () {
    expect(
      feedBannerUnit(TargetPlatform.macOS, release: true, realRequested: true),
      isNull,
    );
    expect(
      feedBannerUnit(TargetPlatform.linux, release: false, realRequested: false),
      isNull,
    );
  });

  test('este teste roda sem a flag, como todo build que não é de produção', () {
    expect(kAnunciosReaisPedidos, isFalse);
  });
}
