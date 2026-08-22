import 'package:flutter/material.dart';

/// A pílula de um filtro: rótulo, opcionalmente um ícone, acesa ou apagada.
///
/// Existe porque a folha de filtros e o seletor de período nasceram na mesma
/// mudança desenhando a mesma coisa — e são desenhados **um em cima do outro**,
/// já que a seção de período da folha é o próprio seletor. Duas aparências de
/// chip encostadas seriam lidas como dois controles diferentes, e ajustar o
/// arredondamento de um criaria a terceira variante. É a mesma cópia de
/// superfície que o `polimento-glass.md` já registrou uma vez.
///
/// Não guarda estado: [selected] vem de fora e [onTap] avisa o toque. Quem
/// decide o que um toque faz — marcar, desmarcar, trocar — é sempre o chamador,
/// porque em três das cinco seções da folha a resposta é diferente.
///
/// [accent] existe para o status levar a cor que ele já tem no card da lista: a
/// forma é a mesma, o significado é que muda.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Colors.blue.shade600;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              // Nos dois lugares onde esta pílula vive hoje — um `Wrap` e um
              // scroll horizontal — a largura é livre e o rótulo nunca aperta.
              // As duas linhas ficam mesmo assim porque custam zero e decidem o
              // comportamento se um dia ela for parar numa largura fixa:
              // cortar com "…" é ruim, quebrar em duas linhas é o layout torto
              // que passou em três testes de largura antes de chegar no
              // aparelho do usuário.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
