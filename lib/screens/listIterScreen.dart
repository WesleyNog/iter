import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:iter/Utils/routeFilter.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/screens/addIter.dart';
import 'package:iter/widget/companyFilter.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/routeCard.dart';
import 'package:iter/widget/routeFilterSheet.dart';
import 'package:iter/widget/routeSlidable.dart';

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

  /// Tudo o que está cortando a lista, num objeto só — empresa, status,
  /// período, veículo, faixa de valor e ordem.
  ///
  /// Não é gravado em disco de propósito: filtro que sobrevive ao fechamento do
  /// app é a origem clássica do "sumiram minhas rotas" uma semana depois.
  ///
  /// Ele também **não** sobrevive a trocar de aba: `home.dart` monta
  /// `body: screens[current]`, não um `IndexedStack`, então o elemento desta
  /// tela é desmontado na troca e este `State` vai junto. Guardar o *widget*
  /// num campo `late final` preserva o widget, nunca o estado. É o mesmo motivo
  /// pelo qual `_expandedId` já voltava fechado, muito antes deste filtro
  /// existir.
  RouteFilter _filter = RouteFilter.none;

  /// Os veículos do usuário, para a folha conseguir **nomear** o filtro —
  /// `provision` guarda só o id.
  ///
  /// `null` é **não deu para saber**: a primeira leitura ainda não chegou, ou
  /// falhou. Nunca "não tem veículo" — a folha desenha as duas coisas com
  /// frases diferentes, e colapsá-las esconderia a seção de quem tem carro e
  /// está sem sinal.
  ///
  /// Assinado uma vez, e não lido com um `get()` a cada abertura da folha: isso
  /// seria uma consulta nova por toque no ícone, que é o que
  /// `docs/specs/filtros.md` põe em "Nunca", e obrigaria a folha a esperar a
  /// rede para aparecer — dois toques durante a espera empilhavam duas folhas,
  /// e confirmar a de baixo depois desfazia a escolha feita na de cima. Sem
  /// `await` antes de abrir, esse caminho deixa de existir.
  List<Vehicle>? _vehicles;
  StreamSubscription<List<Vehicle>>? _vehicleSub;

  /// A última lista **completa** que o stream entregou.
  ///
  /// A folha de filtros precisa dela inteira, sem filtro nenhum: é de lá que
  /// saem os limites da faixa de valor e os veículos que já rodaram. Com a
  /// lista já filtrada, o trilho da faixa encolheria a cada aplicação e a alça
  /// que o usuário acabou de arrastar sairia dele.
  List<NewRouteModal> _allRoutes = const [];

  @override
  void initState() {
    super.initState();
    // Sem `setState`: nada nesta tela desenha veículo. Quem precisa deles é a
    // folha, no instante em que ela abre.
    _vehicleSub = VehicleController.watchAll(widget.user.uid).listen(
      (vehicles) => _vehicles = vehicles,
      onError: (Object error) => debugPrint('Erro ao ler os veículos: $error'),
    );
  }

  @override
  void dispose() {
    _vehicleSub?.cancel();
    super.dispose();
  }

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
          child: Row(
            children: [
              // `Expanded`: o trilho fica com toda a largura que sobra do
              // ícone, seja qual for o tamanho que a fonte do aparelho der aos
              // três rótulos.
              Expanded(
                child: CompanyFilter(
                  selected: _filter.companies,
                  // O widget só avisa em qual empresa o usuário tocou — quem
                  // alterna é `toggleCompany`, a mesma regra que a folha usa
                  // no status.
                  onToggle: (company) => _apply(_filter.toggleCompany(company)),
                ),
              ),
              const SizedBox(width: 8),
              _filterButton(),
            ],
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  /// O ícone que abre os filtros que não cabem no trilho, com o número de
  /// eixos ligados.
  ///
  /// Sem o badge o entregador fecha a folha e não tem como saber que sobrou um
  /// status marcado — e vai jurar que sumiu rota. O número conta **eixos**, não
  /// opções marcadas, e a empresa fica de fora porque ela está desenhada no
  /// trilho ao lado, marcada; quem faz essa conta é `RouteFilter.extraCount`.
  ///
  /// Zero não desenha badge nenhum: um "0" pendurado no ícone é ruído
  /// justamente no estado em que a lista está inteira.
  Widget _filterButton() {
    final button = IconButton(
      key: const ValueKey('abrir-filtros'),
      onPressed: _openFilterSheet,
      icon: const Icon(Icons.tune),
      tooltip: 'Mais filtros',
    );

    final extra = _filter.extraCount;
    if (extra == 0) return button;

    return Badge(
      backgroundColor: Colors.red.shade500,
      label: Text(
        '$extra',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
      child: button,
    );
  }

  Future<void> _openFilterSheet() async {
    final chosen = await showRouteFilterSheet(
      context,
      current: _filter,
      routes: _allRoutes,
      vehicles: _vehicles,
    );

    // `null` é a folha descartada — arrastada para baixo ou fechada por um
    // toque fora. Nada muda.
    if (chosen == null || !mounted) return;
    _apply(chosen);
  }

  /// O único caminho para trocar de filtro.
  ///
  /// Fechar o card expandido junto não é enfeite: com outro recorte a lista
  /// muda de tamanho embaixo dele, e o card que continuava aberto seria de uma
  /// rota que o usuário nem está mais vendo.
  void _apply(RouteFilter next) => setState(() {
    _filter = next;
    _expandedId = null;
  });

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

        // Guardado **sem** `setState`: quem redesenha esta parte da tela já é o
        // próprio StreamBuilder, e um `setState` daqui seria pedir rebuild de
        // dentro do build. É só uma referência para a folha de filtros ler
        // quando abrir.
        _allRoutes = all;

        if (all.isEmpty) {
          return _message(
            icon: Icons.receipt_long_outlined,
            title: 'Nenhuma rota por aqui ainda.',
            subtitle: 'Use o botão + para cadastrar a primeira.',
          );
        }

        final routes = applyFilter(all, _filter);

        // Tem rota, só nenhuma passando nos filtros: mandar cadastrar a
        // primeira aqui seria mentira. O botão existe porque desmarcar cinco
        // coisas na mão para voltar a enxergar a lista é o caminho que ninguém
        // percorre — e a tela não diz qual eixo cortou porque são cinco, e
        // nomeá-los todos é a folha, não uma frase.
        if (routes.isEmpty) {
          return _message(
            icon: Icons.filter_alt_off_outlined,
            title: 'Nenhuma rota com os filtros atuais.',
            subtitle:
                'Ajuste os filtros ou limpe tudo para ver a lista '
                'completa.',
            action: TextButton.icon(
              key: const ValueKey('limpar-filtros'),
              onPressed: () => _apply(RouteFilter.none),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Limpar filtros'),
            ),
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
              child: RouteSlidable(
                route: route,
                onEdit: () => _editRoute(route),
                onDelete: () => _confirmDelete(route),
                onMarkPaid: () => _markPaid(route),
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
        builder: (_) => AddIter(uid: widget.user.uid, route: route),
      ),
    );
  }

  /// Concluída → paga, sem abrir o formulário.
  ///
  /// Grava **só** o campo de status (`RouteController.updateStatus`), então a
  /// provisão congelada, o valor e o `noRoutePayment` não são nem enviados — o
  /// atalho não tem como reescrevê-los. Quem decide que a rota pode receber
  /// isso é `RouteSlidable.canMarkPaid`, e a razão está lá.
  ///
  /// O desfazer não é enfeite: é um gesto de deslizar, fácil de disparar sem
  /// querer, e ele move a rota de "a receber" para "pago" no Resumo. Voltar é a
  /// mesma troca pura de status na direção contrária, então custa o mesmo e
  /// dispensa uma confirmação que anularia o ganho de ser rápido.
  Future<void> _markPaid(NewRouteModal route) =>
      _changeStatus(route, StatusRoute.pago, 'Rota marcada como paga.');

  Future<void> _changeStatus(
    NewRouteModal route,
    StatusRoute status,
    String message,
  ) async {
    final previous = route.status;

    try {
      await RouteController.updateStatus(widget.user.uid, route.id, status);
      if (!mounted) return;

      showNotification(
        context: context,
        type: 'success',
        msg: message,
        learnMoreText: 'Desfazer',
        onLearnMoreTap: () =>
            _changeStatus(route, previous, 'Status desfeito.'),
      );
    } catch (e) {
      debugPrint('Erro ao trocar o status da rota: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: kDebugMode
            ? 'Falha ao trocar o status: $e'
            : 'Não foi possível trocar o status da rota.',
      );
    }
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
    Widget? action,
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
            if (action != null) ...[const SizedBox(height: 12), action],
          ],
        ),
      ),
    );
  }
}
