import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/screens/addIter.dart';
import 'package:iter/widget/companyFilter.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/routeCard.dart';

class ListIterScreen extends StatefulWidget {
  const ListIterScreen({super.key, required this.user});

  final User user;

  @override
  State<ListIterScreen> createState() => _ListIterScreenState();
}

class _ListIterScreenState extends State<ListIterScreen> {
  /// Criado uma única vez: montar o stream dentro do build reinscreveria no
  /// Firestore a cada rebuild.
  late final Stream<List<NewRouteModal>> _routes = RouteController.watchAll(
    widget.user.uid,
  );

  /// Um card aberto por vez.
  String? _expandedId;

  /// `null` = todas as empresas.
  Company? _companyFilter;

  /// Respiro do fim da lista. A `GlassNavBar` flutua por cima do conteúdo
  /// (`extendBody: true` na Home), e é o próprio `Scaffold` quem informa quanto
  /// ela ocupa — assim nenhum número da barra fica duplicado aqui.
  double get _bottomGap => 24 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          // Fora do StreamBuilder: o filtro continua visível mesmo quando a
          // lista está carregando, vazia ou em erro.
          child: CompanyFilter(
            selected: _companyFilter,
            onChanged: (company) => setState(() {
              _companyFilter = company;
              _expandedId = null;
            }),
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    return StreamBuilder<List<NewRouteModal>>(
      stream: _routes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Erro ao ler as rotas: ${snapshot.error}');
          return _message(
            icon: Icons.error_outline,
            title: 'Não foi possível carregar suas rotas.',
            subtitle: kDebugMode ? '${snapshot.error}' : 'Tente novamente.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snapshot.data ?? const <NewRouteModal>[];
        if (all.isEmpty) {
          return _message(
            icon: Icons.receipt_long_outlined,
            title: 'Nenhuma rota por aqui ainda.',
            subtitle: 'Use o botão + para cadastrar a primeira.',
          );
        }

        final routes = _companyFilter == null
            ? all
            : all.where((route) => route.company == _companyFilter).toList();

        // Tem rota, só nenhuma da empresa escolhida: mandar cadastrar a
        // primeira aqui seria mentira.
        if (routes.isEmpty) {
          return _message(
            icon: Icons.filter_alt_off_outlined,
            title: 'Nenhuma rota da ${companyLabel(_companyFilter!)}.',
            subtitle: 'Toque no ícone de todas para ver a lista completa.',
          );
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 16, 16, _bottomGap),
          itemCount: routes.length,
          itemBuilder: (context, index) {
            final route = routes[index];

            // O espaçamento fica fora do Slidable, senão as ações herdam a
            // altura do card + espaço e ficam maiores que ele.
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Slidable(
                key: ValueKey(route.id),
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.45,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _editRoute(route),
                      icon: Icons.edit_outlined,
                      label: 'Editar',
                      backgroundColor: Colors.blue.shade400,
                      foregroundColor: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      padding: EdgeInsets.zero,
                    ),
                    SlidableAction(
                      onPressed: (_) => _confirmDelete(route),
                      icon: Icons.delete_outline,
                      label: 'Excluir',
                      backgroundColor: Colors.red.shade400,
                      foregroundColor: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                child: RouteCard(
                  route: route,
                  isExpanded: _expandedId == route.id,
                  onTap: () => setState(() {
                    _expandedId = _expandedId == route.id ? null : route.id;
                  }),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Abre o mesmo formulário do cadastro, agora com a rota preenchida.
  ///
  /// `push` direto em vez da rota nomeada: aqui vão dois argumentos, e
  /// `settings.arguments` só carrega um `Object?` sem verificação de tipo.
  void _editRoute(NewRouteModal route) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddIter(user: widget.user, route: route),
      ),
    );
  }

  Future<void> _confirmDelete(NewRouteModal route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir rota?'),
        content: Text(
          'A rota de ${route.dateRoute} será apagada. '
          'Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Excluir', style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await RouteController.delete(widget.user.uid, route.id);
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'success',
        msg: 'Rota excluída.',
      );
    } catch (e) {
      debugPrint('Erro ao excluir rota: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: kDebugMode
            ? 'Falha ao excluir: $e'
            : 'Não foi possível excluir a rota.',
      );
    }
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 0, 32, _bottomGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
