import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/stationFilter.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/services/overpass.dart';

NearbyStation _nearby(
  String id, {
  String name = '',
  String? brand,
  String? suburb,
  String? address,
  double meters = 100,
}) => (
  station: FuelStation(
    id: id,
    name: name,
    brand: brand,
    suburb: suburb,
    address: address,
    lat: -3.73,
    lng: -38.52,
  ),
  meters: meters,
);

final _list = [
  _nearby(
    'a',
    name: 'Posto Aliança',
    brand: 'BR',
    suburb: 'Joaquim Távora',
    meters: 300,
  ),
  _nearby(
    'b',
    name: 'Posto Maraponga',
    brand: 'Petrobras',
    suburb: 'Maraponga',
    meters: 900,
  ),
  _nearby(
    'c',
    name: 'Posto Via Serrinha',
    brand: 'Shell',
    suburb: 'Serrinha',
    meters: 1500,
  ),
  _nearby(
    'd',
    name: 'Posto Del Rey',
    address: 'Avenida Bezerra de Menezes, 1000',
    meters: 2000,
  ),
];

List<String> _ids(List<NearbyStation> list) =>
    list.map((s) => s.station.id).toList();

void main() {
  test('consulta vazia devolve tudo, na mesma ordem', () {
    // Quem ordena é a Overpass, por distância. O filtro só tira.
    expect(_ids(filterStations(_list, '')), ['a', 'b', 'c', 'd']);
    expect(_ids(filterStations(_list, '   ')), ['a', 'b', 'c', 'd']);
  });

  test('acha pelo nome, sem acento e sem caixa', () {
    expect(_ids(filterStations(_list, 'ALIANCA')), ['a']);
    expect(_ids(filterStations(_list, 'del rey')), ['d']);
  });

  test('acha pelo bairro', () {
    expect(_ids(filterStations(_list, 'joaquim tavora')), ['a']);
    expect(_ids(filterStations(_list, 'serrinha')), ['c']);
  });

  test('acha pela rua — é o título de quem não tem nome', () {
    expect(_ids(filterStations(_list, 'bezerra')), ['d']);
  });

  test('pedaço de palavra também serve, porque ele ainda está digitando', () {
    expect(_ids(filterStations(_list, 'marap')), ['b']);
  });

  test('acha pela bandeira derivada, não só pelo texto da tag', () {
    // O posto "b" tem `brand=Petrobras`; quem busca "BR" pelo logo que está
    // vendo tem de achá-lo também.
    expect(_ids(filterStations(_list, 'br')), containsAll(['a', 'b']));
    expect(_ids(filterStations(_list, 'petrobras')), ['a', 'b']);
  });

  test('várias palavras: todas têm de bater, cada uma em qualquer campo', () {
    expect(_ids(filterStations(_list, 'shell serrinha')), ['c']);
    expect(filterStations(_list, 'shell maraponga'), isEmpty);
  });

  test('nada encontrado é lista vazia, não null', () {
    expect(filterStations(_list, 'ipiranga'), isEmpty);
  });

  test('a ordem de distância se mantém no resultado', () {
    expect(_ids(filterStations(_list, 'posto')), ['a', 'b', 'c', 'd']);
  });
}
