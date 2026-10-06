import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';

/// O card de uma rota com os gestos de deslizar: editar e excluir de um lado,
/// marcar como paga — ou ler os pacotes — do outro.
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
    required this.onReadPackages,
    required this.child,
  });

  final NewRouteModal route;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Chamado com a rota já sabidamente [canMarkPaid] — a tela grava só o status.
  final VoidCallback onMarkPaid;

  /// Chamado com a rota já sabidamente [canReadPackages] — a tela abre o
  /// leitor e grava o que ele devolver.
  final VoidCallback onReadPackages;

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

  /// O leitor de pacotes só existe na rota **agendada do Mercado Livre**.
  ///
  /// Mercado Livre porque é a etiqueta dele que o leitor sabe ler — o QR com o
  /// número do envio, o endereço, a tarja R/C/A; a Amazon e a Shopee têm outro
  /// leiaute. Agendada porque a leitura é a conferência da carga no CD, antes
  /// de sair, e termina movendo a rota para Em rota: em qualquer outro status
  /// ela reescreveria pacotes e bairros de uma rota que já começou.
  ///
  /// E o atalho é legítimo pelo mesmo argumento do pagar: Agendado e Em rota
  /// não são `hasRun`, nenhum dos dois tem provisão, então trocar um pelo
  /// outro não implica recálculo. Nunca disputa o lado com [canMarkPaid] — um
  /// é só Concluído, o outro só Agendado. Ver `docs/specs/leitor-de-pacotes.md`.
  bool get canReadPackages =>
      route.status == StatusRoute.agendado &&
      route.company == Company.mercadolivre;

  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: ValueKey(route.id),
      // Pagar (Concluída) ou ler pacotes (Agendada do Mercado Livre) — nunca
      // os dois, e nada nos outros casos. Ver [_startPane].
      startActionPane: canMarkPaid
          ? _startPane(
              _action(
                keyName: 'acao-pagar',
                onPressed: onMarkPaid,
                // O mesmo ícone e a mesma cor do selo "Pago" no card: o gesto
                // e o resultado dizem a mesma coisa sem precisar de rótulo.
                icon: statusIcon(StatusRoute.pago),
                color: statusColor(StatusRoute.pago),
                tooltip: 'Marcar como paga',
              ),
            )
          : canReadPackages
          ? _startPane(
              _action(
                keyName: 'acao-ler-pacotes',
                onPressed: onReadPackages,
                // A cor é a do resultado (Em rota); o ícone é o do gesto. O
                // carro de Em rota diria "iniciar", e não "ler as etiquetas".
                icon: Icons.qr_code_scanner,
                color: statusColor(StatusRoute.andamento),
                tooltip: 'Ler pacotes e iniciar a rota',
              ),
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

  /// O painel da esquerda, com uma ação só.
  ///
  /// Só existe para quem tem o que fazer daquele lado. Revelar um painel vazio
  /// — ou um botão que recusa — ensinaria o gesto errado nos outros status.
  ActionPane _startPane(Widget action) => ActionPane(
    motion: const DrawerMotion(),
    // Um ícone só: metade do espaço que os dois do outro lado pedem.
    extentRatio: 0.2,
    children: [action],
  );

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
