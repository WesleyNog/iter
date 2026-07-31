import 'package:flutter/material.dart';

void showBairrosMultiSelect(
  BuildContext context,
  List<String> bairros,
  List<String> selectedBairros,
  TextEditingController searchBairroController,
  StateSetter setState,
) {
  // Copia os bairros para podermos filtrar na busca interna do modal
  List<String> filteredBairros = List.from(bairros);
  searchBairroController.clear();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        // Necessário para atualizar o estado interno do modal
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Text(
                  'Selecione os Bairros',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                // Campo de Busca
                TextField(
                  controller: searchBairroController,
                  decoration: InputDecoration(
                    hintText: 'Buscar bairro...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (value) {
                    setModalState(() {
                      filteredBairros = bairros
                          .where(
                            (bairro) => bairro.toLowerCase().contains(
                              value.toLowerCase(),
                            ),
                          )
                          .toList();
                    });
                  },
                ),
                const SizedBox(height: 10),
                // Lista de Bairros com Checkbox
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredBairros.length,
                    itemBuilder: (context, index) {
                      final bairro = filteredBairros[index];
                      final isSelected = selectedBairros.contains(bairro);
                      return CheckboxListTile(
                        title: Text(bairro),
                        value: isSelected,
                        activeColor: Colors.green,
                        onChanged: (bool? checked) {
                          // Atualiza dentro do modal
                          setModalState(() {
                            if (checked == true) {
                              selectedBairros.add(bairro);
                            } else {
                              selectedBairros.remove(bairro);
                            }
                          });
                          // Atualiza a tela principal (para desenhar as tags)
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
                // Botão de fechar
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
