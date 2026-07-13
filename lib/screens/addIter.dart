import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:iter/Utils/currencyFormat.dart';

class AddIter extends StatefulWidget {
  const AddIter({super.key});

  @override
  State<AddIter> createState() => _AddIterState();
}

class _AddIterState extends State<AddIter> {
  int selectedCompanyIndex = 0;
  String? status;
  DateTime selectedDate = DateTime.now();
  TextEditingController valueController = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova Rota')),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Empresa:',
              style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10.0),
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
                ),
                SizedBox(height: 30),
                const Text(
                  'Opcionais',
                  style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
                ),
                const Divider(color: Colors.grey, thickness: 1.0),
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
