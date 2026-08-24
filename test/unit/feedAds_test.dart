import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/feedAds.dart';
import 'package:iter/model/post.dart';

Post _post(String id) =>
    Post(id: id, uid: 'u1', text: 'oi', createdAt: DateTime(2026, 8, 24));

List<Post> _posts(int quantos) => [
  for (var i = 1; i <= quantos; i++) _post('p$i'),
];

/// O layout como texto, para o teste poder afirmar a lista **inteira**.
List<String> _layout(List<FeedSlot> slots) => [
  for (final slot in slots)
    switch (slot) {
      PostSlot(:final post) => post.id,
      AdSlot(:final anchorId) => 'ad($anchorId)',
    },
];

/// Os intervalos observados: quantos posts entre um anúncio e o próximo.
List<int> _gaps(List<FeedSlot> slots) {
  final gaps = <int>[];
  var contador = 0;

  for (final slot in slots) {
    if (slot is PostSlot) {
      contador++;
    } else {
      gaps.add(contador);
      contador = 0;
    }
  }

  return gaps;
}

void main() {
  group('o layout exato', () {
    test('uma lista conhecida sai sempre igual', () {
      // Afirmar a lista inteira, e não "tem N anúncios": é isto que fica
      // vermelho se alguém trocar o FNV-1a por `String.hashCode` ou mexer na
      // ordem em que a âncora é escolhida.
      final layout = _layout(feedWithAds(_posts(12)));

      expect(layout, [
        'p1',
        'p2',
        'p3',
        'p4',
        'ad(p1)',
        'p5',
        'p6',
        'p7',
        'p8',
        'ad(p5)',
        'p9',
        'p10',
        'p11',
        'p12',
      ]);
    });

    test('o anúncio é ancorado no post que ABRE o bloco', () {
      // E não no que fecha: é a âncora que escolhe o tamanho do bloco, e é ela
      // que vira a chave do cache de BannerAd na etapa 2.
      final slots = feedWithAds(_posts(12));
      final primeiro = slots.whereType<AdSlot>().first;

      expect(primeiro.anchorId, 'p1');
    });
  });

  group('determinismo — o defeito que este arquivo existe para impedir', () {
    test('duas chamadas com a mesma entrada dão a mesma saída', () {
      final posts = _posts(40);

      expect(_layout(feedWithAds(posts)), _layout(feedWithAds(posts)));
    });

    test(
      'a mesma lista em outra ordem de objetos, mesmos ids, mesmo layout',
      () {
        // O feed remonta a lista de `Post` a cada página; os objetos são outros,
        // os ids são os mesmos. Se a cadência dependesse da identidade do
        // objeto, o anúncio andaria a cada `_load`.
        final a = _posts(40);
        final b = [for (final post in a) _post(post.id)];

        expect(_layout(feedWithAds(b)), _layout(feedWithAds(a)));
      },
    );
  });

  group('paginação — a página nova não remexe o que está na tela', () {
    test('o resultado dos 20 primeiros é prefixo do resultado de 40', () {
      final primeira = _posts(20);
      final ambas = _posts(40);

      final antes = _layout(feedWithAds(primeira));
      final depois = _layout(feedWithAds(ambas));

      expect(depois.take(antes.length), antes);
    });

    test('vale para qualquer corte, não só para o de 20', () {
      final todos = _posts(60);
      final completo = _layout(feedWithAds(todos));

      for (final corte in [1, 3, 4, 7, 12, 19, 20, 33, 47]) {
        final parcial = _layout(feedWithAds(todos.take(corte).toList()));
        expect(
          completo.take(parcial.length),
          parcial,
          reason: 'quebrou no corte de $corte posts',
        );
      }
    });
  });

  group('os intervalos', () {
    test('todo intervalo está na cadência — nunca dois anúncios colados', () {
      // O defeito que reprovou o desenho "sorteia por post": ele produzia
      // pares de anúncios um embaixo do outro.
      final gaps = _gaps(feedWithAds(_posts(300)));

      expect(gaps, isNotEmpty);
      for (final gap in gaps) {
        // Piso **absoluto**, escrito à mão: três posts entre um anúncio e o
        // próximo. Conferir só `kFeedCadence.contains(gap)` seria comparar a
        // constante com ela mesma — a revisão provou isso rodando com
        // `kFeedCadence = [1, 5, 4, 1]`, e os catorze testes continuaram
        // verdes com dois anúncios podendo nascer colados. É este número que
        // sustenta a única regra de densidade que a política escreve.
        expect(gap, greaterThanOrEqualTo(3), reason: 'anúncios quase colados');
        expect(kFeedCadence, contains(gap));
      }
    });

    test('a sequência não é sempre o mesmo número', () {
      // Se fosse, o pedido do dono não teria sido atendido: "de 3 em 3" é
      // exatamente o que ele não quer.
      final gaps = _gaps(feedWithAds(_posts(300)));

      expect(gaps.toSet().length, greaterThan(1));
    });

    test('com ids de Firestore de verdade, os três intervalos aparecem', () {
      // `p1`, `p2`, `p3` são ids sintéticos e curtos, e num teste de cadência
      // isso importa: strings quase iguais podem cair no mesmo balde e dar uma
      // sequência menos variada do que a real. O Firestore gera ids de 20
      // caracteres do alfabeto abaixo — estes saíram de um gerador com semente
      // fixa, para o teste continuar determinístico.
      const alfabeto =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      var semente = 12345;
      String proximoId() {
        final buffer = StringBuffer();
        for (var i = 0; i < 20; i++) {
          // LCG simples: o teste não precisa de qualidade estatística, precisa
          // de ids parecidos com os de verdade e iguais em toda execução.
          semente = (semente * 1103515245 + 12345) & 0x7FFFFFFF;
          buffer.write(alfabeto[semente % alfabeto.length]);
        }
        return buffer.toString();
      }

      final posts = [for (var i = 0; i < 300; i++) _post(proximoId())];
      final gaps = _gaps(feedWithAds(posts));

      expect(gaps.toSet(), containsAll(kFeedCadence.toSet()));
    });
  });

  group('as pontas', () {
    test('lista vazia sai vazia', () {
      expect(feedWithAds(const []), isEmpty);
    });

    test('o anúncio nunca é o último item da lista', () {
      // Fechando o bloco no último post, o anúncio ficaria encostado na barra
      // de navegação num feed já todo carregado — o arranjo que o AdMob
      // desencoraja. Com 12 posts o terceiro bloco fecha exatamente no fim.
      final slots = feedWithAds(_posts(12));

      expect(slots.last, isA<PostSlot>());
      expect(_layout(slots).last, 'p12');
    });

    test('o anúncio omitido no fim aparece quando a página seguinte chega', () {
      // E aparece **depois** do que já estava na tela: nada se move.
      final antes = _layout(feedWithAds(_posts(12)));
      final depois = _layout(feedWithAds(_posts(13)));

      expect(depois.take(antes.length), antes);
      expect(depois.last, 'p13');
      expect(depois[antes.length], 'ad(p9)');
    });

    test('feed curto não recebe anúncio nenhum', () {
      // Decisão do dono: com menos posts que o primeiro intervalo, nenhum
      // anúncio. Dois posts com um banner no meio é o caso literal de "mais
      // anúncio que conteúdo".
      for (var n = 1; n <= 2; n++) {
        final slots = feedWithAds(_posts(n));
        expect(slots.whereType<AdSlot>(), isEmpty, reason: '$n posts');
        expect(slots, hasLength(n));
      }
    });

    test('cadência vazia devolve só os posts, sem lançar', () {
      final slots = feedWithAds(_posts(30), cadence: const []);

      expect(slots.whereType<AdSlot>(), isEmpty);
      expect(slots, hasLength(30));
    });
  });

  group('a lista encolhe durante a sessão', () {
    test('apagar um post do fim não move os anúncios de cima', () {
      // Post apagado, autor bloqueado e post denunciado somem da lista sem
      // recarregar nada. Os anúncios acima do buraco não podem se mexer.
      final todos = _posts(30);
      final antes = _layout(feedWithAds(todos));

      final semUltimo = todos.take(29).toList();
      final depois = _layout(feedWithAds(semUltimo));

      final ateOBuraco = antes.indexOf('p29');
      expect(depois.take(ateOBuraco), antes.take(ateOBuraco));
    });

    test('apagar um post do meio mantém tudo acima dele', () {
      final todos = _posts(30);
      final antes = _layout(feedWithAds(todos));

      final semP10 = [...todos]..removeWhere((post) => post.id == 'p10');
      final depois = _layout(feedWithAds(semP10));

      // Tudo até o post apagado é idêntico. Abaixo dele a lista anda uma
      // posição de qualquer jeito, porque o card sumiu.
      final ateP10 = antes.indexOf('p10');
      expect(depois.take(ateP10), antes.take(ateP10));
    });
  });
}
