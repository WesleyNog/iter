import 'package:flutter/material.dart';

/// O espaço do anúncio no mural.
///
/// Na etapa 1 ele é um **placeholder**: desenha a moldura, o rótulo e a folga
/// definitivos, sem nenhum SDK de anúncio por trás. É isso que permite validar
/// a cadência e o respiro no aparelho antes de o `google_mobile_ads` entrar —
/// e antes de existir conta AdMob servindo qualquer coisa. Ver
/// `docs/specs/anuncios-no-feed.md`.
///
/// **Três coisas aqui são política, não estética**, e é por isso que elas estão
/// neste widget e não numa folha de estilo:
///
/// - **Não pode parecer um post.** É violação escrita nos dois sentidos —
///   "format ads so that they become indistinguishable from other content" e
///   "format site content so that it is difficult to distinguish it from ads".
///   O desenho mais tentador seria reusar o `Container` do `PostCard`
///   (`grey.shade50`, raio 14) "para combinar com o feed": é exatamente o que a
///   regra proíbe. Daí o fundo branco, a borda — que o card não tem — e o raio
///   menor.
/// - **O rótulo fica visível.** "Publicidade", sempre, sem depender de o
///   anúncio ter carregado.
/// - **A folga é de 24 px**, contra os 12 px de margem do `PostCard`. O card
///   termina numa fileira de curtir e comentar, e a política nomeia esse caso:
///   banner não deve ficar "next to interactive buttons", porque proximidade é
///   "one of the biggest causes of accidental clicks". Suspensão de conta
///   AdMob não é apelável, e a mesma decisão é julgada pelo Google Play.
class FeedAdSlot extends StatelessWidget {
  const FeedAdSlot({super.key, this.child});

  /// O anúncio de verdade, quando houver. `null` desenha o placeholder.
  ///
  /// A moldura, o rótulo e a folga são os mesmos nos dois casos de propósito:
  /// o que a etapa 1 valida no aparelho é o que a etapa 2 vai mostrar.
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

  /// A altura reservada enquanto não há anúncio.
  ///
  /// O banner inline adaptativo tem altura calculada a partir da largura da
  /// tela, e ela precisa ser conhecida **antes** de o anúncio carregar — senão
  /// a lista salta quando ele chega. Este número é o do banner adaptativo
  /// típico em telefone; a etapa 2 troca a constante pelo valor que o SDK
  /// devolve.
  static const double reservedHeight = 100;

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
              color: Colors.white,
              // Raio menor que os 14 do card, e borda onde o card não tem
              // nenhuma: são as duas diferenças que fazem o slot ler como
              // outro objeto ao rolar depressa.
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            alignment: Alignment.center,
            child:
                child ??
                Text(
                  'Espaço reservado para anúncio',
                  // `shade400` sobre branco dá 1,88:1 — ilegível. Este texto é
                  // temporário, mas é justamente ele que o dono precisa
                  // enxergar no aparelho para validar a cadência.
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
          ),
        ],
      ),
    );
  }
}
