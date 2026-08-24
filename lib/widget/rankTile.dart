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

  @override
  Widget build(BuildContext context) {
    final name = displayName(profile);
    // Cópia local: campo de widget não promove para não-nulo, e a medalha
    // depende de comparar a posição com 3.
    final place = position;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        // A própria linha destacada: o usuário pediu para aparecer no ranking,
        // e achar-se numa lista de vinte não pode depender de ler os nomes.
        color: isMe ? Colors.blue.shade50 : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: place != null && place <= 3
                ? Image.asset(
                    place == 1
                        ? 'assets/images/OURO-MEDAL.png'
                        : place == 2
                        ? 'assets/images/PRATA-MEDAL.png'
                        : 'assets/images/BRONZE-MEDAL.png',
                    width: 25,
                    height: 25,
                  )
                : Text(
                    place == null ? '—' : '$place',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: place == null
                          ? Colors.grey.shade400
                          : Colors.grey.shade700,
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.blue.shade50,
            // Cacheado em disco: os mesmos avatares reaparecem a cada visita.
            backgroundImage: hasPhoto(profile?.photoUrl)
                ? CachedNetworkImageProvider(profile!.photoUrl!)
                : null,
            child: hasPhoto(profile?.photoUrl)
                ? null
                : Text(
                    displayInitial(name),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$name (você)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                // A amostra junto do número, sempre: "1,4%" de 40 rotas e de
                // 2 rotas são o mesmo texto e não são a mesma informação.
                Text(
                  sampleLabel(criterion, row),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _format(row.value),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
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
