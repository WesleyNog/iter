import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// Uma ação de deslizar sem fundo, sem borda e sem rótulo — só o ícone,
/// colorido.
///
/// `CustomSlidableAction` e não `SlidableAction`: o segundo sempre desenha um
/// retângulo cheio e não tem como não desenhar. O fundo transparente deixa o da
/// lista aparecer, então o ícone flutua ao lado do card em vez de virar um
/// bloco colorido do tamanho dele.
///
/// O `Tooltip` devolve por acessibilidade o nome que o rótulo dava: sem ele, o
/// leitor de tela anuncia um botão sem nome.
///
/// Num lugar só porque três listas deslizam — as rotas, o extrato de gastos e
/// os veículos — e o gesto tem de ter a mesma cara nas três. A de veículos foi
/// a última a chegar aqui: ainda desenhava o bloco colorido com rótulo.
Widget iconSlideAction({
  required String keyName,
  required VoidCallback onPressed,
  required IconData icon,
  required Color color,
  required String tooltip,
}) {
  return CustomSlidableAction(
    key: ValueKey(keyName),
    onPressed: (_) => onPressed(),
    backgroundColor: Colors.transparent,
    foregroundColor: color,
    padding: EdgeInsets.zero,
    child: Tooltip(
      message: tooltip,
      child: Icon(icon, size: 28, color: color),
    ),
  );
}
