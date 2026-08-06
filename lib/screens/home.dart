import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/controller/userController.dart';
import 'package:iter/model/users.dart';
import 'package:iter/screens/friendsScreen.dart';
import 'package:iter/screens/graficsScreen.dart';
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
  final _friends = FriendsScreen();
  late final _summary = SummaryScreen(user: widget.user);

  /// Criado uma única vez: montar o stream dentro do build reinscreveria no
  /// Firestore a cada rebuild.
  late final Stream<Users?> _profile = UserController.watch(widget.user.uid);

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
      onAction: () => showNotification(
        context: context,
        type: 'info',
        msg: 'Compartilhar perfil está em desenvolvimento.',
      ),
    );
  }

  /// Menu do "+": hoje só a rota está pronta; abastecimento e manutenção entram
  /// sem `onTap` e aparecem com o selo "Em breve" até ganharem tela.
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
        const CreateAction(
          icon: Icons.build_outlined,
          color: Colors.blueGrey,
          title: 'Manutenção',
          subtitle: 'Registrar manutenção',
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
      bottomNavigationBar: GlassNavBar(
        currentIndex: current,
        trailing: GlassCircleButton(
          icon: Icons.add_rounded,
          iconColor: Colors.green,
          tooltip: "Criar",
          onTap: _showCreateMenu,
        ),
        items: [
          const GlassNavItem(icon: Icons.bar_chart, label: "Gráfico"),
          const GlassNavItem(icon: Icons.receipt_long, label: "Lista"),
          const GlassNavItem(
            icon: Icons.data_saver_off_rounded,
            label: "Resumo",
          ),
          const GlassNavItem(icon: Icons.people, label: "Amigos"),
        ],
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
