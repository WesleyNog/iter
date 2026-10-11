import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/model/publicProfile.dart';

/// A foto de um perfil público, ou a inicial do nome quando não há foto.
///
/// Nasceu com o redesenho do Feed, que desenhava o mesmo `CircleAvatar` em três
/// lugares — o card do post, o compositor e cada comentário. O `FriendTile` e
/// o `RankTile` ainda montam o deles; passam a usar este quando forem mexidos.
///
/// Cacheado em disco: o avatar é justamente a imagem que se repete, e
/// `NetworkImage` só guarda em memória.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    required this.radius,
    this.fallbackName,
  });

  /// `null` é projeção ainda não publicada — desenha a inicial genérica.
  final PublicProfile? profile;
  final double radius;

  /// O nome a usar quando não há perfil. Por padrão, o de `displayName`.
  final String? fallbackName;

  @override
  Widget build(BuildContext context) {
    final photo = profile?.photoUrl;
    final name = fallbackName ?? displayName(profile);

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.blue.shade50,
      backgroundImage: hasPhoto(photo)
          ? CachedNetworkImageProvider(photo!)
          : null,
      child: hasPhoto(photo)
          ? null
          : Text(
              displayInitial(name),
              style: TextStyle(
                fontSize: radius * 0.8,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
