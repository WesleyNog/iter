/// Onde os anúncios entram no mural, e por quê nessas posições.
///
/// Função pura sobre a lista de posts: entra `List<Post>`, sai a lista de itens
/// que a tela desenha, com os anúncios já no lugar. Sem Flutter, sem Firestore,
/// sem sorteio. Ver `docs/specs/anuncios-no-feed.md`.
///
/// **O problema que este arquivo existe para resolver não é "onde pôr o
/// anúncio" — é "como não movê-lo".** O feed reconstrói a lista dezenas de
/// vezes por página carregada: há `setState` em onze pontos do `FeedTab`
/// (curtida, contadores, URL de foto, denúncia, bloqueio, volta da folha de
/// comentários) e o pai reconstrói o filho a cada perfil que chega do prefetch.
/// Uma posição sorteada dentro do `itemBuilder` seria re-sorteada em todas
/// elas, e o anúncio trocaria de lugar debaixo do dedo de quem está rolando —
/// levando a posição da rolagem junto.
///
/// A saída é aleatoriedade **derivada**, não sorteada: o intervalo até o
/// próximo anúncio sai do id do post que abre o bloco. Parece irregular, é
/// diferente para cada pessoa, e é o mesmo toda vez que a mesma lista é
/// desenhada.
library;

import 'package:iter/model/post.dart';

/// Quantos posts entre um anúncio e o próximo.
///
/// Irregular de propósito. Com um número só — "de 3 em 3" — o olho aprende o
/// ritmo em duas rolagens e o anúncio vira parte do cenário, que é o oposto do
/// que ele precisa ser para valer alguma coisa.
///
/// O menor valor é o que garante a única regra de densidade que a política do
/// AdMob de fato escreve ("mais anúncio que conteúdo", medida na tela visível):
/// com três posts entre um e outro, dois anúncios não cabem no mesmo viewport.
const List<int> kFeedCadence = [3, 5, 4, 3];

/// Um item da lista do mural.
sealed class FeedSlot {
  const FeedSlot();
}

/// Um post, como sempre foi.
class PostSlot extends FeedSlot {
  const PostSlot(this.post);

  final Post post;
}

/// Um anúncio, ancorado no post que abriu o bloco.
///
/// [anchorId] não é decoração. É a chave do cache de `BannerAd` quando o AdMob
/// entrar — e tem de ser por âncora, nunca por índice de item: o `ListView`
/// chama o `itemBuilder` de novo para o mesmo índice a cada rolagem, e um
/// `AdWidget` **não pode** reusar um objeto `Ad` ("this AdWidget is already in
/// the Widget tree… make sure you create a new instance in the builder function
/// with a unique ad object"). Com o índice como chave, apagar um post do meio
/// da lista entregaria a um anúncio o objeto de outro.
class AdSlot extends FeedSlot {
  const AdSlot(this.anchorId);

  final String anchorId;
}

/// A lista do mural com os anúncios já no lugar.
///
/// Determinística: os mesmos posts devolvem os mesmos slots, sempre. É esse
/// determinismo que dispensa guardar a sequência no `State` — e, com ela, os
/// quatro pontos de invalidação que existiriam (`_load`, `_refresh`, `_forget`
/// e `didUpdateWidget`, os lugares onde a lista de posts muda).
///
/// **A caminhada é do começo da lista, sempre**, e é isso que faz a página
/// seguinte não remexer o que já está na tela: o resultado dos primeiros N
/// posts é prefixo do resultado de N + 20. Um `addAll` no fim não pode mudar
/// nada acima dele.
///
/// Lista mais curta que o primeiro intervalo sai **sem anúncio nenhum**. Dois
/// posts com um banner no meio é o caso literal de "mais anúncio que conteúdo".
List<FeedSlot> feedWithAds(
  List<Post> posts, {
  List<int> cadence = kFeedCadence,
}) {
  if (posts.isEmpty || cadence.isEmpty) {
    return [for (final post in posts) PostSlot(post)];
  }

  final slots = <FeedSlot>[];

  // O post que abre o bloco atual: é o id dele que escolhe o tamanho do bloco.
  var anchor = posts.first.id;
  var remaining = _gapFor(anchor, cadence);

  // Índice, e não `for (final post in posts)`: o corpo precisa do post
  // **seguinte** para abrir o próximo bloco, e `indexOf` para achá-lo seria
  // O(n²) e compararia por identidade — `Post` não define `==`, então dois
  // posts iguais vindos de duas leituras não são o mesmo objeto.
  for (var i = 0; i < posts.length; i++) {
    slots.add(PostSlot(posts[i]));
    remaining--;

    if (remaining > 0) continue;

    // **Anúncio só quando há post depois dele.** Fechando o bloco no último
    // post carregado, o anúncio viraria o último item da lista — e, num feed
    // já todo carregado, encostado na barra de navegação de baixo. É o arranjo
    // que o AdMob desencoraja ("ads sandwiched between app content and
    // navigation menus"), e também a tela em que o anúncio tem menos conteúdo
    // em volta, que é a única regra de densidade que a política escreve.
    //
    // Isto **não** quebra a propriedade de prefixo: o anúncio passa a ser
    // acrescentado quando a página seguinte chega, em vez de já estar lá. O
    // que estava na tela continua onde estava — o item novo entra depois dele.
    if (i + 1 >= posts.length) break;

    slots.add(AdSlot(anchor));

    // O bloco seguinte é aberto pelo próximo post, e o intervalo dele sai
    // daquele id — não deste. Reusar a âncora repetiria o mesmo intervalo
    // para sempre, e a cadência voltaria a ser regular.
    anchor = posts[i + 1].id;
    remaining = _gapFor(anchor, cadence);
  }

  return slots;
}

int _gapFor(String id, List<int> cadence) =>
    cadence[_fnv1a(id) % cadence.length];

/// FNV-1a de 32 bits, escrito aqui em vez de `String.hashCode`.
///
/// O `hashCode` do SDK só promete ser **compatível com `==`** — nada sobre ser
/// o mesmo número amanhã. A documentação de `Object.hash` é explícita: os
/// valores "não são garantidos estáveis entre execuções… o algoritmo exato pode
/// diferir entre plataformas ou entre versões das bibliotecas".
///
/// Hoje ele é estável na prática, e é justamente essa estabilidade **não
/// contratada** que quebraria num `flutter upgrade`: o layout do feed de todo
/// mundo mudaria de uma vez, sem uma linha de diff para explicar, e o teste que
/// fixa o layout exato ficaria vermelho sem ninguém ter mexido em nada.
int _fnv1a(String value) {
  var hash = 0x811c9dc5;

  for (final unit in value.codeUnits) {
    hash ^= unit;
    // & 0xFFFFFFFF mantém em 32 bits, que é o que o FNV-1a especifica: no Dart
    // nativo o int é 64, e sem a máscara o valor cresceria a cada caractere
    // até virar outro número.
    //
    // Isso **não** dá paridade com JavaScript, e uma versão anterior deste
    // comentário afirmava que dava. Em JS o int é `double`, e o produto
    // intermediário passa de 2^53 antes da máscara — a precisão se perde ali,
    // não depois. Não afeta este app (`firebase_options` lança
    // `UnsupportedError` fora de Android e iOS), mas afirmar o contrário aqui
    // seria a próxima pessoa confiar num contrato que não existe.
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }

  return hash;
}
