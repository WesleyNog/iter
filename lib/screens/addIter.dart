import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/bairros.dart';

class AddIter extends StatefulWidget {
  const AddIter({super.key});

  @override
  State<AddIter> createState() => _AddIterState();
}

class _AddIterState extends State<AddIter> {
  List<String> bairros = fortaleza_bairros;
  List<String> selectedBairros = [];
  int selectedCompanyIndex = 0;
  String? status;
  DateTime selectedDate = DateTime.now();

  TextEditingController valueController = TextEditingController();
  TextEditingController kmInicialController = TextEditingController();
  TextEditingController kmFinalController = TextEditingController();
  TextEditingController pctInicialController = TextEditingController();
  TextEditingController pctFinalController = TextEditingController();
  TextEditingController searchBairroController = TextEditingController();

  void _showCupertinoDatePicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => Container(
        height: 250,
        padding: const EdgeInsets.only(top: 6.0),
        // Margem inferior para evitar que o seletor fique sob a barra de navegação do iPhone
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: SafeArea(
          top: false,
          child: CupertinoDatePicker(
            initialDateTime: selectedDate ?? DateTime.now(),
            mode: CupertinoDatePickerMode.date,
            use24hFormat: true,
            // Atualiza o estado conforme o usuário gira a roleta
            onDateTimeChanged: (DateTime newDate) {
              setState(() {
                selectedDate = newDate;
              });
            },
          ),
        ),
      ),
    );
  }

  void _showBairrosMultiSelect(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova Rota')),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _companySelector(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _companySelector() {
    return Container(
      width: double.infinity,
      height: 50.0,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(5.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          spacing: 5.0,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    selectedCompanyIndex = 0;
                  });
                },
                child: Container(
                  height: 40.0,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: selectedCompanyIndex == 0
                        ? Colors.amber.shade100
                        : null,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(5.0),
                  ),
                  child: Image.asset('assets/logo/ML.jpg', height: 40.0),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    selectedCompanyIndex = 1;
                  });
                },
                child: Container(
                  height: 40.0,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: selectedCompanyIndex == 1
                        ? Colors.blue.shade100
                        : null,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(5.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5.0),
                    child: Image.asset('assets/logo/Amazon.png'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    selectedCompanyIndex = 2;
                  });
                },
                child: Container(
                  height: 40.0,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: selectedCompanyIndex == 2
                        ? Colors.orange.shade100
                        : null,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(5.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Image.asset('assets/logo/Shopee.png', height: 20.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (selectedCompanyIndex) {
      case 0:
        return Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Column(
              children: [
                const Text(
                  'Dados da Rota',
                  style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
                ),
                const Divider(color: Colors.grey, thickness: 1.0),
                SizedBox(height: 10),
                Row(
                  children: [
                    // --- SELETOR DE DATA ---
                    Expanded(
                      flex: 4, // Ajusta a proporção do espaço na linha
                      child: InkWell(
                        onTap: () => _showCupertinoDatePicker(context),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey, width: 1.0),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(10),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                              const Icon(
                                Icons.calendar_today,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // --- DROPDOWN DE STATUS ---
                    Expanded(
                      flex: 5,
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'agendado',
                            child: Text('Agendado'),
                          ),
                          DropdownMenuItem(
                            value: 'andamento',
                            child: Text('Em andamento'),
                          ),
                          DropdownMenuItem(
                            value: 'concluido',
                            child: Text('Concluído'),
                          ),
                          DropdownMenuItem(value: 'pago', child: Text('Pago')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            status = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                TextFormField(
                  controller: valueController,
                  keyboardType:
                      CurrencyFormatterHelper.getCurrencyFormatter().isNotEmpty
                      ? TextInputType.number
                      : TextInputType.text,
                  inputFormatters:
                      CurrencyFormatterHelper.getCurrencyFormatter(),
                  decoration: InputDecoration(
                    labelText: 'Valor',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira um valor';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Opcionais',
                      style: TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Tooltip(
                      margin: EdgeInsets.symmetric(horizontal: 20.0),
                      message:
                          'Informações que serviram de métricas se preenchidas corretamente!',
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.grey, thickness: 1.0),
                SizedBox(height: 10),
                Row(
                  children: [
                    Text('KM'),
                    SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: kmInicialController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Inicial',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(' - '),
                    SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: kmFinalController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Final',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (value) {
                          if ((value == null || value.isEmpty) &&
                              kmInicialController.text.isNotEmpty) {
                            return 'Por favor, insira o KM final';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Text('Rota (Pacote | Parada)'),
                    SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: pctInicialController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'PCT',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(' - '),
                    SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: pctFinalController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Parada',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (value) {
                          if ((value == null || value.isEmpty) &&
                              pctInicialController.text.isNotEmpty) {
                            return 'Por favor, insira o PCT final';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    const Text("Bairros"),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _showBairrosMultiSelect(context),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey, width: 1.0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                selectedBairros.isEmpty
                                    ? 'Selecione os bairros'
                                    : '${selectedBairros.length} selecionado(s)',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: selectedBairros.isEmpty
                                      ? Colors.grey[600]
                                      : Colors.black,
                                ),
                              ),
                              const Icon(
                                Icons.arrow_drop_down,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Expanded(
                  child: SingleChildScrollView(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Wrap(
                        spacing: 8.0, // Espaço horizontal entre as tags
                        runSpacing:
                            4.0, // Espaço vertical entre as linhas de tags
                        children: selectedBairros.map((bairro) {
                          return Chip(
                            label: Text(
                              bairro,
                              style: const TextStyle(fontSize: 13.0),
                            ),
                            backgroundColor: Colors.green.shade50,
                            side: BorderSide(color: Colors.green.shade200),
                            deleteIcon: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.red,
                            ),
                            onDeleted: () {
                              setState(() {
                                selectedBairros.remove(bairro);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: Text('Rota Salva'),
                            content: Text('A rota foi salva com sucesso!'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    '/home',
                                    (route) => false,
                                  );
                                },
                                child: Text('OK'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: Text('Salvar Rota'),
                    style: ElevatedButton.styleFrom(
                      textStyle: TextStyle(color: Colors.white, fontSize: 18.0),
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case 1:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text(
                  'Amazon',
                  style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
                ),
                Divider(color: Colors.grey, thickness: 1.0),
              ],
            ),
          ),
        );

      case 2:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.precision_manufacturing_outlined,
                size: 100,
                color: Colors.grey,
              ),
              SizedBox(height: 8),
              Text(
                'Shopee em Desenvolvimento',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );

      default:
        return const SizedBox();
    }
  }
}
