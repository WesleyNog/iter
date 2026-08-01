import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iter/controller/userController.dart';
import 'package:iter/model/users.dart';
import 'package:iter/screens/graficsScreen.dart';
import 'package:iter/screens/listIterScreen.dart';
import 'package:iter/screens/socialScreen.dart';
import 'package:iter/services/authService.dart';
import 'package:iter/widget/glassNavBar.dart';
import 'package:iter/widget/notificationPush.dart';

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

  final _grafics = GraficsScreen();
  late final _listIter = ListIterScreen(user: widget.user);
  final _social = SocialScreen();

  /// Criado uma única vez: montar o stream dentro do build reinscreveria no
  /// Firestore a cada rebuild.
  late final Stream<Users?> _profile = UserController.watch(widget.user.uid);

  String get _firstName {
    final name = widget.user.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name.split(' ').first;

    final email = widget.user.email ?? '';
    return email.isNotEmpty ? email.split('@').first : 'Bem-vindo';
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
    final List<Widget> screens = [_grafics, _listIter, _social];
    final current = _currentIndex.clamp(0, screens.length - 1);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blue.shade100,
              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                  ? NetworkImage(photoUrl)
                  : null,
              child: photoUrl == null || photoUrl.isEmpty
                  ? Text(
                      _firstName.characters.first.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Olá,',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  StreamBuilder<Users?>(
                    stream: _profile,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        debugPrint('Erro ao ler o perfil: ${snapshot.error}');
                      }

                      final nickName = snapshot.data?.nickName;
                      final hasNickName =
                          nickName != null && nickName.isNotEmpty;

                      return Text.rich(
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
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
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
      ),
      body: screens[current],
      bottomNavigationBar: GlassNavBar(
        currentIndex: current,
        trailing: GlassCircleButton(
          icon: Icons.add_rounded,
          iconColor: Colors.green,
          tooltip: "Criar",
          onTap: () => Navigator.of(
            context,
          ).pushNamed('/addIter', arguments: widget.user),
        ),
        items: [
          const GlassNavItem(icon: Icons.bar_chart, label: "Gráfico"),
          const GlassNavItem(icon: Icons.receipt_long, label: "Lista"),
          const GlassNavItem(icon: Icons.comment_outlined, label: "Social"),
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
