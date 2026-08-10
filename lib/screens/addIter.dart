import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:iter/Utils/calendar.dart';
import 'package:flutter/cupertino.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/insucessoBairro.dart';
import 'package:iter/Utils/routeTime.dart';
import 'package:iter/Utils/bairros.dart';
import 'package:iter/Utils/noRouteRule.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/Utils/vehicleCost.dart';
import 'package:iter/controller/noRouteRuleController.dart';
import 'package:iter/controller/profileController.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/controller/vehicleController.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/vehicle.dart';
import 'package:iter/services/openWeather.dart';
import 'package:iter/Utils/weather.dart';
import 'package:iter/widget/dataPicker.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/selectAdress.dart';
import 'package:iter/widget/selectInsucessoBairro.dart';
import 'package:iter/widget/weatherPicker.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' as math;

class AddIter extends StatefulWidget {
  const AddIter({
    super.key,
    required this.uid,
    this.route,
    this.ruleLoader,
    this.saver,
  });

  /// Só o `uid` é usado aqui — nunca o resto do `User`.
  ///
  /// Mesmo formato de `AddSupply`, e pela mesma razão: um `User` do
  /// FirebaseAuth é classe abstrata com dezenas de membros, e exigi-lo tornava
  /// esta tela impossível de pumpar num teste. Ela é a que carrega a armadilha
  /// do valor cheio × valor líquido, e era a única sem teste nenhum.
  final String uid;

  /// Rota existente = modo edição. `null` = cadastro novo.
  final NewRouteModal? route;

  /// De onde vem o percentual de `norouterule`. `null` = do Firestore.
  ///
  /// Injetável só para o teste alcançar as quatro frases da Sem Rota —
  /// encontrada, ausente, carregando e falhou — sem emulador.
  final Future<int?> Function(Company company)? ruleLoader;

  /// Para onde a rota é gravada. `null` = `RouteController.save`.
  ///
  /// Existe porque o caminho de salvamento não tinha **um** teste, e é onde
  /// mora a invariante mais cara da feature: `value` recebe o líquido e
  /// `noRoutePayment` vai junto. Uma revisão adversarial trocou
  /// `payment?.paid ?? gross` por `gross` neste arquivo e a suíte inteira
  /// continuou verde — 871 testes sem tocar em `_saveRoute`.
  final Future<void> Function(String uid, NewRouteModal route)? saver;

  bool get isEditing => route != null;

  @override
  State<AddIter> createState() => _AddIterState();
}

/// Em que pé está a busca de `norouterule/{empresa}`.
///
/// Quatro estados e não um `int?`, porque **"sem regra cadastrada" e "não
/// consegui ler" pedem coisas opostas ao usuário**: um manda cadastrar no
/// console, o outro manda tentar de novo. E a primeira leitura desta coleção num
/// aparelho nunca vem do cache, então offline é o caso comum, não o raro.
enum _RuleState { ocioso, carregando, encontrada, ausente, falhou }

class _AddIterState extends State<AddIter> {
  final _formKey = GlobalKey<FormState>();
  List<String> bairros = fortaleza_bairros;
  List<String> selectedBairros = [];
  int selectedCompanyIndex = 0;

  /// O enum, e não o nome dele em texto.
  ///
  /// Antes era `String`, e isso formava um contrato de três pontas em texto
  /// puro — o `value` do dropdown, o `route.status.name` da edição e um
  /// `firstWhere` sem `orElse` no salvamento. Qualquer grafia diferente só
  /// estourava no clique de Salvar, com o formulário inteiro preenchido, e caía
  /// no catch genérico virando "Não foi possível salvar a rota".
  StatusRoute status = StatusRoute.agendado;

  DateTime selectedDate = DateTime.now();
  bool isInsucessoSelected = false;

  /// O percentual da empresa escolhida, quando a busca encontrou.
  int? _noRoutePercent;
  _RuleState _ruleState = _RuleState.ocioso;

  /// Descarta resposta de busca que chegou depois de outra mais nova.
  ///
  /// Trocar de empresa duas vezes rápido dispara duas leituras, e a primeira
  /// pode voltar por último — gravando o percentual da empresa errada no
  /// documento, sem erro nenhum.
  int _ruleRequest = 0;

  /// `null` = ainda não sei (carregando, sem rede, sem chave). Só o tempo de
  /// verdade preenche isto — antes o valor nascia como `clear` e o sol aparecia
  /// mesmo quando a consulta falhava.
  WeatherType? currentWeather;

  /// Escolha manual manda. Sem isto, a consulta de rede — que pode voltar
  /// depois de o usuário já ter escolhido — desfaria a escolha dele.
  bool _weatherChosenByUser = false;

  int insucessoQnt = 1;

  /// Em quais bairros os insucessos aconteceram. Pode cobrir só parte deles —
  /// o que sobra é rateado pelo gráfico.
  Map<String, int> insucessoPorBairro = {};

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
    // Só busca o tempo em rota nova. Editando, vale o que ficou gravado: a
    // consulta só sabe o céu de agora, e sobrescrever com ele a rota de semana
    // passada seria trocar um dado certo por um errado.
    if (widget.isEditing) {
      _fillFromRoute(widget.route!);
      // Editar uma ida já gravada **não depende** desta busca: o bloco
      // congelado já responde qual percentual vale. Ela existe para o caso de o
      // documento ter vindo sem bloco, e para a linha de baixo poder dizer algo
      // se ele mudar de empresa. Falhar aqui não impede salvar.
      if (status == StatusRoute.semRota) _loadNoRouteRule();
    } else {
      _loadWeather();
    }
  }

  /// Busca `norouterule/{empresa}` para a empresa que está selecionada.
  ///
  /// Só é chamada quando o status é Sem Rota — nenhum outro precisa da regra, e
  /// uma leitura por rascunho salvo seria consulta jogada fora.
  Future<void> _loadNoRouteRule() async {
    final request = ++_ruleRequest;
    final company = Company.values[selectedCompanyIndex];

    setState(() {
      _ruleState = _RuleState.carregando;
      _noRoutePercent = null;
    });

    try {
      final loader = widget.ruleLoader ?? NoRouteRuleController.fetchPercent;
      final percent = await loader(company);
      // `_ruleRequest` mudou: outra empresa foi escolhida enquanto esta
      // resposta vinha, e gravá-la agora carimbaria o percentual errado.
      if (!mounted || request != _ruleRequest) return;

      setState(() {
        _noRoutePercent = percent;
        _ruleState = percent == null
            ? _RuleState.ausente
            : _RuleState.encontrada;
      });
    } catch (e) {
      // A leitura falhou — sem rede, sem permissão, regra não deployada. É
      // **diferente** de não haver regra, e a frase na tela é outra.
      debugPrint('norouterule: não foi possível ler a regra: $e');
      if (!mounted || request != _ruleRequest) return;

      setState(() {
        _noRoutePercent = null;
        _ruleState = _RuleState.falhou;
      });
    }
  }

  /// Troca a empresa selecionada.
  ///
  /// Um método e não `setState` copiado nos três `GestureDetector` do seletor:
  /// instrumentar dois e esquecer um deixaria o percentual da empresa anterior
  /// na tela **e no documento gravado**.
  void _selectCompany(int index) {
    if (index == selectedCompanyIndex) return;

    setState(() => selectedCompanyIndex = index);
    if (status == StatusRoute.semRota) _loadNoRouteRule();
  }

  /// A empresa escolhida agora.
  Company get _company => Company.values[selectedCompanyIndex];

  bool get _isNoRoute => status == StatusRoute.semRota;

  /// O valor cheio digitado — o que a rota pagaria se tivesse rodado.
  double get _grossValue =>
      CurrencyFormatterHelper.parseMoneyToDouble(valueController.text);

  /// O pagamento que **será gravado**, calculado pela mesma função do save.
  ///
  /// Uma função só para a prévia e para a gravação: uma segunda implementação
  /// para a linha da tela mostraria um número e gravaria outro, e o `paid` é
  /// comparado com igualdade exata contra `value`.
  NoRoutePayment? get _noRoutePreview => resolveNoRoutePayment(
    status: status,
    company: _company,
    grossValue: _grossValue,
    existing: widget.route?.noRoutePayment,
    existingCompany: widget.route?.company,
    currentPercent: _noRoutePercent,
  );

  /// Reidrata o formulário com a rota que está sendo editada.
  void _fillFromRoute(NewRouteModal route) {
    final weather = route.weather;
    currentWeather = weather == null || weather.isEmpty
        ? null
        : WeatherType.fromString(weather);

    selectedCompanyIndex = Company.values.indexOf(route.company);
    status = route.status;
    selectedDate = route.startAt;
    selectedBairros = [...?route.adress];
    isInsucessoSelected = route.isInsucesso ?? false;
    insucessoQnt = route.insucessoQnt ?? 1;
    insucessoPorBairro = {...route.insucessoPorBairro};

    // O campo espera o texto já formatado, igual ao que o formatador produz.
    //
    // Numa Sem Rota, `route.value` é o **líquido**: reabrir uma rota de R$ 250
    // mostraria R$ 100 e salvar sem tocar em nada gravaria R$ 40 — composto,
    // uma vez por edição, sem exceção e sem log. O campo fala sempre em valor
    // cheio, e o líquido aparece na linha de baixo.
    valueController.text = CurrencyFormatterHelper.formatDoubleToMoney(
      route.noRoutePayment?.grossValue ?? route.value,
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

  /// Mantém a distribuição coerente com o que a rota tem **agora**.
  ///
  /// Ela fica inválida sem o usuário tocar nela: basta remover um bairro de
  /// "Bairros" ou baixar a quantidade de insucessos depois de distribuir. Por
  /// isso roda a cada mudança nos dois, e não só ao salvar.
  void _syncInsucessoPorBairro() {
    insucessoPorBairro = reconcileDistribution(
      distribution: insucessoPorBairro,
      bairros: selectedBairros,
      total: isInsucessoSelected ? insucessoQnt : 0,
    );
  }

  /// O que vai para o banco.
  ///
  /// Com um bairro só não há escolha a fazer: todos os insucessos são dele.
  /// Gravar isso dá atribuição exata sem custar um toque ao usuário — é por
  /// isso que o campo nem aparece nesse caso.
  Map<String, int> _distributionToSave() {
    if (!isInsucessoSelected) return const {};

    if (selectedBairros.length == 1) {
      return {selectedBairros.first: insucessoQnt};
    }

    return reconcileDistribution(
      distribution: insucessoPorBairro,
      bairros: selectedBairros,
      total: insucessoQnt,
    );
  }

  void _loadWeather() async {
    double lat = -3.71722;
    double lon = -38.5434;

    final weather = await getWeather(lat, lon);

    // A consulta é de rede: a tela pode ter saído — ou o usuário já ter
    // escolhido o tempo na mão — antes de ela voltar.
    if (!mounted || _weatherChosenByUser) return;

    setState(() {
      currentWeather = weather;
    });
  }

  /// Deixa o usuário corrigir o tempo.
  ///
  /// A rota agendada para amanhã guarda o céu de hoje, e a busca automática não
  /// tem como saber o de amanhã: no dia, quem ajusta é ele.
  Future<void> _pickWeather() async {
    final choice = await showWeatherPicker(context, selected: currentWeather);
    if (choice == null || !mounted) return; // Fechou sem escolher.

    setState(() {
      currentWeather = choice.value;
      _weatherChosenByUser = true;
    });
  }

  /// Ícone do status dentro do campo fechado.
  ///
  /// `switch` sobre o **enum** e sem `default`, ao contrário da versão que
  /// existia aqui: com `default`, um status novo compilava limpo, passava no
  /// `flutter analyze` e entregava uma interrogação cinza no dropdown.
  ///
  /// Os tons são mais claros que os de `statusColor` porque aqui o ícone fica
  /// dentro do campo, sobre o cinza do formulário.
  Widget _statusIcon(StatusRoute value) {
    switch (value) {
      case StatusRoute.agendado:
        return Icon(Icons.calendar_today, color: Colors.blue.shade100);
      case StatusRoute.andamento:
        return Icon(Icons.directions_car, color: Colors.orange.shade100);
      case StatusRoute.concluido:
        return Icon(Icons.check_circle_outline, color: Colors.purple.shade100);
      case StatusRoute.pago:
        return Icon(
          Icons.monetization_on_outlined,
          color: Colors.teal.shade100,
        );
      case StatusRoute.semRota:
        return Icon(
          Icons.do_not_disturb_on_outlined,
          color: Colors.blueGrey.shade200,
        );
    }
  }

  /// Cor do botão de salvar. Também exaustivo: o encadeado ternário que existia
  /// aqui terminava em `Colors.grey` e usava aspas **duplas**, então um status
  /// novo deixava o botão cinza sem avisar — e um `grep` pelas outras listas,
  /// escritas com aspas simples, não achava esta cópia.
  Color _buttonColor(StatusRoute value) {
    switch (value) {
      case StatusRoute.agendado:
        return Colors.blue.shade300;
      case StatusRoute.andamento:
        return Colors.orange.shade300;
      case StatusRoute.concluido:
        return Colors.purple.shade300;
      case StatusRoute.pago:
        return Colors.teal.shade300;
      case StatusRoute.semRota:
        return Colors.blueGrey.shade300;
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

  /// O verbo do botão. Exaustivo pelo mesmo motivo: com `default`, o status novo
  /// entregava um botão escrito "Desconhecido Rota".
  String _getButtonName(StatusRoute value) {
    switch (value) {
      case StatusRoute.agendado:
        return 'Agendar';
      case StatusRoute.andamento:
        return 'Iniciar';
      case StatusRoute.concluido:
        return 'Finalizar';
      case StatusRoute.pago:
        return 'Receber';
      // A ida já aconteceu e já foi paga quando ela é cadastrada: não há o que
      // agendar, iniciar nem receber. Só registrar que houve.
      case StatusRoute.semRota:
        return 'Registrar';
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
                onTap: () => _selectCompany(0),
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
                  child: Image.asset('assets/logo/ML.jpg'),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _selectCompany(1),
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
                onTap: () => _selectCompany(2),
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
    return SingleChildScrollView(
      // O `Expanded` que envolve isto dá altura **fixa**; sem rolagem, o
      // conteúdo estoura em tela pequena e o botão de salvar fica embaixo da
      // faixa listrada. Foi o que aconteceu num Android de tela menor.
      //
      // O respiro embaixo é o que o teclado ocupa: sem ele, abrir o teclado no
      // último campo esconderia o botão de novo.
      padding: EdgeInsets.only(
        top: 10.0,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Center(
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
                      // Na Sem Rota o campo continua sendo o valor **cheio** —
                      // o que a rota pagaria se tivesse rodado. O que entra no
                      // bolso é a linha logo abaixo.
                      labelText: status == StatusRoute.semRota
                          ? 'Valor cheio'
                          : 'Valor',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    // Sem isto a linha do valor líquido nasce certa e fica
                    // permanentemente um caractere atrás: o controller não tem
                    // listener e nada reconstrói a tela enquanto se digita.
                    //
                    // `onChanged` e não `addListener`: esta `State` não tem
                    // `dispose`, e os oito controllers já vazam — não vale
                    // acrescentar o nono.
                    onChanged: (_) {
                      if (status == StatusRoute.semRota) setState(() {});
                    },
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
                  child: DropdownButtonFormField<StatusRoute>(
                    value: status,
                    // Sem isto o dropdown se dimensiona pelo **maior item do
                    // menu** ("Concluído") em vez da largura que recebeu, e
                    // estoura para a direita em tela estreita. Com `true` ele
                    // preenche o espaço dado e corta com reticências.
                    isExpanded: true,
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
                    // As duas listas saem do **mesmo** `StatusRoute.values`, e
                    // não de dois literais paralelos. O Flutter cruza uma com a
                    // outra por índice: com o status novo só em `items`, o
                    // debug estourava um assert e o **release** — onde o assert
                    // some — desenhava o ícone do status anterior. Bug que só
                    // existiria no build que vai para o usuário.
                    selectedItemBuilder: (context) => [
                      for (final value in StatusRoute.values)
                        _statusIcon(value),
                    ],
                    items: [
                      for (final value in StatusRoute.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(statusLabel(value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;

                      setState(() => status = value);
                      // A regra só é buscada quando ela passa a valer.
                      if (value == StatusRoute.semRota) _loadNoRouteRule();
                    },
                  ),
                ),
              ],
            ),
            // Emitido **sempre**, devolvendo um espaço vazio fora da Sem Rota.
            // Um `if` que acrescenta ou remove um filho muda a contagem da
            // Column e desloca todos os irmãos abaixo: o `TextFormField`
            // recriado perde o foco e a mensagem de validação em exibição.
            _noRouteLine(),
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
                              // Bairro retirado da rota não pode continuar com
                              // insucesso atribuído a ele.
                              (fn) => setState(() {
                                fn();
                                _syncInsucessoPorBairro();
                              }),
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
                              _syncInsucessoPorBairro();
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
                                        // Baixar o total corta o excesso já
                                        // distribuído, a partir do fim.
                                        ? () => setState(() {
                                            insucessoQnt--;
                                            _syncInsucessoPorBairro();
                                          })
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

                        Tooltip(
                          message: currentWeather == null
                              ? 'Escolher o tempo'
                              : '${weatherLabel(currentWeather!)} — tocar para alterar',
                          child: Material(
                            color: CupertinoColors.tertiarySystemFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: InkWell(
                              customBorder: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              onTap: _pickWeather,
                              child: SizedBox(
                                height: 44,
                                width: 44,
                                child: Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: weatherImage(currentWeather),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Com 0 ou 1 bairro não há distribuição a fazer: sem
                    // bairro não há onde atribuir, e com um só o save já
                    // atribui tudo a ele.
                    if (isInsucessoSelected && selectedBairros.length > 1) ...[
                      SizedBox(height: 10),
                      _insucessoBairroField(),
                    ],
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
                color: _buttonColor(status),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A linha que diz quanto vai ser gravado numa Sem Rota — e por quê.
  ///
  /// Fora da Sem Rota devolve um espaço vazio em vez de sumir: ver o comentário
  /// na chamada. As quatro frases são quatro pedidos diferentes, e colapsá-las
  /// mandaria o entregador sem sinal cadastrar no console uma regra que já está
  /// lá.
  Widget _noRouteLine() {
    if (status != StatusRoute.semRota) return const SizedBox(height: 0);

    final payment = _noRoutePreview;

    final (String message, bool isProblem) = switch (payment) {
      // O percentual pode ser o da regra de hoje ou o congelado na rota que
      // está sendo editada — `_noRoutePreview` decide, e é a mesma função que o
      // save usa, então o número aqui é literalmente o que vai para o banco.
      final NoRoutePayment p => (
        'Sem rota: a ${companyLabel(_company)} paga ${p.percent}% → '
            '${CurrencyFormatterHelper.formatMoney(p.paid)}',
        false,
      ),
      _ when _grossValue <= 0 => (
        'Informe o valor cheio da rota para calcular o pagamento.',
        false,
      ),
      _ when _ruleState == _RuleState.carregando => (
        'Buscando a regra de pagamento…',
        false,
      ),
      _ when _ruleState == _RuleState.falhou => (
        'Não foi possível ler a regra de pagamento. Tente de novo.',
        true,
      ),
      _ => (
        'Sem regra de pagamento cadastrada para a ${companyLabel(_company)}.',
        true,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isProblem ? Icons.error_outline : Icons.do_not_disturb_on_outlined,
            size: 15,
            color: isProblem ? Colors.red.shade600 : Colors.blueGrey.shade400,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              key: const Key('no-route-line'),
              style: TextStyle(
                fontSize: 12,
                color: isProblem ? Colors.red.shade700 : Colors.blueGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Campo que abre a distribuição dos insucessos entre os bairros da rota.
  ///
  /// Fechado, ele já diz o andamento — distribuir tudo é opcional, e o que
  /// sobrar continua sendo rateado pelo gráfico.
  Widget _insucessoBairroField() {
    final left = remainingFailures(insucessoQnt, insucessoPorBairro);
    final distributed = insucessoQnt - left;

    return InkWell(
      onTap: () => showInsucessoBairroSelect(
        context,
        selectedBairros,
        insucessoPorBairro,
        insucessoQnt,
        setState,
      ),
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
            Icon(Icons.wrong_location_outlined, color: Colors.orange.shade200),
            Expanded(
              child: Text(
                distributed == 0
                    ? 'Onde foram os insucessos?'
                    : '$distributed de $insucessoQnt distribuídos',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: distributed == 0 ? Colors.grey[600] : Colors.black,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  /// Anexa a provisão à rota que está sendo salva.
  ///
  /// Só busca o veículo quando a rota está concluída ou paga: rota agendada não
  /// provisiona nada, e uma leitura no Firestore a cada rascunho salvo seria
  /// consulta jogada fora.
  ///
  /// Quem decide o que fazer é `resolveProvision` — inclusive **manter** o que
  /// já estava gravado quando o KM e o veículo não mudaram, que é o que impede
  /// uma correção de hoje reescrever o lucro de junho.
  Future<NewRouteModal> _withProvision(NewRouteModal draft) async {
    // `hasRun` e não a condição repetida: esta linha roda **antes** de
    // `resolveProvision` e curto-circuita, então enquanto ela não conhecesse a
    // Sem Rota, corrigir só o `vehicleCost.dart` não provisionava uma sequer.
    if (!draft.hasRun) return draft.withProvision(null);

    Vehicle? vehicle;
    try {
      vehicle = await VehicleController.fetchActive(widget.uid);
    } catch (e) {
      // Falha ao ler o veículo não pode impedir de salvar a rota: o dado da
      // rota é do usuário, a provisão é conveniência.
      debugPrint('Não foi possível ler o veículo em uso: $e');
    }

    if (vehicle == null && draft.provision == null && mounted) {
      showNotification(
        context: context,
        type: 'info',
        msg: 'Cadastre um veículo para o app calcular a provisão desta rota.',
      );
    }

    return draft.withProvision(
      resolveProvision(
        route: draft,
        existing: widget.route?.provision,
        vehicle: vehicle,
      ),
    );
  }

  /// Reconta o que os amigos conseguem ver depois de gravar a rota.
  ///
  /// Recalculado da lista inteira, nunca incrementado: `FieldValue.increment`
  /// derivaria na primeira rota editada, e um número público que discorda da
  /// origem, sem ninguém poder auditar, é pior do que número nenhum.
  ///
  /// Editar a data manda **dois** meses: o novo e aquele de onde a rota saiu.
  /// Sem o segundo, o mês antigo continuaria contando uma rota que não está
  /// mais lá.
  Future<void> _republishStats(NewRouteModal saved) async {
    try {
      final routes = await RouteController.fetchAll(widget.uid);
      await ProfileController.refreshAfterRoute(
        uid: widget.uid,
        routes: routes,
        months: {saved.startAt, ?widget.route?.startAt},
      );
    } catch (e) {
      debugPrint('profiles: números públicos não republicados: $e');
    }
  }

  /// Se a Sem Rota pode ser gravada — e, quando não pode, diz o que falta.
  ///
  /// O guarda é **"não há pagamento resolvido"**, e não "não tem percentual em
  /// mãos": corrigir uma ida de junho chega ao formulário sem a regra carregada
  /// (o `initState` só a busca, e offline nunca chega), e o bloco congelado já
  /// responde qual percentual vale. Recusar pela falta do percentual tornaria
  /// impossível editar uma rota antiga.
  bool _noRouteIsSavable(NoRoutePayment? payment, double gross) {
    String? problem;

    if (gross <= 0) {
      problem = 'Informe o valor cheio da rota — o que ela pagaria se tivesse '
          'rodado.';
    } else if (payment == null) {
      problem = switch (_ruleState) {
        _RuleState.carregando => 'Ainda buscando a regra de pagamento. Aguarde '
            'um instante.',
        _RuleState.falhou =>
          'Não foi possível ler a regra de pagamento. Tente de novo.',
        // Sem regra cadastrada é o caso da Shopee. Um default de 100%
        // superestimaria o ganho e um de 0% apagaria a provisão junto — o app
        // diz o que falta em vez de inventar o número.
        _ => 'Sem regra de pagamento cadastrada para a '
            '${companyLabel(_company)}. Cadastre o percentual antes de '
            'registrar esta rota.',
      };
    } else if (payment.paid <= 0) {
      // Só alcançável com valor de centavos e percentual baixo. Deixar passar
      // gravaria uma rota de R$ 0,00, que perde a provisão junto — a gasolina
      // da ida sumiria do custo.
      problem = 'Com ${payment.percent}% o valor pago sairia R\$ 0,00. '
          'Confira o valor da rota.';
    }

    if (problem == null) return true;

    showNotification(context: context, type: 'error', msg: problem);
    return false;
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

    // O campo é formatado como moeda ("R$ 1.234,56"), então precisa do parse
    // que remove o símbolo e o separador de milhar.
    final gross = _grossValue;

    // O pagamento da Sem Rota, congelado. `null` em qualquer outro status.
    final payment = _noRoutePreview;

    if (status == StatusRoute.semRota && !_noRouteIsSavable(payment, gross)) {
      return;
    }

    // O que vai para `value`: o líquido na Sem Rota, o valor cheio no resto. É
    // isto que faz `summarize`, `companySummary` e o lucro funcionarem sem
    // nenhum deles conhecer a regra de pagamento.
    final value = payment?.paid ?? gross;

    final String now = DateTime.now().toIso8601String();

    final draft = NewRouteModal(
      // Mesmo id = o `set` substitui o documento em vez de criar outro.
      id: widget.route?.id ?? Uuid().v4(),
      company: _company,
      dateRoute:
          '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
      weekday: selectedDate.weekday,
      status: status,
      value: value,
      noRoutePayment: payment,
      kmInitial:
          double.tryParse(kmInicialController.text.replaceAll(',', '.')) ?? 0.0,
      kmFinal:
          double.tryParse(kmFinalController.text.replaceAll(',', '.')) ?? 0.0,
      // Uma ida que não virou rota não carregou pacote, não fez parada e não
      // passou por bairro nenhum — então esses campos **não são gravados**
      // nela, mesmo que estejam preenchidos na tela.
      //
      // O caso que isto conserta: reabrir uma rota Concluída com 120 pacotes e
      // trocar o status para Sem Rota. `_fillFromRoute` deixou os controllers
      // cheios, e sem esta guarda o card passaria a exibir "Pacotes: 120" e
      // "Bairros: Aldeota" embaixo do chip "Sem Rota". Os agregados já estavam
      // protegidos (`realized` e a guarda por inclusão de `summarize`); o que
      // sobrava era o card afirmando o que não aconteceu.
      packages: _isNoRoute ? null : int.tryParse(pctInicialController.text),
      stops: _isNoRoute ? null : int.tryParse(pctFinalController.text),
      adress: _isNoRoute ? const <String>[] : selectedBairros,
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
      // Sem isto o campo nunca era gravado: o modelo tem `weather` e o card da
      // lista sabe desenhá-lo, mas nenhuma rota chegava a guardar um.
      weather: currentWeather?.name,
      isInsucesso: _isNoRoute ? false : isInsucessoSelected,
      insucessoQnt: _isNoRoute || !isInsucessoSelected ? null : insucessoQnt,
      insucessoPorBairro: _isNoRoute ? const {} : _distributionToSave(),
      provision: widget.route?.provision,
      createdAt: widget.route?.createdAt ?? now,
    );

    final newRoute = await _withProvision(draft);

    EasyLoading.show(status: 'Salvando rota...').ignore();

    try {
      await (widget.saver ?? RouteController.save)(widget.uid, newRoute);

      // Os números públicos do dono mudaram. Sem `await`: quem está salvando
      // espera a tela fechar, não uma escrita que é conveniência para os
      // amigos — e `refreshAfterRoute` já engole o próprio erro.
      unawaited(_republishStats(newRoute));

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
