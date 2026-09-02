import 'package:flutter/material.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/widget/chartCard.dart';

/// Os cards de dinheiro do carrossel de cima.
///
/// As quatro páginas — resumo, pago, a receber e pendentes — têm a mesma
/// estrutura: três números, uma barra de proporção e a legenda. Então é um
/// widget só, configurado quatro vezes, e não quatro classes quase iguais.
///
/// Ficam fora da tela para poderem ser testados na altura real do carrossel: é
/// onde a legenda de quatro fatias quebra em duas linhas e o card estoura.

String _money(double value) => CurrencyFormatterHelper.formatMoney(value);

/// Uma fatia da barra de proporção: pode ser um status ou uma empresa.
class ShareSlice {
  const ShareSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class MoneyBreakdownCard extends StatelessWidget {
  const MoneyBreakdownCard({
    super.key,
    required this.title,
    required this.stats,
    required this.slices,
    required this.total,
    required this.emptyNote,
    this.eyebrow,
    this.footnote,
    this.extra,
  });

  final String title;
  final List<ChartStat> stats;

  /// Fatias já na ordem em que devem aparecer. Valor zero é descartado aqui.
  final List<ShareSlice> slices;

  /// Denominador das porcentagens — o total **deste card**, não o do período.
  final double total;

  final String emptyNote;

  /// Repassado ao [ChartCard] sem lógica nenhuma — ver [ChartCard.eyebrow].
  final String? eyebrow;

  final String? footnote;

  /// Linha extra no rodapé do card (a taxa de entrega, no resumo).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final visible = slices.where((slice) => slice.value > 0).toList();

    return ChartCard(
      title: title,
      eyebrow: eyebrow,
      stats: stats,
      footnote: footnote,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (visible.isEmpty || total <= 0)
            MiniNote(emptyNote)
          else
            ShareBar(slices: visible, total: total),
          ?extra,
        ],
      ),
    );
  }
}

/// Barra de proporção mais a legenda com valor e porcentagem.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.slices, required this.total});

  final List<ShareSlice> slices;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // O arredondamento fica no ClipRRect, e não em cada pedaço: a conta de
        // "sou o primeiro ou o último?" erra assim que uma fatia some.
        ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: Row(
            children: [
              for (final slice in slices)
                // Esta é a única grandeza da tela **sem** animação de entrada,
                // e é de propósito: a barra de proporção não tem um zero de
                // onde crescer. Todas as fatias partindo de `begin: 0` viram
                // fatias iguais no primeiro quadro — uma divisão que nunca foi
                // verdade — e só depois se acertam. Com `begin` igual ao `end`,
                // a primeira montagem não anima e o que anima é o que interessa:
                // a redistribuição quando o período muda.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: _weightOf(slice), end: _weightOf(slice)),
                  duration: ChartMotion.draw,
                  curve: ChartMotion.curve,
                  // O `Expanded` sai de dentro do `builder`, e não da lista:
                  // ele é `ParentDataWidget` e o que ele exige é ter o
                  // `RenderFlex` como render pai — o `TweenAnimationBuilder`
                  // não cria render nenhum, então o encaixe continua valendo.
                  // `child!` porque `Expanded` não aceita filho nulo e o
                  // `child` acima nunca é: quem constrói é este mesmo widget.
                  builder: (context, weight, child) =>
                      Expanded(flex: weight.round(), child: child!),
                  // A cor segue a **posição** na barra, e a posição troca de
                  // dono quando a ordem muda: animada, ela vira uma cor na
                  // outra em vez de piscar no meio do movimento.
                  child: AnimatedContainer(
                    duration: ChartMotion.draw,
                    curve: ChartMotion.curve,
                    height: 12,
                    color: slice.color,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: [for (final slice in slices) _legendItem(slice)],
        ),
      ],
    );
  }

  /// Peso da fatia na barra, em milésimos do total.
  ///
  /// Nunca zero: `flex: 0` tira a fatia da barra em vez de deixá-la fininha, e
  /// uma empresa com R$ 3 no mês sumiria da legenda que continua a citando.
  double _weightOf(ShareSlice slice) =>
      (slice.value / total * 1000).roundToDouble().clamp(1, 1000);

  Widget _legendItem(ShareSlice slice) {
    final share = total > 0 ? slice.value / total * 100 : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 4, backgroundColor: slice.color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${slice.label} (${share.toStringAsFixed(0)}%)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
              ),
            ),
            Text(
              _money(slice.value),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Quanto dos pacotes foi entregue, no período.
class DeliveryRateBar extends StatelessWidget {
  const DeliveryRateBar({super.key, required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final rate = summary.deliveryRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _MiniLabel('Taxa de entrega'),
        const SizedBox(height: 6),
        if (rate == null) MiniNote(_emptyNote(summary))
        else
          Row(
            children: [
              Expanded(
                child: ChartProgressBar(
                  fraction: rate,
                  colors: const [Color(0xFF69F0AE), Color(0xFF00C853)],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(rate * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: MiniNote(
                  '(${summary.failures} de ${summary.packages} pacotes)',
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// O que dizer quando não há taxa de entrega — três casos, três pedidos.
///
/// O terceiro nasceu com a Sem Rota: um período em que só houve ida ao CD tem
/// `count == 0` e dinheiro na barra logo acima, e "Sem rotas no período" ali
/// pareceria defeito. Mandar preencher "Pacotes" seria pior — a ida não
/// carregou nenhum.
String _emptyNote(PeriodSummary summary) {
  if (summary.count > 0) return 'Preencha "Pacotes" na rota para acompanhar.';
  if (summary.noRouteCount > 0) return 'Só idas sem rota no período.';
  return 'Sem rotas no período.';
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.85),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class MiniNote extends StatelessWidget {
  const MiniNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 11,
      ),
    );
  }
}
