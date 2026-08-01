import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:iter/Utils/calendar.dart';
import 'package:flutter/cupertino.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/routeTime.dart';
import 'package:iter/Utils/bairros.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/services/firebase.dart';
import 'package:iter/services/openWeather.dart';
import 'package:iter/Utils/weather.dart';
import 'package:iter/widget/dataPicker.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/selectAdress.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' as math;

class AddIter extends StatefulWidget {
  const AddIter({super.key, required this.user, this.route});

  final User user;

  /// Rota existente = modo edição. `null` = cadastro novo.
  final NewRouteModal? route;

  bool get isEditing => route != null;

  @override
  State<AddIter> createState() => _AddIterState();
}

class _AddIterState extends State<AddIter> {
  final _formKey = GlobalKey<FormState>();
  List<String> bairros = fortaleza_bairros;
  List<String> selectedBairros = [];
  int selectedCompanyIndex = 0;
  String status = 'agendado';
  DateTime selectedDate = DateTime.now();
  bool isInsucessoSelected = false;
  WeatherType currentWeatherType = WeatherType.clear;
  String weatherIcon = 'assets/images/SOL.png';
  int insucessoQnt = 1;

  final firestore = FirestoreService.instance;

  TextEditingController valueController = TextEditingController();
  TextEditingController kmInicialController = TextEditingController();
  TextEditingController kmFinalController = TextEditingController();
  TextEditingController pctInicialController = TextEditingController();
  TextEditingController pctFinalController = TextEditingController();
  TextEditingController searchBairroController = TextEditingController();
  TextEditingController hrInicioController = TextEditingController();
  TextEditingController hrFimController = TextEditingController();

  initState() {
    super.initState();
    _loadWeatherIcon();
    if (widget.isEditing) _fillFromRoute(widget.route!);
  }

  /// Reidrata o formulário com a rota que está sendo editada.
  void _fillFromRoute(NewRouteModal route) {
    selectedCompanyIndex = Company.values.indexOf(route.company);
    status = route.status.name;
    selectedDate = route.startAt;
    selectedBairros = [...?route.adress];
    isInsucessoSelected = route.isInsucesso ?? false;
    insucessoQnt = route.insucessoQnt ?? 1;

    // O campo espera o texto já formatado, igual ao que o formatador produz.
    valueController.text = CurrencyFormatterHelper.formatDoubleToMoney(
      route.value,
    );
    kmInicialController.text = route.kmInitial?.toString() ?? '';
    kmFinalController.text = route.kmFinal?.toString() ?? '';
    pctInicialController.text = route.packages?.toString() ?? '';
    pctFinalController.text = route.stops?.toString() ?? '';
    hrInicioController.text = RouteTime.formatTime(route.startAt);
    hrFimController.text = route.endAt == null
        ? ''
        : RouteTime.formatTime(route.endAt!);
  }

  void _loadWeatherIcon() async {
    double lat = -3.71722;
    double lon = -38.5434;

    WeatherType weatherType = await getWeather(lat, lon);

    setState(() {
      currentWeatherType = weatherType;
    });
  }

  Widget _getStatusIcon(String statusValue) {
    switch (statusValue) {
      case 'agendado':
        return Icon(Icons.calendar_today, color: Colors.blue.shade100);
      case 'andamento':
        return Icon(Icons.directions_car, color: Colors.orange.shade100);
      case 'concluido':
        return Icon(Icons.check_circle_outline, color: Colors.purple.shade100);
      case 'pago':
        return Icon(
          Icons.monetization_on_outlined,
          color: Colors.teal.shade100,
        );
      default:
        return Icon(Icons.help_outline, color: Colors.grey.shade100);
    }
  }

  /// Campo de hora: abre a roleta do Cupertino e nunca o teclado, então só
  /// entra valor no formato `HH:mm`.
  ///
  /// Início é obrigatório — a rota é agendada já sabendo a que horas começa.
  /// Fim é opcional, porque só se sabe ao terminar.
  Widget _timeField({required bool isStart}) {
    final controller = isStart ? hrInicioController : hrFimController;
    final label = isStart ? 'Hr Início' : 'Hr Fim';

    return TextFormField(
      controller: controller,
      readOnly: true,
      showCursor: false,
      onTap: () => _pickTime(isStart: isStart),
      decoration: InputDecoration(
        labelText: isStart ? '$label *' : label,
        prefixIcon: Icon(Icons.access_time, color: Colors.amber.shade300),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(50)),
      ),
      validator: (value) => isStart && (value == null || value.isEmpty)
          ? 'Informe a hora de início'
          : null,
    );
  }

  void _pickTime({required bool isStart}) {
    final controller = isStart ? hrInicioController : hrFimController;
    final current = RouteTime.combine(selectedDate, controller.text);
    final initial = current ?? DateTime.now();

    // Grava já o valor inicial: fechar a roleta sem girar deixaria o campo
    // vazio mesmo com uma hora aparecendo na tela.
    setState(() => controller.text = RouteTime.formatTime(initial));

    showCupertinoTimePicker(context, initial, (time) {
      setState(() => controller.text = RouteTime.formatTime(time));
    });
  }

  String _getButtonName(String statusValue) {
    switch (statusValue) {
      case 'agendado':
        return 'Agendar';
      case 'andamento':
        return 'Iniciar';
      case 'concluido':
        return 'Finalizar';
      case 'pago':
        return 'Receber';
      default:
        return 'Desconhecido';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar Rota' : 'Nova Rota'),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
        // Sem este Form, `_formKey.currentState` é null e a validação nem roda.
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _companySelector(),
              Expanded(child: _buildContent()),
            ],
          ),
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
                    onTap: () => showCupertinoDatePicker(
                      context,
                      selectedDate,
                      (newDate) {
                        setState(() {
                          selectedDate = newDate;
                        });
                      },
                    ),
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
                Container(
                  height: 50,
                  width: 50,
                  child: Center(
                    child: Stack(
                      children: [
                        getWeekdayIcon(selectedDate.weekday),
                        Positioned(
                          bottom: 3,
                          right: 8,
                          child: Text(
                            '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: valueController,
                    keyboardType:
                        CurrencyFormatterHelper.getCurrencyFormatter()
                            .isNotEmpty
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
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: status,
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
                    selectedItemBuilder: (BuildContext context) {
                      return const [
                        'agendado',
                        'andamento',
                        'concluido',
                        'pago',
                      ].map((String value) {
                        return _getStatusIcon(value);
                      }).toList();
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 'agendado',
                        child: Text('Agendado'),
                      ),
                      DropdownMenuItem(
                        value: 'andamento',
                        child: Text('Em Rota'),
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
            Row(
              children: [
                Expanded(child: _timeField(isStart: true)),
                const SizedBox(width: 10),
                Expanded(child: _timeField(isStart: false)),
              ],
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Opcionais',
                  style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
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
            SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(5.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: kmInicialController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'KM - Inicial',
                              prefixIcon: Icon(
                                Icons.speed,
                                color: Colors.blue.shade100,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: kmFinalController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'KM - Final',
                              prefixIcon: Icon(
                                Icons.speed,
                                color: Colors.blue.shade100,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
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
                        Expanded(
                          child: TextField(
                            controller: pctInicialController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Pacotes',
                              prefixIcon: Icon(
                                Icons.inventory_2_outlined,
                                color: Colors.green.shade100,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: pctFinalController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Paradas',
                              prefixIcon: Icon(
                                Icons.location_on_outlined,
                                color: Colors.red.shade100,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
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
                        Expanded(
                          child: InkWell(
                            onTap: () => showBairrosMultiSelect(
                              context,
                              bairros,
                              selectedBairros,
                              searchBairroController,
                              setState,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey,
                                  width: 1.0,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Icon(
                                    Icons.streetview_outlined,
                                    color: Colors.blue.shade100,
                                  ),
                                  Text(
                                    selectedBairros.isEmpty
                                        ? 'Bairros'
                                        : selectedBairros.length > 1
                                        ? '${selectedBairros.first.substring(0, math.min(20, selectedBairros.first.length))} + ${selectedBairros.length - 1}'
                                        : '${selectedBairros.first}',
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
                    SizedBox(height: 10),
                    Row(
                      children: [
                        CupertinoSwitch(
                          value: isInsucessoSelected,
                          onChanged: (bool value) {
                            setState(() {
                              isInsucessoSelected = value;
                            });
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Opacity(
                            // Desativa visualmente o seletor quando o switch estiver desligado
                            opacity: isInsucessoSelected ? 0.6 : 0.4,
                            child: Container(
                              height: 44, // Altura padrão de controles iOS
                              decoration: BoxDecoration(
                                color: CupertinoColors.tertiarySystemFill,
                                borderRadius: BorderRadius.circular(
                                  12,
                                ), // Curva padrão do iOS
                              ),
                              child: Row(
                                children: [
                                  // Botão Decrementar (-)
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed:
                                        (isInsucessoSelected &&
                                            insucessoQnt > 1)
                                        ? () => setState(() => insucessoQnt--)
                                        : null,
                                    child: const Icon(
                                      CupertinoIcons.minus,
                                      size: 18,
                                      color: CupertinoColors.label,
                                    ),
                                  ),

                                  // Texto Central
                                  Expanded(
                                    child: Text(
                                      isInsucessoSelected
                                          ? '$insucessoQnt'
                                          : 'Insucesso',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isInsucessoSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isInsucessoSelected
                                            ? CupertinoColors.label
                                            : CupertinoColors.secondaryLabel,
                                      ),
                                    ),
                                  ),

                                  // Botão Incrementar (+)
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed:
                                        (isInsucessoSelected &&
                                            insucessoQnt < 999)
                                        ? () => setState(() => insucessoQnt++)
                                        : null,
                                    child: const Icon(
                                      CupertinoIcons.plus,
                                      size: 18,
                                      color: CupertinoColors.label,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: CupertinoColors.tertiarySystemFill,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6.0),
                          child: Image.asset(
                            getWeatherIcon(currentWeatherType),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                onPressed: () => _saveRoute(),
                child: Text(
                  widget.isEditing
                      ? 'Salvar alterações'
                      : '${_getButtonName(status)} Rota',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                color: status == "agendado"
                    ? Colors.blue.shade300
                    : status == "andamento"
                    ? Colors.orange.shade300
                    : status == "concluido"
                    ? Colors.purple.shade300
                    : status == "pago"
                    ? Colors.teal.shade300
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRoute() async {
    // `currentState` continua podendo ser null se o Form sair da árvore.
    if (!(_formKey.currentState?.validate() ?? false)) {
      showNotification(
        context: context,
        type: 'error',
        msg: 'Por favor, preencha todos os campos obrigatórios.',
      );
      return;
    }

    final String now = DateTime.now().toIso8601String();

    final newRoute = NewRouteModal(
        // Mesmo id = o `set` substitui o documento em vez de criar outro.
        id: widget.route?.id ?? Uuid().v4(),
        company: Company.values[selectedCompanyIndex],
        dateRoute:
            '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
        weekday: selectedDate.weekday,
        status: StatusRoute.values.firstWhere(
          (e) => e.toString() == 'StatusRoute.$status',
        ),
        // O campo é formatado como moeda ("R$ 1.234,56"), então precisa do
        // parse que remove o símbolo e o separador de milhar.
        value: CurrencyFormatterHelper.parseMoneyToDouble(valueController.text),
        kmInitial:
            double.tryParse(kmInicialController.text.replaceAll(',', '.')) ??
            0.0,
        kmFinal:
            double.tryParse(kmFinalController.text.replaceAll(',', '.')) ?? 0.0,
        packages: int.tryParse(pctInicialController.text),
        stops: int.tryParse(pctFinalController.text),
        adress: selectedBairros,
        // O validator já garante a hora de início; o `??` só existe porque o
        // tipo é nullable.
        startAt:
            RouteTime.combine(selectedDate, hrInicioController.text) ??
            selectedDate,
        // Fim antes do início significa rota que virou o dia.
        endAt: RouteTime.resolveEnd(
          RouteTime.combine(selectedDate, hrInicioController.text) ??
              selectedDate,
          hrFimController.text,
        ),
        isInsucesso: isInsucessoSelected,
        insucessoQnt: isInsucessoSelected ? insucessoQnt : null,
        createdAt: widget.route?.createdAt ?? now,
      );

    EasyLoading.show(status: 'Salvando rota...').ignore();

    try {
      await RouteController.save(widget.user.uid, newRoute);

      if (!mounted) return;
      showNotification(
        context: context,
        type: 'success',
        msg: widget.isEditing
            ? 'Rota atualizada com sucesso!'
            : 'Rota salva com sucesso!',
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('Erro ao salvar rota: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: kDebugMode
            ? 'Falha ao salvar: $e'
            : 'Não foi possível salvar a rota. Tente novamente.',
      );
    } finally {
      await EasyLoading.dismiss();
    }
  }
}
