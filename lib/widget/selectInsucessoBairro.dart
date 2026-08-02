import 'package:flutter/material.dart';
import 'package:iter/Utils/insucessoBairro.dart';

/// Sheet para dizer em qual bairro cada insucesso aconteceu.
///
/// Irmão de `showBairrosMultiSelect`: mesma moldura, mas a lista traz **só os
/// bairros da rota** (não os 123 da cidade) e o checkbox vira um seletor de
/// quantidade, porque aqui a pergunta não é "passou por aqui?" e sim "quantos
/// foram aqui?".
///
/// [distribution] é alterado no lugar, como o `selectedBairros` do outro sheet,
/// e [setState] é o da tela que chamou — para o resumo do campo atualizar
/// quando o sheet fechar.
///
/// Distribuir tudo é opcional: o que sobrar continua sendo rateado pelo
/// gráfico. Por isso não há validação nem botão bloqueado ao sair.
void showInsucessoBairroSelect(
  BuildContext context,
  List<String> bairros,
  Map<String, int> distribution,
  int total,
  StateSetter setState,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          final left = remainingFailures(total, distribution);

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Text(
                  'Onde foram os insucessos?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _remainingChip(left: left, total: total),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: bairros.length,
                    itemBuilder: (context, index) {
                      final bairro = bairros[index];
                      final qnt = distribution[bairro] ?? 0;

                      return _bairroRow(
                        bairro: bairro,
                        qnt: qnt,
                        // Sem insucesso sobrando não dá para somar em ninguém.
                        canAdd: left > 0,
                        onChanged: (novo) {
                          setModalState(() {
                            if (novo <= 0) {
                              distribution.remove(bairro);
                            } else {
                              distribution[bairro] = novo;
                            }
                          });
                          // A tela atrás mostra "3 de 5" no campo fechado.
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: const Text(
                      'Confirmar',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _remainingChip({required int left, required int total}) {
  final done = left == 0;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: done ? Colors.green.shade50 : Colors.amber.shade50,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: done ? Colors.green.shade200 : Colors.amber.shade200,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle_outline : Icons.pending_outlined,
          size: 16,
          color: done ? Colors.green.shade700 : Colors.amber.shade800,
        ),
        const SizedBox(width: 6),
        Text(
          done
              ? 'Todos os $total distribuídos'
              : 'Restam $left de $total',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: done ? Colors.green.shade800 : Colors.amber.shade900,
          ),
        ),
      ],
    ),
  );
}

Widget _bairroRow({
  required String bairro,
  required int qnt,
  required bool canAdd,
  required ValueChanged<int> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            bairro,
            style: TextStyle(
              fontSize: 15,
              // Bairro já com insucesso marcado salta na lista.
              fontWeight: qnt > 0 ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        IconButton(
          onPressed: qnt > 0 ? () => onChanged(qnt - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: Colors.red.shade300,
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$qnt',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: qnt > 0 ? Colors.black : Colors.grey.shade400,
            ),
          ),
        ),
        IconButton(
          onPressed: canAdd ? () => onChanged(qnt + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          color: Colors.green.shade400,
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
}
