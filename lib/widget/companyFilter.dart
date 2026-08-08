import 'package:flutter/material.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/segmentedSelector.dart';

/// Controle segmentado para filtrar a lista por empresa.
///
/// [selected] em `null` significa "todas" — é o estado padrão.
///
/// O trilho e a pílula moram no [SegmentedSelector]; aqui fica só o que é de
/// empresa: os logos, os rótulos e o segmento extra do "todas".
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
    return SegmentedSelector<Company?>(
      keyPrefix: 'filtro',
      selected: selected,
      onChanged: onChanged,
      segments: [
        SegmentOption(
          value: null,
          label: 'Todas',
          keySuffix: 'todas',
          child: Icon(
            Icons.apps_rounded,
            size: 19,
            color: selected == null ? Colors.blue.shade600 : Colors.grey,
          ),
        ),
        for (final company in Company.values)
          SegmentOption(
            value: company,
            label: companyLabel(company),
            keySuffix: company.name,
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
    );
  }
}
