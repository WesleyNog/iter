/// O ritmo de uma rota: **minutos por parada**.
///
/// Existe como arquivo próprio porque três telas mostram este número — o card
/// da rota, o dialog de perfil e o Ranking — e cada uma o alcança por um
/// caminho diferente: uma rota em mãos, um documento de carreira, um balde de
/// mês. Três divisões escritas em três lugares é como duas telas passam a
/// discordar sobre o mesmo entregador.
///
/// **Por parada, e não por pacote.** O tempo de uma rota se gasta dirigindo até
/// o ponto, estacionando e subindo; cinco pacotes na mesma porta custam quase o
/// mesmo que um. Medir por pacote premiaria quem pega parada cheia sem ele ter
/// sido mais rápido em nada. De quebra é o campo mais disponível dos dois: o
/// formulário **exige** "Paradas" sempre que "Pacotes" está preenchido
/// (`addIter.dart`), então nunca há ritmo por pacote onde não haveria por
/// parada. Ver `docs/specs/amigos.md`.
library;

import 'package:iter/model/newRouteModal.dart';

/// Minutos por parada, a partir dos dois números crus.
///
/// `null` é **"não dá para calcular"**, nunca zero: rota sem parada informada
/// e rota instantânea não são "ritmo perfeito", são ausência de número. Zero
/// aqui coroaria campeão quem não preencheu nada.
///
/// Os dois lados têm de vir da **mesma população de rotas**. Somar os minutos
/// de todas as rotas cronometradas e dividir pelas paradas só das que têm
/// parada informada mistura duas contagens e produz um ritmo que não é o de
/// ninguém — foi exatamente esse o defeito do `minutesPerPackage` que este
/// arquivo substitui.
double? paceFrom(int minutes, int stops) {
  if (minutes <= 0 || stops <= 0) return null;
  return minutes / stops;
}

/// Os dois lados do ritmo de **uma** rota, ou `null` quando ela não tem ritmo.
///
/// É aqui que mora a regra "esta rota entra no ritmo", e ela vale em três
/// lugares: o card da rota divide os dois números, o balde do mês e a carreira
/// os **somam** antes de dividir. Escrita uma vez porque duas cópias divergem —
/// e a divergência apareceria da pior forma, com o card mostrando o ritmo de
/// uma rota que o Ranking não contou.
///
/// Três recusas, e cada uma tem um jeito próprio de errar:
///
/// - **sem hora de fim**, não há duração para dividir — é a rota que ainda está
///   acontecendo, ou aquela que o entregador não fechou;
/// - **duração não positiva** é documento corrompido, não rota de madrugada:
///   `RouteTime.resolveEnd` já rola a virada do dia na gravação;
/// - **menos de um minuto** entra por último e é a mais traiçoeira: a duração é
///   positiva, `inMinutes` trunca para zero, e a rota levaria as paradas dela
///   para o denominador sem levar tempo nenhum para o numerador — puxando o
///   ritmo do mês inteiro para baixo, que é o lado que lisonjeia.
({int minutes, int stops})? pacedOf(NewRouteModal route) {
  final end = route.endAt;
  if (end == null) return null;

  final minutes = end.difference(route.startAt).inMinutes;
  if (minutes <= 0) return null;

  final stops = route.stops ?? 0;
  if (stops <= 0) return null;

  return (minutes: minutes, stops: stops);
}

/// O ritmo de **uma** rota.
double? paceOf(NewRouteModal route) {
  final paced = pacedOf(route);
  return paced == null ? null : paceFrom(paced.minutes, paced.stops);
}

/// `5,7 min/parada` — o texto por extenso, do card da rota e do Ranking.
String formatPace(double minutesPerStop) =>
    '${_casa(minutesPerStop)} min/parada';

/// `6,0 m/p` — a forma curta, para onde a longa não cabe.
///
/// Existe **uma** razão para uma segunda função e não uma segunda
/// interpolação: o número é o mesmo, e é o arredondamento que não pode
/// divergir. `_casa` é o que as duas compartilham — sem ele, o card diria
/// `5,7 min/parada` e o dialog `5,8 m/p` para o mesmo entregador no dia em que
/// alguém mexesse numa só.
///
/// Onde cabe a longa, vai a longa: no card da rota e no Ranking o número tem a
/// linha inteira. Aqui ele divide uma coluna de terço de dialog com a duração
/// média, e "min/parada" por extenso quebraria a linha — que é o que desalinha
/// a coluna em relação às vizinhas.
String formatPaceShort(double minutesPerStop) => '${_casa(minutesPerStop)} m/p';

/// Uma casa decimal, vírgula, sempre — inclusive nos redondos: `6 m/p` ao lado
/// de `5,7 m/p` faz o primeiro parecer arredondado de mais longe do que está.
String _casa(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
