import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:iter/Utils/adUnits.dart';
import 'package:iter/services/feedBanners.dart';

/// O SDK de anúncios do Google, num lugar só. Ver
/// `docs/specs/anuncios-no-feed.md`.
class AdsService {
  static Future<void>? _pronto;

  /// Termina quando o SDK acabou de inicializar — com sucesso ou não.
  ///
  /// O Google recomenda não pedir anúncio antes disso. É um `Future` guardado,
  /// e não um `await` no `main()`, porque a inicialização acorda os adaptadores
  /// de mediação e faz rede: o primeiro quadro do app não tem por que esperar
  /// um banner que só existe na aba Amigos.
  static Future<void> get pronto => _pronto ??= _inicializar();

  /// Chamado de `main()`, sem `await`.
  static void ativar() {
    debugPrint(
      usingRealAds()
          ? 'anúncio: blocos REAIS (build de produção)'
          : 'anúncio: blocos de demonstração',
    );
    unawaited(pronto);
  }

  static Future<void> _inicializar() async {
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      // Sem SDK não há anúncio, e isso não pode derrubar nada: o slot some.
      debugPrint('anúncio: SDK não inicializou: $e');
    }
  }

  /// **Sempre não personalizado.** Decisão registrada na spec: com público
  /// brasileiro, as saídas são oferecer a escolha ao usuário ou servir só o não
  /// personalizado. Este dispensa tela de consentimento e cabe no legítimo
  /// interesse da política de privacidade; o custo é eCPM menor, que nesta
  /// escala é centavo. Trocar por anúncio personalizado exige o formulário de
  /// consentimento (UMP) **antes**, e a política junto.
  static const AdRequest request = AdRequest(nonPersonalizedAds: true);

  /// O carregador de verdade que `FeedBanners` usa fora dos testes.
  ///
  /// Devolve `null` quando não veio anúncio, e nunca lança: sem preenchimento
  /// é o caso comum de um app pequeno, não um erro.
  static Future<LoadedBanner?> loadBanner({
    required String unitId,
    required int width,
    required int maxHeight,
  }) async {
    await pronto;

    // Quem fecha `chegou` primeiro decide, e **só quem fecha libera o anúncio**
    // num caminho de desistência. Sem essa regra, um banner que carregasse
    // depois do prazo seria entregue a ninguém — e liberado duas vezes.
    final chegou = Completer<LoadedBanner?>();
    Timer? prazo;

    late final BannerAd ad;
    ad = BannerAd(
      adUnitId: unitId,
      // Adaptativo **com teto**: o servidor escolhe a altura, mas nunca maior
      // que o espaço que o slot já reservou. Ver `kFeedBannerMaxHeight`.
      size: AdSize.getInlineAdaptiveBannerAdSize(width, maxHeight),
      request: request,
      listener: BannerAdListener(
        onAdLoaded: (_) async {
          if (chegou.isCompleted) return;

          double height = maxHeight.toDouble();
          try {
            // A altura de verdade só existe depois de carregar.
            final size = await ad.getPlatformAdSize();
            if (size != null) height = size.height.toDouble();
          } catch (e) {
            debugPrint('anúncio: tamanho do banner não veio: $e');
          }

          // O prazo pode ter vencido durante o `await` acima.
          if (chegou.isCompleted) return;
          prazo?.cancel();
          chegou.complete(_GoogleBanner(ad, height));
        },
        onAdFailedToLoad: (_, error) {
          if (chegou.isCompleted) return;
          debugPrint('anúncio: sem banner ($error)');
          prazo?.cancel();
          chegou.complete(null);
          ad.dispose();
        },
      ),
    );

    // Nenhum dos dois retornos em meio minuto: desiste e libera a view, para um
    // pedido pendurado não segurar o slot reservado para sempre.
    prazo = Timer(const Duration(seconds: 30), () {
      if (chegou.isCompleted) return;
      debugPrint('anúncio: banner sem resposta, desistindo');
      chegou.complete(null);
      ad.dispose();
    });

    try {
      await ad.load();
    } catch (e) {
      if (!chegou.isCompleted) {
        debugPrint('anúncio: pedido não saiu: $e');
        prazo.cancel();
        chegou.complete(null);
        ad.dispose();
      }
    }

    return chegou.future;
  }
}

class _GoogleBanner implements LoadedBanner {
  _GoogleBanner(this._ad, this.height) : view = AdWidget(ad: _ad);

  final BannerAd _ad;

  /// Criado **uma vez** por anúncio. O `AdWidget` não pode estar duas vezes na
  /// árvore com o mesmo objeto; guardando a instância, o slot que reconstrói
  /// devolve o mesmo widget em vez de montar um segundo.
  @override
  final Widget view;

  @override
  final double height;

  @override
  void dispose() => _ad.dispose();
}
