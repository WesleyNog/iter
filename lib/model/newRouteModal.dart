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
  final String? hoursInitial;
  final String? hoursFinal;
  final bool? isInsucesso;
  final int? insucessoQnt;
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
    this.hoursInitial,
    this.hoursFinal,
    this.isInsucesso,
    this.insucessoQnt,
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
      hoursInitial = map['hoursInitial'],
      hoursFinal = map['hoursFinal'],
      isInsucesso = map['isInsucesso'],
      insucessoQnt = map['insucessoQnt'],
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
    'hoursInitial': hoursInitial,
    'hoursFinal': hoursFinal,
    'isInsucesso': isInsucesso,
    'insucessoQnt': insucessoQnt,
    'createdAt': createdAt,
  };
}
