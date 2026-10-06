import 'package:flutter/material.dart';
import 'package:iter/Utils/packageLabel.dart';
import 'package:iter/Utils/packageSession.dart';
import 'package:iter/widget/packageList.dart';

/// Quanto destaque cada tipo recebe.
///
/// Decisão de produto, não de estilo, e por isso tem nome e teste. O **A** é a
/// agência ou o Place, que às vezes está fechado e sai da rota: é o número que
/// o entregador confere antes de lançar o total no app do Mercado Livre. O
/// **C** é comércio, que tem horário — pede atenção, mas não sai da carga. O R
/// é o resto da carga e não disputa o olhar.
enum ChipEmphasis { normal, alerta, forte }

ChipEmphasis emphasisOf(PackageType type) {
  switch (type) {
    case PackageType.residencial:
      return ChipEmphasis.normal;
    case PackageType.comercial:
      return ChipEmphasis.alerta;
    case PackageType.agencia:
      return ChipEmphasis.forte;
  }
}

Color _emphasisColor(ChipEmphasis emphasis) {
  switch (emphasis) {
    case ChipEmphasis.normal:
      return Colors.white;
    case ChipEmphasis.alerta:
      return Colors.amber.shade400;
    case ChipEmphasis.forte:
      return Colors.deepOrange.shade500;
  }
}

/// A contagem por cima da câmera: total, paradas, cada tipo e o Finalizar.
///
/// Tocar no total abre a lista inteira; tocar num tipo abre a lista só
/// daquele tipo — é assim que se acha a agência fechada numa carga de cem.
class PackageCounterBar extends StatelessWidget {
  const PackageCounterBar({
    super.key,
    required this.session,
    required this.onOpenList,
    required this.onFinish,
  });

  final PackageSession session;
  final void Function(PackageListFilter filter) onOpenList;
  final VoidCallback onFinish;

  static const _filterOf = {
    PackageType.residencial: PackageListFilter.residencial,
    PackageType.comercial: PackageListFilter.comercial,
    PackageType.agencia: PackageListFilter.agencia,
  };

  @override
  Widget build(BuildContext context) {
    final total = session.total;
    final stops = session.stops;
    final untyped = session.untyped;

    return Material(
      color: Colors.black.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('total'),
              onTap: () => onOpenList(PackageListFilter.todos),
              borderRadius: BorderRadius.circular(8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: total == 1 ? '1 pacote' : '$total pacotes',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: stops == 1
                          ? '  ·  1 parada'
                          : '  ·  $stops paradas',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // R, C, A: a ordem da etiqueta, com o mais importante no fim,
                // onde o polegar já está a caminho do Finalizar.
                for (final type in PackageType.values)
                  PackageTypeChip(
                    key: ValueKey('chip-${packageTypeLetter(type)}'),
                    letter: packageTypeLetter(type),
                    count: session.count(type),
                    emphasis: emphasisOf(type),
                    onTap: () => onOpenList(_filterOf[type]!),
                  ),
                // Só aparece quando existe: um "? 0" fixo ensinaria a ignorar
                // o chip no dia em que ele importasse.
                if (untyped > 0)
                  PackageTypeChip(
                    key: const ValueKey('chip-?'),
                    letter: '?',
                    count: untyped,
                    emphasis: ChipEmphasis.normal,
                    onTap: () => onOpenList(PackageListFilter.semLetra),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('finalizar'),
              onPressed: session.isEmpty ? null : onFinish,
              child: const Text('Finalizar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Um tipo e a sua contagem.
class PackageTypeChip extends StatelessWidget {
  const PackageTypeChip({
    super.key,
    required this.letter,
    required this.count,
    required this.emphasis,
    required this.onTap,
  });

  final String letter;
  final int count;
  final ChipEmphasis emphasis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _emphasisColor(emphasis);
    final strong = emphasis == ChipEmphasis.forte;

    return Material(
      // O forte é cheio; o alerta, só contorno e um véu da cor; o normal não
      // tem cor nenhuma. Três níveis que se distinguem até sem ver cor.
      color: switch (emphasis) {
        ChipEmphasis.normal => Colors.transparent,
        ChipEmphasis.alerta => color.withValues(alpha: 0.18),
        ChipEmphasis.forte => color,
      },
      shape: StadiumBorder(
        side: BorderSide(
          color: emphasis == ChipEmphasis.normal ? Colors.white38 : color,
          width: strong ? 2 : 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: strong ? 16 : 12,
            vertical: strong ? 8 : 6,
          ),
          child: Text(
            '$letter $count',
            style: TextStyle(
              color: strong ? Colors.white : color,
              fontSize: strong ? 20 : 16,
              fontWeight: emphasis == ChipEmphasis.normal
                  ? FontWeight.w500
                  : FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// A letra do tipo num quadrado, como a tarja da etiqueta. Sem tipo, "?".
class PackageTypeBadge extends StatelessWidget {
  const PackageTypeBadge({super.key, required this.type});

  final PackageType? type;

  @override
  Widget build(BuildContext context) {
    final type = this.type;
    final emphasis = type == null ? ChipEmphasis.normal : emphasisOf(type);
    final color = type == null
        ? Colors.grey.shade500
        : emphasis == ChipEmphasis.normal
        ? Colors.grey.shade800
        : _emphasisColor(emphasis);

    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type == null ? '?' : packageTypeLetter(type),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}
