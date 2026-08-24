import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';

/// O card de uma rota com os gestos de deslizar: editar e excluir de um lado,
/// marcar como paga do outro.
///
/// Separado da tela porque a lista precisa de um `User` e de um stream do
/// Firestore para existir — e a regra que decide **quando** o botão de pagar
/// aparece é justamente a que não pode quebrar em silêncio. Aqui ela é um
/// getter, e o teste pergunta direto.
class RouteSlidable extends StatelessWidget {
  const RouteSlidable({
    super.key,
    required this.route,
    required this.onEdit,
    required this.onDelete,
    required this.onMarkPaid,
    required this.child,
  });

  final NewRouteModal route;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Chamado com a rota já sabidamente [canMarkPaid] — a tela grava só o status.
  final VoidCallback onMarkPaid;

  final Widget child;

  /// Marcar como paga direto da lista só é honesto na rota **concluída**.
  ///
  /// Concluído e pago são os dois `hasRun` com a mesma provisão: KM e veículo
  /// não mudam, o bloco congelado continua valendo, e a troca é de fato só o
  /// status — que é o que torna o atalho legítimo em vez de conveniente.
  ///
  /// Rota **agendada** ou **em rota** não tem provisão: ela nasce ao concluir.
  /// Marcá-la paga por aqui deixaria uma rota paga sem combustível nem peças
  /// cobrados — lucro inflado, que é sempre o lado que engana. E a **sem rota**
  /// guarda valor líquido e um `noRoutePayment` congelado: virar rota paga a
  /// colocaria na contagem de rotas e nos rankings de bairro com uma fração do
  /// valor.
  ///
  /// Quem precisa de qualquer outra troca usa o formulário de edição, que
  /// continua oferecendo os cinco status e recalcula o que tem de recalcular.
  bool get canMarkPaid => route.status == StatusRoute.concluido;

  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: ValueKey(route.id),
      // Só existe para quem pode ser marcada como paga. Revelar um painel vazio
      // — ou um botão que recusa — ensinaria o gesto errado em quatro dos cinco
      // status.
      startActionPane: canMarkPaid
          ? ActionPane(
              motion: const DrawerMotion(),
              // Um ícone só: metade do espaço que os dois do outro lado pedem.
              extentRatio: 0.2,
              children: [
                _action(
                  keyName: 'acao-pagar',
                  onPressed: onMarkPaid,
                  // O mesmo ícone e a mesma cor do selo "Pago" no card: o gesto
                  // e o resultado dizem a mesma coisa sem precisar de rótulo.
                  icon: statusIcon(StatusRoute.pago),
                  color: statusColor(StatusRoute.pago),
                  tooltip: 'Marcar como paga',
                ),
              ],
            )
          : null,
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        // Era 0.45 quando cada ação tinha fundo, borda e rótulo. Só o ícone
        // pede bem menos, e o excesso deixava o card sumir da tela.
        extentRatio: 0.32,
        children: [
          _action(
            keyName: 'acao-editar',
            onPressed: onEdit,
            icon: Icons.edit_outlined,
            color: Colors.blue.shade600,
            tooltip: 'Editar',
          ),
          _action(
            keyName: 'acao-excluir',
            onPressed: onDelete,
            icon: Icons.delete_outline,
            color: Colors.red.shade600,
            tooltip: 'Excluir',
          ),
        ],
      ),
      child: child,
    );
  }

  /// Uma ação sem fundo, sem borda e sem rótulo — só o ícone, colorido.
  ///
  /// `CustomSlidableAction` e não `SlidableAction`: o segundo sempre desenha um
  /// retângulo cheio e não tem como não desenhar. O fundo transparente deixa o
  /// da lista aparecer, então o ícone flutua ao lado do card em vez de virar um
  /// bloco colorido do tamanho dele.
  ///
  /// O `Tooltip` devolve por acessibilidade o nome que o rótulo dava: sem ele,
  /// o leitor de tela anuncia um botão sem nome.
  Widget _action({
    required String keyName,
    required VoidCallback onPressed,
    required IconData icon,
    required Color color,
    required String tooltip,
  }) {
    return CustomSlidableAction(
      key: ValueKey(keyName),
      onPressed: (_) => onPressed(),
      backgroundColor: Colors.transparent,
      foregroundColor: color,
      padding: EdgeInsets.zero,
      child: Tooltip(
        message: tooltip,
        child: Icon(icon, size: 28, color: color),
      ),
    );
  }
}
