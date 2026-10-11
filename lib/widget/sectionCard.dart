import 'package:flutter/material.dart';

/// A superfície branca das listas da aba Amigos: as seções de convites, amigos
/// e bloqueados, e o corpo do placar do Ranking.
///
/// Um widget e uma [decoration] só porque o card do Ranking e os da lista de
/// amigos são o mesmo objeto visto em duas sub-telas. Copiar raio e sombra nos
/// dois lugares é a deriva que `GlassSurface` fechou para o vidro.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.children,
    this.dividerIndent = 0,
  });

  final List<Widget> children;

  /// Recuo da divisória entre duas linhas — alinhada com o texto, não com a
  /// borda, para a divisória separar pessoas e não cortar o avatar.
  final double dividerIndent;

  static const double radius = 20;

  /// A sombra é azulada e não preta: sobre o fundo lilás do tema, sombra preta
  /// lê como sujeira em volta do card.
  static final BoxDecoration decoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: const [
      BoxShadow(color: Color(0x1A0D47A1), blurRadius: 20, offset: Offset(0, 6)),
      BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // O branco é um `Material`, não a cor da decoração: o `ListTile` pinta o
    // efeito de toque no `Material` mais próximo, e com o branco num
    // `DecoratedBox` esse `Material` seria o do `Scaffold`, **embaixo** do
    // card — o toque funcionaria sem mostrar que funcionou.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: decoration.borderRadius,
        boxShadow: decoration.boxShadow,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: dividerIndent,
                    color: const Color(0xFFEEE9F2),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
