import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:iter/Utils/adUnits.dart';
import 'package:iter/services/ads.dart';

/// Um banner que já carregou: o que desenhar, quanto ele ocupa, e como liberar.
///
/// Interface, e não o `BannerAd` direto, para o teste conseguir exercitar o
/// cache sem view nativa — o `google_mobile_ads` não carrega nada fora de um
/// aparelho.
abstract interface class LoadedBanner {
  Widget get view;

  /// A altura que o servidor escolheu, que só existe depois de carregar.
  double get height;

  void dispose();
}

/// Carrega um banner, ou devolve `null` quando não veio anúncio.
typedef BannerLoader =
    Future<LoadedBanner?> Function({
      required String unitId,
      required int width,
      required int maxHeight,
    });

/// Os banners do mural, **um por âncora**. Ver `docs/specs/anuncios-no-feed.md`.
///
/// Por âncora, e nunca por índice de item: o `ListView` chama o `itemBuilder`
/// de novo para o mesmo índice a cada rolagem, e um `AdWidget` não pode reusar
/// um objeto `Ad` ("this AdWidget is already in the Widget tree… create a new
/// instance in the builder function with a unique ad object"). Com o índice
/// como chave, apagar um post do meio entregaria a um anúncio o objeto de outro.
///
/// **Nada é descartado ao sair da tela**, e é a regra que o protótipo mediu:
/// seis banners vivos usaram 22% do orçamento de quadro no pior caso.
/// Descartar e pedir de novo gasta requisição sem impressão, que é o que
/// derruba a taxa de preenchimento. Tudo morre junto no `dispose` da aba.
///
/// **Âncora que falhou não é pedida de novo** enquanto a aba viver: sem
/// anúncio para aquele pedido, repetir a cada rolagem só acumula requisição
/// vazia. O slot some em vez de ficar um buraco com o rótulo em cima.
class FeedBanners extends ChangeNotifier {
  FeedBanners({String? unitId, BannerLoader? load})
    : _unitId = unitId ?? feedBannerUnit(defaultTargetPlatform),
      _load = load ?? AdsService.loadBanner;

  final String? _unitId;
  final BannerLoader _load;

  final Map<String, LoadedBanner> _loaded = {};
  final Set<String> _pending = {};
  final Set<String> _failed = {};
  bool _disposed = false;

  /// O slot desta âncora ainda pode mostrar anúncio?
  ///
  /// `false` quando a plataforma não tem AdMob ou quando o pedido desta âncora
  /// já falhou — nos dois casos o slot deve sumir, não reservar espaço.
  bool isAvailable(String anchorId) =>
      _unitId != null && !_failed.contains(anchorId);

  /// O banner carregado desta âncora, ou `null` enquanto não chegou.
  LoadedBanner? bannerFor(String anchorId) => _loaded[anchorId];

  /// Pede o banner desta âncora. Idempotente: pedir de novo o que já chegou,
  /// o que está a caminho ou o que falhou não faz nada.
  ///
  /// **Não chame de dentro de um `build`.** O protótipo pedia de lá e produziu
  /// um contador incoerente na tela — mutar estado durante a construção é o
  /// defeito, o número errado foi só o sintoma. `FeedBannerSlot` pede depois
  /// do quadro.
  Future<void> request(String anchorId, {required int width}) async {
    final unitId = _unitId;
    if (unitId == null || _disposed || width <= 0) return;
    if (_loaded.containsKey(anchorId) ||
        _pending.contains(anchorId) ||
        _failed.contains(anchorId)) {
      return;
    }

    _pending.add(anchorId);

    LoadedBanner? banner;
    try {
      banner = await _load(
        unitId: unitId,
        width: width,
        maxHeight: kFeedBannerMaxHeight.toInt(),
      );
    } catch (e) {
      debugPrint('anúncio: banner $anchorId falhou: $e');
      banner = null;
    }

    _pending.remove(anchorId);

    // A aba pode ter fechado com o pedido no ar. O banner que chega depois não
    // tem mais dono e seria uma view nativa vazando até o app fechar.
    if (_disposed) {
      banner?.dispose();
      return;
    }

    if (banner == null) {
      _failed.add(anchorId);
    } else {
      _loaded[anchorId] = banner;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final banner in _loaded.values) {
      banner.dispose();
    }
    _loaded.clear();
    super.dispose();
  }
}
