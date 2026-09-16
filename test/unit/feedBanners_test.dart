import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/adUnits.dart';
import 'package:iter/services/feedBanners.dart';

class _FakeBanner implements LoadedBanner {
  _FakeBanner(this.id);

  final String id;
  bool disposed = false;

  @override
  Widget get view => SizedBox(key: Key('banner-$id'));

  @override
  double get height => 60;

  @override
  void dispose() => disposed = true;
}

/// Um carregador que o teste controla: cada pedido fica pendente até o teste
/// dizer se veio anúncio ou não.
class _Loader {
  final calls = <({String unitId, int width, int maxHeight})>[];
  final _pending = <Completer<LoadedBanner?>>[];

  Future<LoadedBanner?> call({
    required String unitId,
    required int width,
    required int maxHeight,
  }) {
    calls.add((unitId: unitId, width: width, maxHeight: maxHeight));
    final completer = Completer<LoadedBanner?>();
    _pending.add(completer);
    return completer.future;
  }

  void deliver(int index, LoadedBanner? banner) =>
      _pending[index].complete(banner);
}

void main() {
  late _Loader loader;
  late FeedBanners banners;

  setUp(() {
    loader = _Loader();
    banners = FeedBanners(unitId: 'unidade', load: loader.call);
  });

  test('pede com o teto de altura que o slot reserva', () async {
    unawaited(banners.request('p1', width: 358));

    expect(loader.calls.single.width, 358);
    expect(loader.calls.single.maxHeight, kFeedBannerMaxHeight.toInt());
    expect(loader.calls.single.unitId, 'unidade');
  });

  test('pedir de novo a mesma âncora, a caminho ou já carregada, não repete', () async {
    // O slot reconstrói a cada rolagem. Cada requisição repetida é pedido sem
    // impressão, que é o que derruba a taxa de preenchimento.
    final first = banners.request('p1', width: 358);
    unawaited(banners.request('p1', width: 358));
    expect(loader.calls, hasLength(1));

    loader.deliver(0, _FakeBanner('p1'));
    await first;
    await banners.request('p1', width: 358);

    expect(loader.calls, hasLength(1));
    expect(banners.bannerFor('p1'), isNotNull);
  });

  test('âncoras diferentes são banners diferentes', () async {
    unawaited(banners.request('p1', width: 358));
    unawaited(banners.request('p9', width: 358));

    expect(loader.calls, hasLength(2));
  });

  test('avisa quem escuta quando o banner chega', () async {
    var notified = 0;
    banners.addListener(() => notified++);

    final pending = banners.request('p1', width: 358);
    expect(notified, 0);

    loader.deliver(0, _FakeBanner('p1'));
    await pending;

    expect(notified, 1);
    expect(banners.isAvailable('p1'), isTrue);
  });

  test('sem anúncio, a âncora some e não é pedida de novo', () async {
    final pending = banners.request('p1', width: 358);
    loader.deliver(0, null);
    await pending;

    expect(banners.isAvailable('p1'), isFalse);
    expect(banners.bannerFor('p1'), isNull);

    await banners.request('p1', width: 358);
    expect(loader.calls, hasLength(1));
  });

  test('um carregador que lança conta como sem anúncio, sem derrubar nada', () async {
    final failing = FeedBanners(
      unitId: 'unidade',
      load: ({required unitId, required width, required maxHeight}) =>
          Future.error(StateError('sem rede')),
    );

    await failing.request('p1', width: 358);

    expect(failing.isAvailable('p1'), isFalse);
  });

  test('fechar a aba libera todos os banners carregados', () async {
    final a = _FakeBanner('p1');
    final b = _FakeBanner('p9');
    final first = banners.request('p1', width: 358);
    final second = banners.request('p9', width: 358);
    loader.deliver(0, a);
    loader.deliver(1, b);
    await Future.wait([first, second]);

    banners.dispose();

    expect(a.disposed, isTrue);
    expect(b.disposed, isTrue);
  });

  test('banner que chega depois de a aba fechar é liberado na hora', () async {
    // Sem isto, a view nativa ficaria viva sem dono até o app fechar.
    final late = _FakeBanner('p1');
    final pending = banners.request('p1', width: 358);

    banners.dispose();
    loader.deliver(0, late);
    await pending;

    expect(late.disposed, isTrue);
  });

  test('largura zero não pede — o slot ainda não foi medido', () async {
    await banners.request('p1', width: 0);

    expect(loader.calls, isEmpty);
    expect(banners.isAvailable('p1'), isTrue);
  });

  test('plataforma sem AdMob: nada é pedido e o slot não aparece', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final desktop = FeedBanners(load: loader.call);
    await desktop.request('p1', width: 358);

    expect(loader.calls, isEmpty);
    expect(desktop.isAvailable('p1'), isFalse);
  });
}
