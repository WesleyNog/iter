import 'package:flutter/material.dart';
import 'package:iter/services/feedBanners.dart';
import 'package:iter/widget/feedAdSlot.dart';

/// O slot de anúncio do mural ligado a um banner de verdade.
///
/// `FeedAdSlot` é a moldura (rótulo, borda, folga — o que a política cobra);
/// este widget decide o que vai dentro dela. Três estados:
///
/// - **a caminho:** a moldura com a altura reservada, para a lista não saltar;
/// - **carregou:** o banner, na altura que o servidor escolheu;
/// - **não vai vir** (falhou, ou a plataforma não tem AdMob): nada. Um buraco
///   com "PUBLICIDADE" em cima é pior que nenhum anúncio.
///
/// Ver `docs/specs/anuncios-no-feed.md`.
class FeedBannerSlot extends StatefulWidget {
  const FeedBannerSlot({
    super.key,
    required this.anchorId,
    required this.banners,
  });

  final String anchorId;
  final FeedBanners banners;

  @override
  State<FeedBannerSlot> createState() => _FeedBannerSlotState();
}

class _FeedBannerSlotState extends State<FeedBannerSlot> {
  @override
  void initState() {
    super.initState();
    _requestAfterFrame();
  }

  @override
  void didUpdateWidget(FeedBannerSlot old) {
    super.didUpdateWidget(old);
    if (old.anchorId != widget.anchorId || old.banners != widget.banners) {
      _requestAfterFrame();
    }
  }

  /// O pedido sai **depois** do quadro, nunca do `build` — a regra que o
  /// protótipo produziu. E sai daqui, do slot, e não de quando a página de
  /// posts chega: o `ListView.builder` só constrói o que está perto da tela,
  /// então o anúncio é pedido quando alguém vai de fato vê-lo. Pedir os cinco
  /// de uma página que ninguém rolou até o fim é requisição sem impressão.
  void _requestAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // A largura **medida** do slot, e não a da tela: o banner cabe dentro da
      // borda da moldura, e a lista tem margem dos dois lados.
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final inner = box.size.width - 2 * FeedAdSlot.borderWidth;

      widget.banners.request(widget.anchorId, width: inner.truncate());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.banners,
      builder: (context, _) {
        if (!widget.banners.isAvailable(widget.anchorId)) {
          return const SizedBox.shrink();
        }

        final banner = widget.banners.bannerFor(widget.anchorId);
        return FeedAdSlot(
          child: banner == null
              ? null
              : SizedBox(height: banner.height, child: banner.view),
        );
      },
    );
  }
}
