import 'package:flutter/material.dart';
import 'package:iter/Utils/adUnits.dart';

/// A moldura do anúncio no mural: rótulo, borda e folga.
///
/// Nasceu como placeholder na etapa 1, para validar a cadência e o respiro no
/// aparelho antes do SDK; na etapa 2 quem decide o que vai dentro é o
/// `FeedBannerSlot`, e esta moldura ficou igual de propósito — o que foi
/// validado é o que aparece. Ver `docs/specs/anuncios-no-feed.md`.
///
/// **Três coisas aqui são política, não estética**, e é por isso que elas estão
/// neste widget e não numa folha de estilo:
///
/// - **Não pode parecer um post.** É violação escrita nos dois sentidos —
///   "format ads so that they become indistinguishable from other content" e
///   "format site content so that it is difficult to distinguish it from ads".
///   O desenho mais tentador seria reusar a superfície do `PostCard` "para
///   combinar com o feed": é exatamente o que a regra proíbe. O card é branco,
///   flutua com sombra e tem cantos de 20; a moldura é **transparente**, chapada,
///   com borda — que o card não tem — e cantos de 6.
///
///   Até o redesenho do Feed (2026-10-11) era o contrário: o card era
///   cinza-claro e a moldura, branca. Quando o card ficou branco a moldura
///   teria virado a mesma cor dele — o teste "não imita o card de post" ficou
///   vermelho, e é para isso que ele existe. Quem mudou foi a moldura, nunca o
///   teste.
/// - **O rótulo fica visível.** "Publicidade", sempre, sem depender de o
///   anúncio ter carregado.
/// - **A folga é de 24 px**, contra os 14 px de margem do `PostCard`. O card
///   termina numa fileira de curtir e comentar, e a política nomeia esse caso:
///   banner não deve ficar "next to interactive buttons", porque proximidade é
///   "one of the biggest causes of accidental clicks". Suspensão de conta
///   AdMob não é apelável, e a mesma decisão é julgada pelo Google Play.
class FeedAdSlot extends StatelessWidget {
  const FeedAdSlot({super.key, this.child});

  /// O banner, quando chegou. `null` desenha a moldura vazia na altura
  /// reservada, para a lista não saltar quando ele chegar.
  final Widget? child;

  /// A folga acima e abaixo. Decisão registrada na spec: 24 px contra os 12 px
  /// de margem do card, para o anúncio não nascer colado no botão de comentar.
  ///
  /// O que chega na tela é mais que isso em cima, e é de propósito: medido num
  /// `ListView` a 390 dp, do fim pintado do card até o topo da caixa do
  /// anúncio dá **54 px** (os 24 daqui mais o rótulo e o respiro dele), e da
  /// base da caixa até o card seguinte, 24. A folga que a política cobra é
  /// justamente a de cima — é lá que fica a fileira de curtir e comentar; o
  /// que vem embaixo é o cabeçalho do próximo post, que é texto e foto.
  static const double gap = 24;

  /// A altura reservada enquanto o banner não chega — o mesmo teto com que ele
  /// é pedido (`kFeedBannerMaxHeight`), para nunca chegar maior que o espaço.
  static const double reservedHeight = kFeedBannerMaxHeight;

  /// A espessura da borda. O banner é pedido com a largura **de dentro** dela,
  /// e é por isso que o número mora aqui e não só no `Border.all`.
  static const double borderWidth = 1;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              'PUBLICIDADE',
              // `shade700`, e não o `shade500` da primeira versão: medido, ele
              // dava 2,55:1 de contraste contra a superfície da tela, abaixo
              // do texto mais apagado que o feed já tem (o carimbo de data do
              // post, a 4,41:1). Este rótulo é o único elemento do slot que a
              // política **exige** que se veja — ele não pode ser o texto
              // menos legível da tela.
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Container(
            height: child == null ? reservedHeight : null,
            decoration: BoxDecoration(
              // Sem cor: o branco é do card de post. O banner, quando chega,
              // traz o próprio fundo; até lá a moldura é só a borda.
              //
              // Cantos de 6 contra os 20 do card, borda onde o card não tem
              // nenhuma e nenhuma sombra onde o card flutua: são as diferenças
              // que fazem o slot ler como outro objeto ao rolar depressa.
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.grey.shade300,
                width: borderWidth,
              ),
            ),
            alignment: Alignment.center,
            // `clipBehavior` porque a view nativa do banner não respeita o raio
            // da moldura por conta própria.
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ],
      ),
    );
  }
}
