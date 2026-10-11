import 'package:flutter/material.dart';
import 'package:iter/Utils/periodSelection.dart';
import 'package:iter/widget/glassTabs.dart';
import 'package:iter/widget/periodFilter.dart';
import 'package:iter/widget/segmentedSelector.dart';

/// O seletor de período de Gráficos e Resumo: três abas de vidro e, embaixo,
/// as setas de mês ou semana — ou as roletas, no Personalizado.
///
/// Substituiu a fileira de cinco chips que rolava. Cinco não cabiam em fatias
/// iguais, e o print do aparelho mostrava o custo: "Seman…" cortado na borda e
/// o "Personalizado" fora da tela. "Mês anterior" e "Semana anterior" eram o
/// mesmo recorte um passo para trás; com a seta, viraram gesto. Ver
/// `docs/specs/seletores-de-vidro.md`.
///
/// Não guarda estado, como o `PeriodPresetFilter` que ele substituiu nestas
/// telas: recebe a [selection] e avisa a próxima por [onChanged]. Quem decide o
/// que um toque faz é `PeriodSelection` — este widget só traduz o toque.
class PeriodNavigator extends StatelessWidget {
  const PeriodNavigator({
    super.key,
    required this.selection,
    required this.onChanged,
  });

  final PeriodSelection selection;
  final ValueChanged<PeriodSelection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassTabs<PeriodKind>(
          keyPrefix: 'periodo',
          selected: selection.kind,
          onChanged: (kind) => onChanged(selection.switchTo(kind)),
          tabs: [
            for (final kind in PeriodKind.values)
              SegmentOption(
                value: kind,
                label: kind.label,
                keySuffix: kind.name,
              ),
          ],
        ),
        const SizedBox(height: 8),
        // As roletas só existem no Personalizado e as setas só fora dele: não
        // há como girar uma data com Mês aceso, então a aba nunca mente sobre
        // o recorte que está valendo.
        if (selection.hasSteps)
          _steps()
        else
          PeriodFilter(
            start: selection.range.start,
            end: selection.range.end,
            onChanged: (start, end) =>
                onChanged(PeriodSelection.custom((start: start, end: end))),
          ),
      ],
    );
  }

  /// `‹ OUTUBRO 2026 ›` — o mesmo desenho da barra de mês do Ranking, fora do
  /// azul.
  Widget _steps() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('periodo-anterior'),
          icon: const Icon(Icons.chevron_left),
          color: Colors.grey.shade800,
          tooltip: selection.kind == PeriodKind.mes
              ? 'Mês anterior'
              : 'Semana anterior',
          onPressed: () => onChanged(selection.step(-1)),
        ),
        SizedBox(
          // Cabe "29/12/2025 – 04/01/2026", a semana mais comprida que existe.
          width: 200,
          child: Text(
            periodSelectionLabel(selection),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.grey.shade900,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('periodo-seguinte'),
          icon: const Icon(Icons.chevron_right),
          color: Colors.grey.shade800,
          disabledColor: Colors.grey.shade400,
          tooltip: selection.kind == PeriodKind.mes
              ? 'Mês seguinte'
              : 'Semana seguinte',
          // Apagada no período atual: o seletor nunca ofereceu o futuro.
          onPressed: selection.canGoForward
              ? () => onChanged(selection.step(1))
              : null,
        ),
      ],
    );
  }
}
