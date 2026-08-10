import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/friendship.dart';
import 'package:iter/Utils/ranking.dart';
import 'package:iter/controller/blockController.dart';
import 'package:iter/controller/friendController.dart';
import 'package:iter/controller/profileController.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/screens/addFriend.dart';
import 'package:iter/widget/blockDialog.dart';
import 'package:iter/widget/feedTab.dart';
import 'package:iter/widget/friendTile.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/profileDialog.dart';
import 'package:iter/widget/rankingTab.dart';
import 'package:iter/widget/segmentedSelector.dart';

enum FriendsTab { amigos, ranking, feed }

/// A aba Amigos: lista, ranking e feed, alternados pelo seletor do topo.
///
/// Ranking e Feed nascem visíveis e inertes, pelo mesmo raciocínio do menu
/// "+": informar o que vem sem precisar redesenhar depois. Ver
/// `docs/specs/amigos.md`.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.user});

  final User user;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  FriendsTab _tab = FriendsTab.amigos;

  /// Criados uma vez: montar o stream dentro do `build` reinscreveria no
  /// Firestore a cada rebuild.
  late final _friends = FriendController.watchFriends(widget.user.uid);
  late final _incoming = FriendController.watchIncoming(widget.user.uid);

  /// Um prefetch por uid, guardado aqui. Uma leitura por tile seria N idas à
  /// rede a cada rolagem.
  final Map<String, PublicProfile?> _profiles = {};
  final Set<String> _loading = {};

  /// Quem eu bloqueei.
  ///
  /// Uma assinatura e não um `StreamBuilder`, ao contrário dos outros dois
  /// streams desta tela: **duas sub-telas precisam do mesmo conjunto** — a
  /// lista, para desenhar a seção de bloqueados, e o mural, para filtrar os
  /// posts. Embrulhar as duas em mais um `StreamBuilder` empilharia um
  /// terceiro nível de aninhamento por um dado que cabe num campo.
  Set<String> _blocked = const {};
  StreamSubscription<Set<String>>? _blockedSub;

  double get _bottomGap => 24 + MediaQuery.paddingOf(context).bottom;

  @override
  void initState() {
    super.initState();
    _blockedSub = BlockController.watch(widget.user.uid).listen(
      (blocked) {
        if (!mounted) return;
        setState(() => _blocked = blocked);
      },
      // A falha esconde só a seção dela — e falha de regra do Firestore já
      // sumiu silenciosamente neste projeto antes.
      onError: (Object e) =>
          debugPrint('amigos: lista de bloqueados indisponível: $e'),
    );
  }

  @override
  void dispose() {
    _blockedSub?.cancel();
    super.dispose();
  }

  /// Busca os perfis que ainda não vieram, sem bloquear a lista.
  ///
  /// A lista desenha na hora com o que tem — o `FriendTile` sabe desenhar sem
  /// perfil — e repinta quando cada um chega.
  void _prefetch(Iterable<String> uids) {
    final missing = missingProfiles(
      uids,
      known: _profiles.keys.toSet(),
      loading: _loading,
    );
    if (missing.isEmpty) return;

    _loading.addAll(missing);
    for (final uid in missing) {
      ProfileController.fetch(uid).then((profile) {
        if (!mounted) return;
        setState(() {
          _profiles[uid] = profile;
          _loading.remove(uid);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedSelector<FriendsTab>(
            keyPrefix: 'aba',
            selected: _tab,
            onChanged: (tab) => setState(() => _tab = tab),
            segments: const [
              SegmentOption(
                value: FriendsTab.amigos,
                label: 'Amigos',
                keySuffix: 'amigos',
              ),
              SegmentOption(
                value: FriendsTab.ranking,
                label: 'Ranking',
                keySuffix: 'ranking',
              ),
              SegmentOption(
                value: FriendsTab.feed,
                label: 'Feed',
                keySuffix: 'feed',
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            FriendsTab.amigos => _friendsTab(),
            FriendsTab.ranking => _rankingTab(),
            FriendsTab.feed => FeedTab(
              uid: widget.user.uid,
              // O mesmo mapa da lista e do ranking. Um cache próprio no feed
              // morreria a cada troca de aba e releria perfis que este já tem.
              profiles: _profiles,
              blocked: _blocked,
              onNeedProfiles: _prefetch,
              bottomGap: _bottomGap,
            ),
          },
        ),
      ],
    );
  }

  /// O ranking precisa da lista de amigos, então nasce dentro do mesmo stream.
  ///
  /// **Sem `ValueKey`.** Uma key derivada da lista destruiria o `State` a cada
  /// mudança, e com ele o mês e o critério que o usuário escolheu: aceitar um
  /// convite jogaria a tela de volta para Agosto/Rotas sem ele ter tocado em
  /// nada. Quem recarrega é o `didUpdateWidget` da própria aba.
  Widget _rankingTab() {
    return StreamBuilder<List<String>>(
      stream: _friends,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final friends = snapshot.data ?? const <String>[];

        // A mesma lista que a `RankingTab` usa para buscar os baldes. Duas
        // listas de participantes montadas em dois lugares foi o que deixou o
        // dono aparecer como "Entregador" no próprio ranking.
        _prefetch(rankingParticipants(widget.user.uid, friends));

        return RankingTab(
          uid: widget.user.uid,
          friends: friends,
          profiles: _profiles,
          bottomGap: _bottomGap,
        );
      },
    );
  }

  Widget _friendsTab() {
    return StreamBuilder<List<String>>(
      stream: _friends,
      builder: (context, friendsSnapshot) {
        if (friendsSnapshot.hasError) {
          // Falha de regra do Firestore já sumiu silenciosamente neste
          // projeto antes.
          debugPrint('amigos: lista indisponível: ${friendsSnapshot.error}');
          return _erro('Não foi possível carregar seus amigos.');
        }
        if (friendsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final friends = friendsSnapshot.data ?? const <String>[];

        return StreamBuilder<List<String>>(
          stream: _incoming,
          builder: (context, incomingSnapshot) {
            // A falha de um stream esconde só a seção dele: convite quebrado
            // não pode apagar a lista de amigos.
            if (incomingSnapshot.hasError) {
              debugPrint('amigos: convites: ${incomingSnapshot.error}');
            }

            final pending = FriendController.pendingOnly(
              incomingSnapshot.data ?? const <String>[],
              friends,
            );

            _prefetch([...friends, ...pending, ..._blocked]);

            if (friends.isEmpty && pending.isEmpty && _blocked.isEmpty) {
              return _vazio();
            }

            return ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, _bottomGap),
              children: [
                if (pending.isNotEmpty) ...[
                  _secao('CONVITES (${pending.length})'),
                  for (final uid in pending) _convite(uid),
                  const SizedBox(height: 20),
                ],
                if (friends.isNotEmpty) ...[
                  _secao('MEUS AMIGOS (${friends.length})'),
                  for (final uid in friends) _amigo(uid),
                ],
                // Bloquear sem ter como desbloquear é uma armadilha: a lista
                // fica aqui, embaixo, e só aparece quando existe.
                if (_blocked.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _secao('BLOQUEADOS (${_blocked.length})'),
                  for (final uid in _blocked) _bloqueado(uid),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _secao(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _convite(String uid) {
    return FriendTile(
      uid: uid,
      profile: _profiles[uid],
      // Aceitar ou recusar sem saber de quem é não é decisão, é chute. O
      // toque abre o mesmo dialog que a busca abre antes de convidar.
      onTap: () => _openProfile(uid, status: FriendshipStatus.convidou),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('aceitar-$uid'),
            tooltip: 'Aceitar',
            icon: Icon(Icons.check_circle_outline, color: Colors.green.shade600),
            onPressed: () => _run(
              () => FriendController.accept(me: widget.user.uid, other: uid),
              'Vocês agora são amigos.',
            ),
          ),
          IconButton(
            key: ValueKey('recusar-$uid'),
            tooltip: 'Recusar',
            icon: Icon(Icons.close, color: Colors.grey.shade600),
            onPressed: () => _run(
              () => FriendController.decline(me: widget.user.uid, other: uid),
              'Convite recusado.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _amigo(String uid) {
    return FriendTile(
      uid: uid,
      profile: _profiles[uid],
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () => _openProfile(uid, status: FriendshipStatus.amigo),
    );
  }

  /// Sem `onTap`: o dialog de perfil de quem eu bloqueei ofereceria
  /// "Adicionar" — a tela convidando para desfazer o que a pessoa acabou de
  /// fazer, e um convite que a própria regra recusa.
  Widget _bloqueado(String uid) {
    return FriendTile(
      uid: uid,
      profile: _profiles[uid],
      trailing: TextButton(
        key: ValueKey('desbloquear-$uid'),
        onPressed: () => _run(
          () => BlockController.unblock(me: widget.user.uid, other: uid),
          // Não diz "vocês voltaram a ser amigos": a amizade foi desfeita no
          // bloqueio, e ressuscitá-la sozinha seria decidir pelo outro lado.
          'Desbloqueado. Vocês podem se convidar de novo.',
        ),
        child: const Text('Desbloquear'),
      ),
    );
  }

  /// O mesmo dialog que a busca usa, com o rótulo que a relação pede.
  ///
  /// O `actionLabel` vem de `FriendshipStatus` e não de um literal aqui: são
  /// as mesmas quatro frases da tela de busca, e duas listas de rótulo para o
  /// mesmo conceito divergem na primeira vez que alguém edita uma só.
  void _openProfile(String uid, {required FriendshipStatus status}) {
    final profile = _profiles[uid];
    final name = profile?.name.isNotEmpty == true ? profile!.name : 'Entregador';

    showProfileDialog(
      context,
      name: name,
      nickName: profile?.nickName,
      photoUrl: profile?.photoUrl,
      // Sem fabricar zeros: `null` chega ao dialog como "não posso ver".
      stats: ProfileController.fetchCareer(uid),
      actionLabel: status.actionLabel ?? 'Fechar',
      // É daqui que se bloqueia quem insiste em convidar: recusar sozinho não
      // resolve, porque quem é recusado reconvida e o badge acende de novo.
      onBlock: () {
        Navigator.of(context).pop();
        _blockFrom(uid, name);
      },
      onAction: () {
        Navigator.of(context).pop();
        switch (status) {
          case FriendshipStatus.convidou:
            _run(
              () => FriendController.accept(me: widget.user.uid, other: uid),
              'Vocês agora são amigos.',
            );
          case FriendshipStatus.amigo:
            _run(
              () => FriendController.remove(me: widget.user.uid, other: uid),
              'Amizade desfeita.',
            );
          default:
            break;
        }
      },
    );
  }

  /// Bloquear a partir do dialog de perfil.
  ///
  /// Passa pela mesma confirmação do mural: bloquear **apaga a amizade e os
  /// convites**, e essa consequência não pode aparecer só num dos dois lugares
  /// de onde se bloqueia.
  Future<void> _blockFrom(String uid, String name) async {
    final ok = await confirmBlock(context, name: name);
    if (ok != true || !mounted) return;

    await _run(
      () => BlockController.block(me: widget.user.uid, other: uid),
      '$name foi bloqueado.',
    );
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    final ok = await FriendController.tryRun(action);
    if (!mounted) return;

    showNotification(
      context: context,
      type: ok ? 'success' : 'error',
      msg: ok ? success : 'Não foi possível concluir. Tente de novo.',
    );
  }

  Widget _erro(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _vazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Você ainda não tem amigos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Peça o @apelido do colega e busque por ele para convidar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('adicionar-amigo-vazio'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddFriend(uid: widget.user.uid),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_outlined),
              label: const Text('Adicionar amigo'),
            ),
          ],
        ),
      ),
    );
  }
}
