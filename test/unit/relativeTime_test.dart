import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/relativeTime.dart';

/// O agora de todos os casos. Fixo, para o teste não depender do relógio — a
/// mesma razão de `sortByDate` receber uma `reference`.
final _agora = DateTime(2026, 8, 9, 12, 30);

String _quando(Duration atras) =>
    relativeWhen(_agora.subtract(atras), reference: _agora);

void main() {
  test('menos de um minuto é "agora"', () {
    expect(_quando(const Duration(seconds: 40)), 'agora');
  });

  test('minutos, horas e dias, cada um na sua faixa', () {
    expect(_quando(const Duration(minutes: 12)), 'há 12min');
    expect(_quando(const Duration(hours: 3)), 'há 3h');
    expect(_quando(const Duration(days: 2)), 'há 2d');
  });

  test('as bordas caem na faixa de baixo', () {
    expect(_quando(const Duration(minutes: 59)), 'há 59min');
    expect(_quando(const Duration(minutes: 60)), 'há 1h');
    expect(_quando(const Duration(hours: 23)), 'há 23h');
    expect(_quando(const Duration(hours: 24)), 'há 1d');
  });

  test('a partir de uma semana vira a data', () {
    // "há 43d" não diz nada que `06/08` não diga melhor.
    expect(_quando(const Duration(days: 7)), '02/08');
    expect(_quando(const Duration(days: 40)), '30/06');
  });

  test('dia e mês vêm com dois dígitos', () {
    expect(
      relativeWhen(DateTime(2026, 1, 5), reference: DateTime(2026, 3, 1)),
      '05/01',
    );
  });

  test('data no futuro é "agora", nunca "há -3min"', () {
    // Relógio adiantado e carimbo do servidor ainda não confirmado dão
    // diferença negativa, e "agora" é a leitura certa dos dois.
    expect(
      relativeWhen(_agora.add(const Duration(minutes: 3)), reference: _agora),
      'agora',
    );
  });
}
