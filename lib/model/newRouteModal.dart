import 'package:iter/Utils/insucessoBairro.dart';
import 'package:iter/Utils/mapRead.dart';
import 'package:iter/Utils/routeTime.dart';

enum Company { mercadolivre, amazon, shopee }

enum StatusRoute { agendado, andamento, concluido, pago }

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
    createdAt: createdAt,
  );

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
      createdAt = map['createdAt'];

  Map<String, dynamic> toMap() => {
    'id': id,
    'company': company.toString().split('.').last,
    'dateRoute': dateRoute,
    'weekday': weekday,
    'weather': weather,
    'status': status.toString().split('.').last,
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
