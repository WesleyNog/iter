import 'package:flutter/material.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/segmentedSelector.dart';

/// Controle segmentado para filtrar a lista por empresa — múltipla escolha.
///
/// Conjunto **vazio ou com as três** quer dizer "todas": as duas metades são a
/// mesma resposta, e é por isso que não existe mais um segmento "Todas".
/// Nenhum marcado é onde a tela abre; as três marcadas é onde o usuário chega
/// marcando uma a uma. A regra mora uma vez só, em `_passes` do
/// `routeFilter.dart` — repeti-la aqui seria a segunda cópia que um dia fica
/// para trás.
///
/// Com o conjunto vazio os três logos ficam apagados, que é o pedido e é o
/// estado inicial. Quem impede o "tudo apagado" de parecer "nada aparece" é o
/// estado vazio da lista, que nunca fica em branco sem dizer por quê.
///
/// [onToggle] avisa **em qual empresa o usuário tocou**, marcada ou não — este
/// widget não guarda estado e não alterna nada. Quem alterna é a tela, com
/// `RouteFilter.toggleCompany`, que é a mesma regra usada pela folha de
/// filtros: dois lugares alternando por conta própria é como um toque acaba
/// marcando numa metade da tela e desmarcando na outra.
///
/// O trilho, a pílula e a opacidade moram no [SegmentedSelector]; aqui fica só
/// o que é de empresa: os logos e os rótulos.
class CompanyFilter extends StatelessWidget {
  const CompanyFilter({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<Company> selected;
  final ValueChanged<Company> onToggle;

  @override
  Widget build(BuildContext context) {
    return SegmentedSelector<Company>.multi(
      keyPrefix: 'filtro',
      selected: selected,
      onChanged: onToggle,
      segments: [
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
