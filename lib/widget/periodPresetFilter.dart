import 'package:flutter/material.dart';
import 'package:iter/widget/filterPill.dart';
import 'package:iter/Utils/periodPreset.dart';
import 'package:iter/widget/periodFilter.dart';

/// Seletor de período por atalho: uma linha de chips, e as duas roletas de data
/// só dentro do Personalizado.
///
/// Envolve o [PeriodFilter], que continua sendo quem desenha Início e Fim e
/// quem impede fim antes de início. A novidade aqui é que, na maior parte do
/// tempo, o entregador não precisa de nenhuma das duas: ele quer "este mês" ou
/// "semana passada", e escolher isso girando duas roletas é descobrir o recorte
/// por eliminação.
///
/// O widget **não guarda estado**. Ele recebe [preset], [start] e [end] e avisa
/// por [onChanged] o que o usuário pediu — quem guarda é a tela, com `setState`,
/// como o resto do app. Isso é o que garante que o chip aceso e as datas em uso
/// sejam sempre o mesmo par: não existem duas cópias do recorte para
/// divergirem.
class PeriodPresetFilter extends StatelessWidget {
  const PeriodPresetFilter({
    super.key,
    required this.preset,
    required this.start,
    required this.end,
    required this.onChanged,
    this.allowAll = false,
  });

  /// O atalho aceso, ou `null` para "Todo o período".
  ///
  /// `null` só é alcançável com [allowAll]; sem ele, nenhum chip fica aceso, o
  /// que é estado legítimo de quem ainda não escolheu.
  final PeriodPreset? preset;

  /// O recorte em uso. Fora do Personalizado ele é o que [rangeOf] devolveu
  /// para [preset] — a tela guarda as datas, não o widget.
  final DateTime start;
  final DateTime end;

  /// Avisa o atalho escolhido **junto com as datas que ele implica**.
  ///
  /// Os três valores viajam juntos de propósito: a tela que só guardasse o
  /// preset teria de recalcular o recorte por conta própria, e aí passariam a
  /// existir duas contas de "que dia começa a semana passada".
  final void Function(PeriodPreset? preset, DateTime start, DateTime end)
  onChanged;

  /// Acrescenta o chip "Todo o período" na frente dos cinco.
  ///
  /// Fica desligado por padrão porque as telas de Gráficos e de Resumo somam
  /// dinheiro por recorte: "todo o período" ali é um total de carreira dentro
  /// de um card mensal. A folha de filtros da lista é o caso oposto — ela abre
  /// sem filtrar nada, e "todo o período" é o padrão dela.
  final bool allowAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Rola na horizontal em vez de dividir a largura em cinco.
        //
        // Um trilho de segmentos iguais dá a cada rótulo um quinto da tela, e
        // "Semana Anterior" não cabe nisso num iPhone. O `CLAUDE.md` registra
        // exatamente esse erro com um `SegmentedButton` de "Substituição": ele
        // passou em três testes de largura e quebrou linha no aparelho, porque
        // a fonte do teste é quadrada e quebra de linha não levanta exceção.
        // Rolando, o chip recebe a largura do próprio texto e a decisão sai da
        // mão da fonte.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              if (allowAll)
                _chip(
                  keyName: 'periodo-todo',
                  label: 'Todo o período',
                  // Mantém as datas: sair de "todo o período" para o
                  // Personalizado tem de cair em algum recorte, e o último que
                  // esteve na tela é o único que o usuário reconhece.
                  selected: preset == null,
                  onTap: () => onChanged(null, start, end),
                ),
              for (final option in PeriodPreset.values)
                _chip(
                  keyName: 'periodo-${option.name}',
                  label: presetLabel(option),
                  selected: preset == option,
                  onTap: () => _pick(option),
                ),
            ],
          ),
        ),
        // As roletas só existem no Personalizado, e é isso que fecha o caminho
        // de volta: não há como girar uma data com outro chip aceso, então
        // nenhum chip pode acabar mentindo sobre o recorte que está valendo.
        if (preset == PeriodPreset.personalizado)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: PeriodFilter(
              start: start,
              end: end,
              onChanged: (s, e) => onChanged(PeriodPreset.personalizado, s, e),
            ),
          ),
      ],
    );
  }

  /// Traduz o toque num chip para o recorte que ele implica.
  ///
  /// `rangeOf` devolve `null` no Personalizado, e esse `null` quer dizer "esta
  /// pergunta não se aplica" — nunca "deu zero". Por isso ele cai nas datas que
  /// **já estavam** na tela: quem entra no Personalizado quer ajustar o recorte
  /// em que estava. Trocar por um mês qualquer aqui apagaria a escolha do
  /// usuário toda vez que ele reabrisse a seção.
  void _pick(PeriodPreset option) {
    final range = rangeOf(option);
    onChanged(option, range?.start ?? start, range?.end ?? end);
  }

  Widget _chip({
    required String keyName,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => FilterPill(
    key: ValueKey(keyName),
    label: label,
    selected: selected,
    onTap: onTap,
  );
}
