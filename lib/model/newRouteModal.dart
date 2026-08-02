import 'package:iter/Utils/insucessoBairro.dart';
import 'package:iter/Utils/routeTime.dart';

enum Company { mercadolivre, amazon, shopee }

enum StatusRoute { agendado, andamento, concluido, pago }

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

  final String createdAt;

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
