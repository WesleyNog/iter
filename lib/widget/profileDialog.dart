import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/Utils/routeTime.dart';

/// Perfil do entregador, quase em tela cheia.
///
/// O widget **recebe** tudo que mostra e não lê o usuário logado por dentro:
/// assim dá para testá-lo sem Firebase, e a aba Friends só vai precisar passar
/// outro uid. O botão de ação também é parâmetro — "Compartilhar" hoje,
/// "Seguir" amanhã, sem tocar aqui.
Future<void> showProfileDialog(
  BuildContext context, {
  required String name,
  String? nickName,
  String? photoUrl,
  required Future<ProfileStats?> stats,
  required String actionLabel,
  VoidCallback? onAction,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ProfileDialog(
      name: name,
      nickName: nickName,
      photoUrl: photoUrl,
      stats: stats,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

class ProfileDialog extends StatelessWidget {
  const ProfileDialog({
    super.key,
    required this.name,
    required this.stats,
    required this.actionLabel,
    this.onAction,
    this.nickName,
    this.photoUrl,
  });

  final String name;
  final String? nickName;
  final String? photoUrl;

  /// Nome e foto já vêm da AppBar e aparecem na hora; só os números esperam o
  /// Firestore. Segurar o dialog fechado por meio segundo faz o toque parecer
  /// que não funcionou.
  ///
  /// Resolver em `null` significa **"não posso ver"**, não "zero": os números
  /// de carreira são legíveis só por amigos, e mostrar zeros para um
  /// desconhecido seria dizer que ele nunca rodou.
  final Future<ProfileStats?> stats;

  final String actionLabel;

  /// `null` desabilita o botão de verdade.
  ///
  /// É o que a aba Amigos precisa para o perfil do próprio usuário: um
  /// `onPressed` vazio deixaria o botão clicável sem efeito, que é pior do que
  /// apagado — parece que o toque não funcionou.
  final VoidCallback? onAction;

  static const _bannerHeight = 116.0;
  static const _avatarRadius = 46.0;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            const SizedBox(height: 10),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (nickName != null && nickName!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '@$nickName',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _stats(),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    actionLabel.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner com a foto cavalgando a borda de baixo.
  ///
  /// A altura reservada é a do banner **mais** o pedaço da foto que vaza, para
  /// nada depender de o `Stack` conseguir desenhar fora do card — o `Dialog`
  /// recorta nos cantos arredondados.
  Widget _header(BuildContext context) {
    return SizedBox(
      height: _bannerHeight + _avatarRadius,
      child: Stack(
        children: [
          Container(
            height: _bannerHeight,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0D47A1),
                  Color(0xFF1976D2),
                  Color(0xFF42A5F5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            top: _bannerHeight - _avatarRadius,
            left: 0,
            right: 0,
            child: Center(child: _avatar()),
          ),
        ],
      ),
    );
  }

  Widget _avatar() {
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();

    return CircleAvatar(
      radius: _avatarRadius,
      backgroundColor: Colors.white,
      child: CircleAvatar(
        radius: _avatarRadius - 4,
        backgroundColor: Colors.blue.shade100,
        backgroundImage: hasPhoto ? NetworkImage(url) : null,
        child: hasPhoto
            ? null
            : Text(
                initial,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _stats() {
    return FutureBuilder<ProfileStats?>(
      future: stats,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Erro ao ler as métricas do perfil: ${snapshot.error}');
          return _note(
            kDebugMode
                ? '${snapshot.error}'
                : 'Não foi possível carregar suas métricas.',
          );
        }

        // "Ainda não chegou" e "não posso ver" são estados diferentes, e o
        // `data == null` sozinho os confundiria — o shimmer ficaria para
        // sempre em quem não é amigo.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _StatsPlaceholder();
        }

        final data = snapshot.data;
        if (data == null) {
          return _note('Os números aparecem depois que vocês forem amigos.');
        }

        return Column(
          children: [
            Row(
              children: [
                _bigStat('${data.routes}', 'Rotas'),
                _bigStat('${data.deliveredPackages}', 'Pacotes'),
                _bigStat('${data.stops}', 'Paradas'),
              ],
            ),
            const SizedBox(height: 18),
            Divider(color: Colors.grey.shade200, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                _smallStat(
                  Icons.report_gmailerrorred_outlined,
                  'Insucesso',
                  data.failureRate == null
                      ? '—'
                      : '${data.failureRate!.toStringAsFixed(1)}%',
                ),
                _smallStat(
                  Icons.local_shipping_outlined,
                  'Mais rodada',
                  data.topCompany == null
                      ? '—'
                      : '${data.topCompany!.label}\n'
                            '${data.topCompany!.share.toStringAsFixed(0)}%',
                ),
                _smallStat(
                  Icons.timer_outlined,
                  'Tempo médio',
                  _duration(data.averageDuration),
                ),
              ],
            ),
            if (data.routes == 0) ...[
              const SizedBox(height: 16),
              _note('Cadastre sua primeira rota para ver seus números.'),
            ],
          ],
        );
      },
    );
  }

  /// O mesmo formato da lista e do ranking (`9h30`, `45min`).
  String _duration(Duration? average) {
    if (average == null) return '—';
    return RouteTime.formatMinutes(average.inMinutes);
  }

  Widget _bigStat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1976D2),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _smallStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _note(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
    );
  }
}

/// Espaço dos números enquanto o Firestore responde, com a mesma altura do
/// conteúdo final para o dialog não pular de tamanho ao carregar.
class _StatsPlaceholder extends StatelessWidget {
  const _StatsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}
