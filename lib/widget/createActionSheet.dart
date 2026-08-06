import 'package:flutter/material.dart';
import 'package:iter/widget/glassSurface.dart';

/// Uma ação do menu do "+" (ex.: "Nova rota", "Abastecimento").
///
/// Sem [onTap] a linha aparece inerte, com o selo "Em breve": é assim que uma
/// função ainda não pronta se anuncia. `onTap` opcional em vez de um `bool`
/// separado torna impossível escrever a linha inconsistente — marcada como
/// pronta sem ação, ou com ação e selo de "em breve".
class CreateAction {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const CreateAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  bool get comingSoon => onTap == null;
}

/// Abre o menu de criação (bottom sheet de vidro) com as [actions].
///
/// O `onTap` da ação escolhida roda **depois** do pop do sheet, para o
/// Navigator não empilhar o sheet junto com a tela nova.
Future<void> showCreateActionSheet(
  BuildContext context, {
  required List<CreateAction> actions,
}) async {
  final chosen = await showModalBottomSheet<CreateAction>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    // Barreira mais clara que o padrão para o blur do vidro continuar visível.
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (_) => CreateActionSheet(actions: actions),
  );
  chosen?.onTap?.call();
}

/// Bottom sheet flutuante em "vidro" (mesmo material do [GlassNavBar]),
/// listando as ações de criação. Retorna a [CreateAction] escolhida no pop.
class CreateActionSheet extends StatelessWidget {
  final List<CreateAction> actions;

  const CreateActionSheet({super.key, required this.actions});

  // ---- Aparência ajustável ----
  static const double _radius = 28;

  /// Mais opaco que a barra de navegação **de propósito**: aqui há texto, e
  /// letra sobre vidro claro precisa de mais fundo para ficar legível do que um
  /// ícone. É diferença justificada, não deriva.
  static const double _glassOpacity = 0.75;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassSurface(
          opacity: _glassOpacity,
          borderRadius: BorderRadius.circular(_radius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              _handle(),
              const SizedBox(height: 6),
              ...actions.map((action) => _row(context, action)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// "Puxador" cinza no topo, indicando que o sheet pode ser arrastado.
  Widget _handle() {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _row(BuildContext context, CreateAction action) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(action.icon, color: action.color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[850],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  action.subtitle,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (action.comingSoon)
            _comingSoonBadge()
          else
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
        ],
      ),
    );

    // Ação em desenvolvimento: nada de InkWell — sem ripple e sem toque, para o
    // sheet não fechar prometendo uma tela que ainda não existe. O selo já diz.
    if (action.comingSoon) {
      return Opacity(opacity: 0.55, child: content);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(context, action),
        child: content,
      ),
    );
  }

  Widget _comingSoonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Em breve',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Colors.grey[700],
        ),
      ),
    );
  }
}
