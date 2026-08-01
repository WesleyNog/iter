import 'package:flutter/material.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';

/// Controle segmentado para filtrar a lista por empresa.
///
/// [selected] em `null` significa "todas" — é o estado padrão.
class CompanyFilter extends StatelessWidget {
  const CompanyFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Company? selected;
  final ValueChanged<Company?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _segment(
            company: null,
            tooltip: 'Todas',
            child: Icon(
              Icons.apps_rounded,
              size: 19,
              color: selected == null ? Colors.blue.shade600 : Colors.grey,
            ),
          ),
          for (final company in Company.values)
            _segment(
              company: company,
              tooltip: companyLabel(company),
              child: Image.asset(
                companyLogo(company),
                height: 18,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _segment({
    required Company? company,
    required String tooltip,
    required Widget child,
  }) {
    final isSelected = selected == company;

    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          key: ValueKey('filtro-${company?.name ?? 'todas'}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(company),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            // Apagar o não selecionado deixa claro qual está ativo sem
            // precisar de fundo colorido em cada empresa.
            child: Center(
              child: Opacity(opacity: isSelected ? 1 : 0.45, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
