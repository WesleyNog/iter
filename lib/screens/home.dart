import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/friendShare.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/controller/friendController.dart';
import 'package:iter/controller/profileController.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/controller/userController.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/users.dart';
import 'package:iter/screens/addFriend.dart';
import 'package:iter/screens/friendsScreen.dart';
import 'package:iter/screens/graficsScreen.dart';
import 'package:iter/screens/addMaintenance.dart';
import 'package:iter/screens/addSupply.dart';
import 'package:iter/screens/listIterScreen.dart';
import 'package:iter/screens/summaryScreen.dart';
import 'package:iter/screens/vehiclesScreen.dart';
import 'package:iter/services/authService.dart';
import 'package:iter/widget/createActionSheet.dart';
import 'package:iter/widget/glassNavBar.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/profileDialog.dart';
import 'package:iter/widget/vehicleAvatar.dart';
import 'package:share_plus/share_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  /// Usuário autenticado, entregue pelo AuthGate.
  final User user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSigningOut = false;
  int _currentIndex = 0;

  late final _grafics = GraficsScreen(user: widget.user);
  late final _listIter = ListIterScreen(user: widget.user);
  late final _friends = FriendsScreen(user: widget.user);
  late final _summary = SummaryScreen(user: widget.user);

  /// Convites recebidos, só para o badge da navBar.
  ///
  /// Fica aqui e não na aba porque o badge tem de acender **sem** o usuário
  /// estar em Amigos. É a coleção mais barata do app — um documento por
  /// convite pendente.
  late final Stream<List<String>> _incoming = FriendController.watchIncoming(
    widget.user.uid,
  );

  /// Criado uma única vez: montar o stream dentro do build reinscreveria no
  /// Firestore a cada rebuild.
  late final Stream<Users?> _profile = UserController.watch(widget.user.uid);

  @override
  void initState() {
    super.initState();
    _publishPublicProfile();
  }

  /// Publica `profiles/{uid}` na abertura do app.
  ///
  /// **Aqui e não no login.** `signInWithGoogle()` só roda quando a
  /// `LoginScreen` o chama, e quem já tem sessão cai direto aqui pelo
  /// `AuthGate` — é exatamente por isso que `user/{uid}` está congelado desde
  /// o primeiro dia, e repetir o erro deixaria a busca por apelido sem
  /// encontrar ninguém que já usava o app.
  ///
  /// Fora do `build` porque é escrita: o `StreamBuilder` da AppBar reconstrói
  /// a cada mudança do perfil, e publicar de lá viraria laço.
  ///
  /// Silencioso de propósito. A projeção é conveniência para os outros; o app
  /// do dono funciona inteiro sem ela, e um toast de erro na abertura seria
  /// ruído sobre algo que ele não pode resolver.
  Future<void> _publishPublicProfile() async {
    try {
      // O `User` em memória é cache: sem `reload`, trocar a foto no Google não
      // chega aqui, e a projeção nasceria velha de novo.
      await widget.user.reload();
      final user = FirebaseAuth.instance.currentUser ?? widget.user;

      final results = await Future.wait([
        UserController.fetch(user.uid),
        RouteController.fetchAll(user.uid),
      ]);

      final profile = results[0] as Users?;
      final routes = results[1] as List<NewRouteModal>;

      await ProfileController.publish(
        user: user,
        routes: routes,
        // Sem apelido ninguém acha esse perfil na busca — mas publicar o resto
        // ainda vale: nome e foto sustentam a lista de quem já é amigo.
        nickName: profile?.nickName,
      );
    } catch (e) {
      debugPrint('profiles: não foi possível publicar na abertura: $e');
    }
  }

  String get _firstName {
    final name = widget.user.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name.split(' ').first;

    final email = widget.user.email ?? '';
    return email.isNotEmpty ? email.split('@').first : 'Bem-vindo';
  }

  String get _fullName {
    final name = widget.user.displayName?.trim() ?? '';
    return name.isEmpty ? _firstName : name;
  }

  /// Abre o perfil já com nome e foto — que a AppBar tem de graça — e busca só
  /// as métricas.
  ///
  /// `fetchAll` e não `watchAll`: a lista e os gráficos já mantêm um listener
  /// cada nesta coleção, e um terceiro permanente para um dialog que quase
  /// nunca abre seria escuta parada consumindo à toa. A leitura única sai do
  /// cache que os outros dois já preencheram.
  void _openProfile(String? nickName) {
    showProfileDialog(
      context,
      name: _fullName,
      nickName: nickName,
      photoUrl: widget.user.photoURL,
      stats: RouteController.fetchAll(widget.user.uid).then(profileStats),
      actionLabel: 'Compartilhar',
      // Sem apelido não há o que compartilhar nem o que virar QR: a busca do
      // outro lado é por `nicknames/{apelido}`. Na prática ele sempre existe
      // — o login reserva um —, e `null` aqui é o perfil que ainda não
      // carregou. Botão apagado diz isso melhor do que um QR de string vazia.
      onAction: nickName == null ? null : () => _shareProfile(nickName),
      qrPayload: nickName == null ? null : friendQrPayload(nickName),
    );
  }

  /// Manda o convite para fora do app.
  ///
  /// A folha nativa é quem oferece WhatsApp, Instagram, e-mail e "copiar" —
  /// com os apps que a pessoa tem de fato instalados. Um botão por rede aqui
  /// seria uma lista para manter e um esquema de URL para quebrar sozinho.
  Future<void> _shareProfile(String nickName) async {
    // No iPad a folha é um **popover**, e popover sem âncora derruba o app com
    // exceção nativa. O `TARGETED_DEVICE_FAMILY` do projeto é "1,2", então o
    // iPad é destino declarado, mesmo que ninguém teste nele. No iPhone o
    // parâmetro é ignorado.
    final box = context.findRenderObject() as RenderBox?;

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: friendShareText(nickName, name: _fullName),
          subject: 'Me adiciona no iter',
          sharePositionOrigin: box == null || !box.hasSize
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      debugPrint('compartilhar perfil falhou: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível abrir o compartilhamento.',
      );
    }
  }

  /// Menu do "+".
  ///
  /// As três primeiras são o que o app **registra**, na ordem em que registra.
  /// "Adicionar amigo" fecha a lista porque não é registro: é a única entrada
  /// que não grava nada do dia de trabalho.
  void _showCreateMenu() {
    showCreateActionSheet(
      context,
      actions: [
        CreateAction(
          icon: Icons.local_shipping_outlined,
          color: Colors.green,
          title: 'Nova rota',
          subtitle: 'Cadastrar uma rota',
          // Rota nomeada, e não `push`: o AddIter volta com
          // `popUntil((route) => route.isFirst)` e o AuthGate segue de pé.
          onTap: () => Navigator.of(
            context,
          ).pushNamed('/addIter', arguments: widget.user),
        ),
        CreateAction(
          icon: Icons.local_gas_station_outlined,
          color: Colors.orange,
          title: 'Abastecimento',
          subtitle: 'Registrar combustível',
          // `push` normal: a tela volta com `pop` e o AuthGate, que vive na
          // primeira rota, segue de pé.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddSupply(uid: widget.user.uid)),
          ),
        ),
        CreateAction(
          icon: Icons.build_outlined,
          color: Colors.blueGrey,
          title: 'Manutenção',
          subtitle: 'Registrar manutenção',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddMaintenance(uid: widget.user.uid),
            ),
          ),
        ),
        CreateAction(
          icon: Icons.person_add_alt_outlined,
          color: Colors.indigo,
          title: 'Adicionar amigo',
          subtitle: 'Buscar pelo @apelido',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddFriend(uid: widget.user.uid)),
          ),
        ),
      ],
    );
  }

  /// `push` normal: a tela de veículos volta com `pop` e o AuthGate, que vive
  /// na primeira rota, segue de pé.
  void _openVehicles() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VehiclesScreen(uid: widget.user.uid)),
    );
  }

  Future<void> _handleSignOut() async {
    setState(() => _isSigningOut = true);

    try {
      // Não navega: o AuthGate volta para o login ao receber o novo estado.
      await GoogleSignInService.signOut();
    } catch (e) {
      debugPrint('Erro ao sair: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível sair. Tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.user.photoURL;
    final List<Widget> screens = [_grafics, _listIter, _summary, _friends];
    final current = _currentIndex.clamp(0, screens.length - 1);
    return Scaffold(
      // A GlassNavBar é uma pílula flutuante: sem isto ela reservaria a própria
      // altura no layout, encostando na última linha de conteúdo, e o blur não
      // teria nada atrás para borrar. As telas roláveis compensam com o respiro
      // que o Scaffold anuncia em `MediaQuery.paddingOf(context).bottom`.
      extendBody: true,
      // Um StreamBuilder para a AppBar inteira, e não só para o título: o
      // avatar precisa do apelido para levá-lo ao dialog de perfil, e o botão
      // de veículos precisa do `activeVehicleId`, que mora no mesmo documento.
      // Dois StreamBuilder seriam duas escutas de `user/{uid}`.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: StreamBuilder<Users?>(
          stream: _profile,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint('Erro ao ler o perfil: ${snapshot.error}');
            }

            final nickName = snapshot.data?.nickName;
            final hasNickName = nickName != null && nickName.isNotEmpty;

            return AppBar(
              titleSpacing: 16,
              title: Row(
                children: [
                  InkWell(
                    onTap: () => _openProfile(nickName),
                    customBorder: const CircleBorder(),
                    child: Tooltip(
                      message: 'Ver perfil',
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.blue.shade100,
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Text(
                                _firstName.characters.first.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Olá,',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: _firstName),
                              if (hasNickName)
                                TextSpan(
                                  text: '  |  @$nickName',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                VehicleAvatar(
                  uid: widget.user.uid,
                  activeVehicleId: snapshot.data?.activeVehicleId,
                  onTap: _openVehicles,
                ),
                IconButton(
                  tooltip: 'Sair',
                  onPressed: _isSigningOut ? null : _handleSignOut,
                  icon: _isSigningOut
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout),
                ),
              ],
            );
          },
        ),
      ),
      body: screens[current],
      bottomNavigationBar: StreamBuilder<List<String>>(
        stream: _incoming,
        builder: (context, snapshot) =>
            _navBar(current, pending: snapshot.data?.length ?? 0),
      ),
    );
  }

  /// O gancho do badge já existia na `GlassNavBar` e nunca tinha sido usado.
  Widget _navBar(int current, {required int pending}) {
    return GlassNavBar(
      currentIndex: current,
      pendingIndex: 3,
      pendingCount: pending,
      trailing: GlassCircleButton(
        icon: Icons.add_rounded,
        iconColor: Colors.green,
        tooltip: "Criar",
        onTap: _showCreateMenu,
      ),
      items: [
        const GlassNavItem(icon: Icons.bar_chart, label: "Gráfico"),
        const GlassNavItem(icon: Icons.receipt_long, label: "Lista"),
        const GlassNavItem(icon: Icons.data_saver_off_rounded, label: "Resumo"),
        const GlassNavItem(icon: Icons.people, label: "Amigos"),
      ],
      onTap: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
    );
  }
}
