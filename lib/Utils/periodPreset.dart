/// Os recortes de data que os filtros de período oferecem prontos.
///
/// Mora fora dos widgets pela mesma razão que `routeStats.dart`: "que dia
/// começa a semana passada" é conta, e conta dentro do `build` não tem como ser
/// provada sem bombear uma tela. Aqui é função pura, e o teste passa a
/// referência em vez de depender do relógio.
library;

/// Um recorte fechado, **as duas pontas inclusive**.
///
/// É o mesmo formato que `PeriodFilter.currentMonth` já devolvia — registro
/// anônimo, então nenhuma conversão é necessária entre os dois.
typedef DateRange = ({DateTime start, DateTime end});

/// Os atalhos do seletor de período.
///
/// [personalizado] é o único que **não** é um recorte: ele é o modo em que o
/// recorte vem das roletas. Por isso [rangeOf] devolve `null` para ele, e não
/// um mês qualquer — ver a nota daquela função.
enum PeriodPreset {
  esteMes,
  mesAnterior,
  estaSemana,
  semanaAnterior,
  personalizado,
}

String presetLabel(PeriodPreset preset) {
  switch (preset) {
    case PeriodPreset.esteMes:
      return 'Este Mês';
    case PeriodPreset.mesAnterior:
      return 'Mês Anterior';
    case PeriodPreset.estaSemana:
      return 'Esta Semana';
    case PeriodPreset.semanaAnterior:
      return 'Semana Anterior';
    case PeriodPreset.personalizado:
      return 'Personalizado';
  }
}

/// O recorte de um atalho, ou `null` quando ele não tem recorte próprio.
///
/// `null` é [PeriodPreset.personalizado], e quer dizer **"esta pergunta não se
/// aplica"** — nunca "deu zero". É o que faz o widget *manter* as datas que já
/// estavam na tela em vez de reescrevê-las: quem entra no Personalizado quer
/// ajustar o recorte em que estava, não começar de um mês qualquer.
///
/// Devolver o mês corrente aqui seria a versão que parece inofensiva e apaga a
/// escolha do usuário toda vez que ele reabre a seção.
DateRange? rangeOf(PeriodPreset preset, [DateTime? reference]) {
  switch (preset) {
    case PeriodPreset.esteMes:
      return currentMonth(reference);
    case PeriodPreset.mesAnterior:
      return previousMonth(reference);
    case PeriodPreset.estaSemana:
      return currentWeek(reference);
    case PeriodPreset.semanaAnterior:
      return previousWeek(reference);
    case PeriodPreset.personalizado:
      return null;
  }
}

/// Primeiro ao último dia do mês de [reference] — o recorte que o entregador
/// olha no dia a dia, e o padrão das três telas que filtram por período.
///
/// Dia 0 do mês seguinte é o último do atual, então fevereiro bissexto fecha no
/// 29 sem nenhum caso especial.
DateRange currentMonth([DateTime? reference]) {
  final now = reference ?? DateTime.now();
  return (
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 0),
  );
}

/// O mês inteiro anterior ao de [reference].
///
/// `month - 1` em janeiro vira o mês 0, que o construtor normaliza para
/// dezembro do ano anterior. É por isso que a virada de ano não precisa de um
/// `if` aqui — e é por isso que ela precisa de um teste.
DateRange previousMonth([DateTime? reference]) {
  final now = reference ?? DateTime.now();
  return (
    start: DateTime(now.year, now.month - 1, 1),
    end: DateTime(now.year, now.month, 0),
  );
}

/// Segunda a domingo da semana que contém [reference].
DateRange currentWeek([DateTime? reference]) {
  final monday = _mondayOf(reference ?? DateTime.now());
  return (start: monday, end: _plusDays(monday, 6));
}

/// A semana fechada imediatamente anterior à de [reference].
///
/// Numa segunda-feira isso é a semana que acabou ontem, não a que está
/// correndo — que é o que "semana anterior" quer dizer para quem fecha conta.
DateRange previousWeek([DateTime? reference]) {
  final monday = _plusDays(_mondayOf(reference ?? DateTime.now()), -7);
  return (start: monday, end: _plusDays(monday, 6));
}

/// A segunda-feira da semana de [day], à meia-noite.
///
/// `DateTime.weekday` já é 1 (segunda) a 7 (domingo), então a semana
/// segunda-a-domingo sai sem nenhuma conversão — e domingo, que é o dia em que
/// a conta errada devolve a semana seguinte, cai naturalmente no fim da sua.
DateTime _mondayOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - 1));

/// Soma dias pelo **construtor**, nunca por `Duration`.
///
/// `add(Duration(days: 7))` soma 168 horas, não sete dias: num fuso com horário
/// de verão isso cai na hora errada do dia certo, e a ponta do recorte passa a
/// incluir ou excluir um dia por acidente. O construtor normaliza — dia 0 é o
/// último do mês anterior, dia 32 é o primeiro do seguinte.
///
/// Fortaleza não tem horário de verão e o Brasil o extinguiu em 2019, então
/// hoje os dois caminhos dão o mesmo resultado. Este é escolhido porque
/// continua certo se o app rodar em outro fuso, o custo de acertar é zero, e o
/// erro do outro aparece uma vez por ano.
DateTime _plusDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);
