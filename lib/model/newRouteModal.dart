import 'package:iter/Utils/insucessoBairro.dart';
import 'package:iter/Utils/mapRead.dart';
import 'package:iter/Utils/routeTime.dart';

enum Company { mercadolivre, amazon, shopee }

/// O ciclo de uma rota. A ordem é lida como esteira: `valueByStatus` itera
/// `StatusRoute.values` e a barra do Resumo desenha nessa sequência.
///
/// [semRota] vai no **fim** por isso — inserir no meio reordenaria um gráfico de
/// outra tela sem nenhum sinal aqui. É a rota que a empresa ofereceu, foi aceita
/// e acabou antes de começar: ela paga uma fração do valor, e o que fica gravado
/// em `value` já é essa fração. Ver [NoRoutePayment] e `docs/specs/sem-rota.md`.
enum StatusRoute { agendado, andamento, concluido, pago, semRota }

/// Como [StatusRoute] é gravado no Firestore — e a **única** forma.
///
/// Existe porque agora há dois caminhos escrevendo esse campo: o `toMap` do
/// documento inteiro e a troca rápida de status na lista, que grava só ele.
/// Duas expressões `split('.')` soltas divergiriam no dia em que alguém
/// renomeasse um valor do enum, e `fromMap` só reclamaria em execução — lendo
/// um status desconhecido de um documento que este mesmo app escreveu.
///
/// O caminho de volta mora em `NewRouteModal.fromMap`, que compara com
/// `'StatusRoute.${map['status']}'`. Renomear um valor quebra os dois: mude
/// junto, como o resto dos enums gravados como texto neste arquivo.
String storedStatus(StatusRoute status) => status.toString().split('.').last;

/// O pagamento de uma ida que não virou rota, **congelado**.
///
/// Mesma escolha de [RouteProvision], pelo mesmo motivo: o percentual mora numa
/// coleção global (`norouterule/{empresa}`) que o dono edita no console, e uma
/// taxa guardada é uma taxa que alguém muda. Se o valor cheio ficasse na rota e
/// o percentual fosse aplicado na leitura, trocar 40 por 30 hoje reescreveria o
/// lucro de junho — que é o que a planilha faz e o que este app existe para não
/// fazer.
///
/// O que vai para `NewRouteModal.value` é [paid], já descontado. É isso que faz
/// `summarize`, `companySummary`, `valuePerCompany` e o lucro funcionarem sem
/// nenhum deles conhecer a regra — e o primeiro que a esquecesse mostraria 100%
/// de uma rota de 40%.
///
/// [grossValue] e [percent] existem para as outras duas perguntas: o formulário
/// reabre com o valor **cheio** (sem ele, cada edição aplicaria o percentual de
/// novo, e R$ 250 viraria R$ 100 e depois R$ 40) e o card consegue dizer "40% de
/// R$ 250,00" em vez de um número sem procedência.
class NoRoutePayment {
  const NoRoutePayment({
    required this.grossValue,
    required this.percent,
    required this.appliedAt,
  });

  /// O que a rota valia cheia — o que o entregador digita no campo Valor.
  final double grossValue;

  /// Quanto a empresa paga por ela, em pontos percentuais (40 = 40%).
  final int percent;

  final String appliedAt;

  /// O que entrou no bolso. **Derivado, nunca gravado dentro deste bloco** —
  /// valor derivado que se grava é valor que um dia discorda da origem.
  ///
  /// Ele já está gravado uma vez, em `NewRouteModal.value`, porque é de lá que
  /// todos os agregados leem. A invariante `route.value == payment.paid` é
  /// comparação exata de `double`, e só se sustenta porque os dois lados passam
  /// por [paidValue].
  double get paid => paidValue(grossValue, percent);

  /// A conta, em **centavos inteiros**, sem float no meio.
  ///
  /// Duas armadilhas evitadas aqui, e as duas passam despercebidas na tela
  /// porque `toStringAsFixed(2)` esconde um `double` sujo:
  ///
  /// - `gross * (percent / 100)` dá `99.96000000000001` para `249,90 × 40%`,
  ///   enquanto `gross * percent / 100` dá `99,96` exato. Ou seja, o caso óbvio
  ///   de teste passa **por sorte**, e o defeito aparece só em outro par
  ///   (`1.234,56 × 40% = 493.82399999999996`).
  /// - `(x * 100).round() / 100` arredonda duas vezes, e os meios centavos são
  ///   alcançáveis: `87,45 × 30%` dá exatamente `26,235`. Pior, `1.005 * 100`
  ///   vira `100.49999999999999` em `double`, então a direção do arredondamento
  ///   passaria a ser decidida por ruído de float em vez de por regra.
  ///
  /// Com inteiros, `+ 50` antes da divisão é meio-centavo-para-cima, sempre.
  static double paidValue(double grossValue, int percent) {
    // Nunca negativo: o `+ 50` só é "para cima" do lado positivo, e o formulário
    // não tem como produzir valor negativo.
    if (grossValue <= 0 || percent <= 0) return 0;

    final grossCents = (grossValue * 100).round();
    return (grossCents * percent + 50) ~/ 100 / 100;
  }

  Map<String, dynamic> toMap() => {
    'grossValue': grossValue,
    'percent': percent,
    'appliedAt': appliedAt,
  };

  /// Leitura defensiva, como [RouteProvision.fromMap] e ao contrário de
  /// `NewRouteModal.value`, que é a exceção da casa: o Firestore devolve `int`
  /// para número sem casa decimal, um cast cru lança, e o `try/catch` por
  /// documento de `RouteController._parseAll` faria a rota **sumir da lista sem
  /// log nenhum**.
  factory NoRoutePayment.fromMap(Map<String, dynamic> map) => NoRoutePayment(
    grossValue: readDouble(map['grossValue']) ?? 0,
    percent: readInt(map['percent']) ?? 0,
    appliedAt: map['appliedAt'] as String? ?? '',
  );
}

/// O custo de uma rota, **congelado** no momento em que ela foi concluída.
///
/// Guarda valores em **reais**, nunca a taxa por km nem uma referência ao
/// veículo de onde ela veio. Essa escolha é o ponto inteiro desta classe:
/// taxa guardada é taxa que alguém edita, e o lucro de julho deixaria de contar
/// o pneu de R$ 500 no dia em que o pneu passasse a custar R$ 700.
///
/// É onde o app diverge da planilha de propósito. Lá as colunas F..K são
/// fórmulas apontando para o bloco de parâmetros do mês, então mudar um preço
/// reescreve o lucro de dias que já aconteceram — e um lucro que muda depois do
/// fato não é lucro, é estimativa. Refazer a conta aqui só acontece por ação
/// explícita do usuário.
class RouteProvision {
  const RouteProvision({
    required this.vehicleId,
    required this.km,
    required this.fuel,
    required this.parts,
    required this.totalParts,
    required this.calculatedAt,
  });

  /// Qual veículo rodou. Serve para saber se a provisão ainda corresponde ao
  /// veículo ativo; o custo em si não depende mais dele.
  final String vehicleId;

  /// KM rodado que foi usado na conta (`kmFinal - kmInitial`).
  final double km;

  /// Coluna F da planilha. Fica **fora** de [totalParts] e é subtraída à parte
  /// no lucro, como `O3 = C3 - F3 - L3`.
  final double fuel;

  /// Colunas G..K: quanto cada peça provisionou, por nome.
  ///
  /// O nome vai junto para a rota não depender do veículo: renomear "Freio"
  /// para "Pastilha" amanhã não apaga o que a rota de julho já sabe.
  final Map<String, double> parts;

  /// Coluna L: `=SUM(G3:K3)`, só as peças.
  final double totalParts;

  final String calculatedAt;

  /// Tudo que a rota custou: combustível mais peças.
  double get total => fuel + totalParts;

  /// Coluna O da planilha. **Derivado, nunca gravado** — valor derivado que se
  /// grava é valor que um dia discorda da origem.
  double profitFrom(double routeValue) => routeValue - total;

  Map<String, dynamic> toMap() => {
    'vehicleId': vehicleId,
    'km': km,
    'fuel': fuel,
    'parts': parts,
    'totalParts': totalParts,
    'calculatedAt': calculatedAt,
  };

  factory RouteProvision.fromMap(Map<String, dynamic> map) {
    final rawParts = map['parts'];

    return RouteProvision(
      vehicleId: map['vehicleId'] as String? ?? '',
      km: readDouble(map['km']) ?? 0,
      fuel: readDouble(map['fuel']) ?? 0,
      // O `?` no valor descarta a entrada quando o número é ilegível, em vez de
      // gravar um zero que passaria por custo real.
      parts: rawParts is Map
          ? {
              for (final entry in rawParts.entries)
                entry.key.toString(): ?readDouble(entry.value),
            }
          : const {},
      totalParts: readDouble(map['totalParts']) ?? 0,
      calculatedAt: map['calculatedAt'] as String? ?? '',
    );
  }
}

class NewRouteModal {
  final String id;
  final Company company;
  final String dateRoute;
  final int weekday;
  final String? weather;
  final StatusRoute status;
  final double value;
  final double? kmInitial;
  final double? kmFinal;
  final int? packages;
  final int? stops;
  final List<String>? adress;
  /// Início da rota com data e hora. Obrigatório: a rota já é agendada
  /// sabendo a que horas começa.
  final DateTime startAt;

  /// Fim da rota. Só se sabe ao terminar, então é opcional. Quando a rota
  /// vira o dia, já vem com a data do dia seguinte (ver [RouteTime.resolveEnd]).
  final DateTime? endAt;
  final bool? isInsucesso;
  final int? insucessoQnt;

  /// Em quais bairros os insucessos aconteceram: bairro → quantidade.
  ///
  /// Vazio significa "não distribuído", que é o estado de todo documento
  /// gravado antes deste campo existir — e o gráfico volta a ratear nesse caso.
  /// Pode cobrir só parte de [insucessoQnt]: o resto vai para o rateio.
  final Map<String, int> insucessoPorBairro;

  /// Quanto esta rota custou, congelado quando ela foi concluída.
  ///
  /// `null` em rota que ainda não rodou, em rota gravada antes desta versão e
  /// quando faltou KM ou veículo para calcular. Ver [RouteProvision].
  final RouteProvision? provision;

  /// Como o valor desta rota foi calculado, quando ela é [StatusRoute.semRota].
  ///
  /// `null` em toda rota normal. Ver [NoRoutePayment] — e note que `value` já
  /// vem descontado, então quem só lê `value` está certo sem saber que isto
  /// existe.
  final NoRoutePayment? noRoutePayment;

  final String createdAt;

  /// A mesma rota com outra provisão.
  ///
  /// Existe por causa de um ovo e galinha no salvamento: a provisão é calculada
  /// **a partir** da rota (precisa do status, do KM e do valor novos), então a
  /// rota tem de existir antes dela. Repetir os dezoito argumentos no
  /// `addIter.dart` só para trocar um campo seria pedir para esquecer um.
  NewRouteModal withProvision(RouteProvision? provision) => NewRouteModal(
    id: id,
    company: company,
    dateRoute: dateRoute,
    weekday: weekday,
    weather: weather,
    status: status,
    value: value,
    kmInitial: kmInitial,
    kmFinal: kmFinal,
    packages: packages,
    stops: stops,
    adress: adress,
    startAt: startAt,
    endAt: endAt,
    isInsucesso: isInsucesso,
    insucessoQnt: insucessoQnt,
    insucessoPorBairro: insucessoPorBairro,
    provision: provision,
    // Esta linha é a única defesa contra apagar o bloco congelado no mesmo save
    // que o criou: os parâmetros são nomeados e opcionais, então omiti-la não
    // gera erro de compilação nem teste vermelho — e o estrago só apareceria na
    // edição seguinte, aplicando o percentual sobre um valor já descontado.
    noRoutePayment: noRoutePayment,
    createdAt: createdAt,
  );

  /// Esta rota **rodou**: queimou combustível e tem custo a provisionar.
  ///
  /// Não é o mesmo que "foi uma rota". A ida sem rota entra aqui e fica de fora
  /// de `realized` — é a distinção que a feature inteira sustenta: dinheiro e
  /// quilômetro de um lado, contagem e pacotes do outro.
  ///
  /// É getter, e não a condição repetida, porque ela estava escrita em **três**
  /// arquivos: `vehicleCost.resolveProvision`, `addIter._withProvision` e
  /// `routeCard._profitBlock`. A de `addIter` roda **primeiro** e curto-circuita
  /// com `withProvision(null)`, então corrigir só a de `vehicleCost` deixava
  /// toda Sem Rota salvando sem provisão — o teste unitário verde, o KM até o CD
  /// nunca virando gasolina, e nenhum erro de compilação.
  bool get hasRun =>
      status == StatusRoute.concluido ||
      status == StatusRoute.pago ||
      status == StatusRoute.semRota;

  /// Coluna O da planilha: `valor − gasolina − peças`.
  ///
  /// `null` sem provisão, e nunca [value]. Sem saber o custo, dizer que o
  /// lucro é tudo que entrou seria a mentira mais cara que o app poderia
  /// contar.
  double? get profit => provision?.profitFrom(value);

  NewRouteModal({
    required this.id,
    required this.company,
    required this.dateRoute,
    required this.weekday,
    this.weather,
    required this.status,
    required this.value,
    this.kmInitial,
    this.kmFinal,
    this.packages,
    this.stops,
    this.adress,
    required this.startAt,
    this.endAt,
    this.isInsucesso,
    this.insucessoQnt,
    this.insucessoPorBairro = const {},
    this.provision,
    this.noRoutePayment,
    required this.createdAt,
  });

  NewRouteModal.fromMap(Map<String, dynamic> map)
    : id = map['id'],
      company = Company.values.firstWhere(
        (e) => e.toString() == 'Company.${map['company']}',
      ),
      dateRoute = map['dateRoute'],
      weekday = map['weekday'],
      weather = map['weather'],
      status = StatusRoute.values.firstWhere(
        (e) => e.toString() == 'StatusRoute.${map['status']}',
      ),
      value = map['value'],
      kmInitial = map['kmInitial'],
      kmFinal = map['kmFinal'],
      packages = map['packages'],
      stops = map['stops'],
      adress = (map['adress'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      startAt = _readStart(map),
      endAt = _readEnd(map),
      isInsucesso = map['isInsucesso'],
      insucessoQnt = map['insucessoQnt'],
      insucessoPorBairro = distributionFromList(map['insucessoPorBairro']),
      // Ausente em toda rota gravada antes deste campo existir, e o `is Map`
      // segura um documento corrompido sem derrubar a leitura da rota.
      provision = map['provision'] is Map
          ? RouteProvision.fromMap(
              Map<String, dynamic>.from(map['provision'] as Map),
            )
          : null,
      // Mesma guarda `is Map` da provisão: ausente em toda rota que não é
      // `semRota`, e um documento corrompido não pode derrubar a leitura.
      noRoutePayment = map['noRoutePayment'] is Map
          ? NoRoutePayment.fromMap(
              Map<String, dynamic>.from(map['noRoutePayment'] as Map),
            )
          : null,
      createdAt = map['createdAt'];

  Map<String, dynamic> toMap() => {
    'id': id,
    'company': company.toString().split('.').last,
    'dateRoute': dateRoute,
    'weekday': weekday,
    'weather': weather,
    'status': storedStatus(status),
    'value': value,
    'kmInitial': kmInitial,
    'kmFinal': kmFinal,
    'packages': packages,
    'stops': stops,
    'adress': adress,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt?.toIso8601String(),
    'isInsucesso': isInsucesso,
    'insucessoQnt': insucessoQnt,
    'insucessoPorBairro': distributionToList(insucessoPorBairro),
    'provision': provision?.toMap(),
    'noRoutePayment': noRoutePayment?.toMap(),
    'createdAt': createdAt,
  };

  /// Documentos gravados antes de `startAt` existir têm `dateRoute` e
  /// `hoursInitial`; sem nada legível, cai na data de cadastro para a rota
  /// não sumir da lista.
  static DateTime _readStart(Map<String, dynamic> map) {
    final direct = DateTime.tryParse(map['startAt'] ?? '');
    if (direct != null) return direct;

    final date = RouteTime.parseDate(map['dateRoute'] ?? '');
    if (date != null) {
      return RouteTime.combine(date, map['hoursInitial'] ?? '') ?? date;
    }

    return DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime(1970);
  }

  static DateTime? _readEnd(Map<String, dynamic> map) {
    final direct = DateTime.tryParse(map['endAt'] ?? '');
    if (direct != null) return direct;

    return RouteTime.resolveEnd(_readStart(map), map['hoursFinal']);
  }
}
