import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/Utils/ranking.dart';
import 'package:iter/Utils/routePace.dart';
import 'package:iter/model/publicProfile.dart';

/// Uma linha do Ranking: posição, quem é, de onde saiu o número, e o número.
///
/// Fica fora da `RankingTab` pelo mesmo motivo que o `FriendTile` ficou fora da
/// `FriendsScreen`: aquela tela abre o Firestore no `initState`, então tudo que
/// mora dentro dela é inalcançável por teste de widget — e foi assim que a
/// legenda da amostra chegou a afirmar "0 pacotes · 17 rotas" sem nenhum teste
/// ficar vermelho. Aqui ela recebe tudo pronto e não lê nada.
///
/// Não tem margem: quem espaça as linhas é o `RankingBoard`, que as posiciona
/// uma a uma para poder animar a troca de lugar.
class RankTile extends StatelessWidget {
  const RankTile({
    super.key,
    required this.row,
    required this.criterion,
    required this.profile,
    required this.position,
    required this.isMe,
  });

  final RankRow row;
  final RankCriterion criterion;

  /// `null` é perfil que ainda não foi publicado — `displayName` resolve.
  final PublicProfile? profile;

  /// `null` é quem está no rodapé, fora da classificação.
  final int? position;

  final bool isMe;

  // Os estilos moram aqui, e não soltos no `build`, porque [heightFor] mede
  // com os mesmos. Medir com um estilo e desenhar com outro é a linha cortada
  // que a medição existe para evitar.
  static const _nameStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static const _sampleStyle = TextStyle(fontSize: 11.5);
  static const _numberStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const _unitStyle = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
  );

  static const double _avatarSize = 36;
  static const double _verticalPadding = 10;
  static const double _sampleGap = 2;

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    // O azul de `ChartPalette.azul` e do card de total do Resumo: o app não
    // ganha uma quarta cor de destaque.
    colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
  );

  /// A altura que a linha vai ocupar **com a fonte deste aparelho**.
  ///
  /// O `RankingBoard` posiciona cada linha num `y` calculado — é o que deixa a
  /// troca de critério animar o lugar. Um número fixo aqui cortaria a linha de
  /// quem usa a fonte grande do sistema, que entre entregadores não é raro.
  /// Por isso mede com `TextPainter`, o mesmo `textScaler` e o mesmo estilo
  /// efetivo (`DefaultTextStyle` mesclado) que o `Text` vai usar.
  static double heightFor(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);

    double line(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ág', style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final text = line(_nameStyle) + _sampleGap + line(_sampleStyle);
    final content = math.max(_avatarSize, math.max(text, line(_numberStyle)));
    return content + 2 * _verticalPadding;
  }

  bool get _out => position == null;

  /// O cinza do texto secundário — branco translúcido sobre o gradiente.
  Color get _faded =>
      isMe ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade600;

  @override
  Widget build(BuildContext context) {
    final name = displayName(profile);

    return Container(
      // Cada pixel horizontal aqui sai do nome: "Wesley Nogueira (você)" ao
      // lado de "5,2 min/parada" precisa de ~150 px, e com recuos mais largos
      // o "(você)" era cortado em 390 dp.
      padding: const EdgeInsets.fromLTRB(
        6,
        _verticalPadding,
        10,
        _verticalPadding,
      ),
      decoration: BoxDecoration(
        // A própria linha destacada: o usuário pediu para aparecer no ranking,
        // e achar-se numa lista de vinte não pode depender de ler os nomes. O
        // `blue.shade50` de antes sumia justamente numa lista de vinte.
        gradient: isMe ? _gradient : null,
        // As outras são **brancas**, não transparentes, mesmo sobre o corpo
        // branco: ao trocar de critério as linhas passam umas por cima das
        // outras, e transparentes os textos se misturavam no meio do caminho.
        color: isMe ? null : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isMe
            ? [
                BoxShadow(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          SizedBox(width: 26, child: Center(child: _place())),
          const SizedBox(width: 6),
          _avatar(name),
          const SizedBox(width: 10),
          // O nome e a amostra do lado elástico; só o número fica no lado
          // fixo. Num `Row`, filho sem `flex` se serve primeiro de largura
          // ilimitada e o `Expanded` fica com a sobra — então empilhar a
          // amostra à direita do número tirava do nome os pixels que a
          // legenda comprida ganhava. Medido com Roboto em 360 dp: o nome
          // caía de 194 px para 121, e "Wesley Nogueira (você)", que precisa
          // de 149, passava a ser cortado. É o mesmo arranjo do `FriendTile`:
          // quem identifica a pessoa em cima, o detalhe embaixo.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$name (você)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _nameStyle.copyWith(
                    fontWeight: isMe ? FontWeight.w700 : null,
                    color: isMe ? Colors.white : null,
                  ),
                ),
                const SizedBox(height: _sampleGap),
                // A amostra junto do número, sempre: "1,4%" de 40 rotas e de
                // 2 rotas são o mesmo texto e não são a mesma informação.
                Text(
                  sampleLabel(criterion, row),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sampleStyle.copyWith(color: _faded),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _value(),
        ],
      ),
    );
  }

  Widget _place() {
    // Cópia local: campo de widget não promove para não-nulo, e a medalha
    // depende de comparar a posição com 3.
    final place = position;

    if (place != null && place <= 3) {
      return Image.asset(
        place == 1
            ? 'assets/images/OURO-MEDAL.png'
            : place == 2
            ? 'assets/images/PRATA-MEDAL.png'
            : 'assets/images/BRONZE-MEDAL.png',
        // Só a altura: a medalha é retrato (342 × 516), e um quadrado a
        // espremia para dois terços da largura que ela tem.
        height: 28,
      );
    }

    return Text(
      place == null ? '—' : '$place',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: isMe
            ? Colors.white.withValues(alpha: place == null ? 0.75 : 1)
            : place == null
            ? Colors.grey.shade400
            : Colors.grey.shade700,
      ),
    );
  }

  Widget _avatar(String name) {
    final photo = profile?.photoUrl;

    final avatar = CircleAvatar(
      // Com o anel, o círculo encolhe o que o anel ocupa: a linha própria
      // não fica mais alta que as outras.
      radius: isMe ? _avatarSize / 2 - 2 : _avatarSize / 2,
      backgroundColor: Colors.blue.shade50,
      // Cacheado em disco: os mesmos avatares reaparecem a cada visita.
      backgroundImage: hasPhoto(photo)
          ? CachedNetworkImageProvider(photo!)
          : null,
      child: hasPhoto(photo)
          ? null
          : Text(
              displayInitial(name),
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
    );

    if (!isMe) return avatar;

    // O anel branco separa a foto do azul do gradiente — sem ele, uma foto de
    // fundo azul se dissolve na linha.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: avatar),
    );
  }

  /// O número grande e a unidade pequena — `4,9` se lê antes de `min/parada`.
  ///
  /// As duas partes saem do **mesmo** texto de `_format`, cortado no primeiro
  /// espaço. Uma segunda formatação do ritmo seria a divergência que
  /// `Utils/routePace.dart` existe para impedir. E o `Text.rich` continua
  /// sendo um texto só, `5,7 min/parada`, para quem o procura.
  Widget _value() {
    final text = _format(row.value);
    final cut = text.indexOf(' ');
    final number = cut < 0 ? text : text.substring(0, cut);
    final unit = cut < 0 ? null : text.substring(cut);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: number,
            style: _numberStyle.copyWith(
              // Fora da disputa, o número continua visível e perde a força:
              // em negrito, o 4,6 do rodapé era o número mais forte da tela e
              // parecia estar ganhando do primeiro lugar.
              fontWeight: _out ? FontWeight.w600 : null,
              color: _numberColor,
            ),
          ),
          if (unit != null)
            TextSpan(
              text: unit,
              style: _unitStyle.copyWith(color: _faded),
            ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }

  Color? get _numberColor {
    // A própria linha no rodapé: o cinza do rodapé sobre o gradiente seria o
    // número sumindo justamente na linha de quem está olhando.
    if (isMe) return Colors.white.withValues(alpha: _out ? 0.75 : 1);
    return _out ? Colors.grey.shade600 : null;
  }

  String _format(double? value) {
    if (value == null) return '—';

    return switch (criterion) {
      RankCriterion.rotas => value.toInt().toString(),
      // O mesmo "5,7 min/parada" do card da rota e do dialog de perfil.
      RankCriterion.ritmo => formatPace(value),
      RankCriterion.insucesso =>
        '${value.toStringAsFixed(1).replaceAll('.', ',')}%',
    };
  }
}
