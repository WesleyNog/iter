/// O recorte das telas de Gráficos e Resumo: um mês ou uma semana a alguns
/// passos do atual, ou as datas livres das roletas.
///
/// Substituiu os cinco atalhos (`PeriodPreset`) nessas duas telas porque "Mês
/// anterior" e "Semana anterior" não eram opções, eram o mesmo recorte um passo
/// para trás — e cinco opções não cabiam em fatias iguais. A folha de filtros
/// da Lista continua com os atalhos. Ver `docs/specs/seletores-de-vidro.md`.
///
/// Puro, com o "hoje" injetável, pela razão de `periodPreset.dart`: "que semana
/// vem depois desta" é conta, e conta dentro do `build` não se prova.
library;

import 'dart:math' as math;

import 'package:iter/Utils/periodPreset.dart';
import 'package:iter/Utils/routeStyle.dart' show monthLabel;

/// As três abas do seletor.
enum PeriodKind {
  mes,
  semana,

  /// O único sem passo: o recorte vem das roletas.
  personalizado;

  String get label => switch (this) {
    mes => 'Mês',
    semana => 'Semana',
    personalizado => 'Personalizado',
  };
}

class PeriodSelection {
  const PeriodSelection._(this.kind, this.offset, this.range);

  /// O mês a [offset] do atual — 0 é este mês, -1 o anterior.
  ///
  /// Nunca passa de 0: o seletor nunca ofereceu o futuro, e o Ranking também
  /// não vai além do mês corrente.
  factory PeriodSelection.month(int offset, [DateTime? today]) {
    final steps = math.min(0, offset);
    return PeriodSelection._(PeriodKind.mes, steps, monthAt(steps, today));
  }

  /// A semana, segunda a domingo, a [offset] da atual.
  factory PeriodSelection.week(int offset, [DateTime? today]) {
    final steps = math.min(0, offset);
    return PeriodSelection._(PeriodKind.semana, steps, weekAt(steps, today));
  }

  /// As datas que o usuário girou nas roletas.
  const PeriodSelection.custom(DateRange range)
    : this._(PeriodKind.personalizado, 0, range);

  final PeriodKind kind;

  /// Quantos meses ou semanas antes do atual. Zero no Personalizado, onde não
  /// quer dizer nada.
  final int offset;

  /// O recorte que as telas filtram — as duas pontas inclusive.
  final DateRange range;

  bool get hasSteps => kind != PeriodKind.personalizado;

  /// A seta › para no período atual (regra 2 da spec).
  bool get canGoForward => hasSteps && offset < 0;

  /// Um passo para trás (`-1`) ou para a frente (`+1`). No Personalizado não
  /// há passo, e a seleção volta como está.
  PeriodSelection step(int delta, [DateTime? today]) => switch (kind) {
    PeriodKind.mes => PeriodSelection.month(offset + delta, today),
    PeriodKind.semana => PeriodSelection.week(offset + delta, today),
    PeriodKind.personalizado => this,
  };

  /// Troca de aba sem perder o lugar.
  ///
  /// Mês e Semana caem no período que contém **o último dia que estava na
  /// tela, sem passar de hoje**. Voltar sempre para o atual seria mais simples
  /// e jogaria fora onde o usuário estava: quem olha agosto e quer ver as
  /// semanas de agosto teria de tocar ‹ nove vezes. O "sem passar de hoje" é o
  /// que faz o caso comum dar certo — o fim de outubro é futuro, e de Este Mês
  /// para Semana o esperado é esta semana, não a última de outubro.
  ///
  /// Personalizado mantém **as mesmas datas**: quem entra nele quer ajustar o
  /// recorte em que estava, a regra que o `PeriodPresetFilter` já seguia.
  PeriodSelection switchTo(PeriodKind to, [DateTime? today]) {
    if (to == kind) return this;
    if (to == PeriodKind.personalizado) return PeriodSelection.custom(range);

    final now = today ?? DateTime.now();
    final anchor = _dayOf(range.end).isAfter(_dayOf(now)) ? now : range.end;

    return to == PeriodKind.mes
        ? PeriodSelection.month(_monthsBetween(now, anchor), now)
        : PeriodSelection.week(_weeksBetween(now, anchor), now);
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Meses de [now] até [then] — negativo para o passado.
  static int _monthsBetween(DateTime now, DateTime then) =>
      (then.year - now.year) * 12 + then.month - now.month;

  /// Semanas de [now] até [then], contadas entre as segundas-feiras.
  ///
  /// Em UTC para a diferença ser de dias inteiros: entre duas meias-noites
  /// locais, um fuso com horário de verão daria 23 ou 25 horas, e `inDays`
  /// truncaria um dia.
  static int _weeksBetween(DateTime now, DateTime then) {
    DateTime utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    final days = utc(mondayOf(then)).difference(utc(mondayOf(now))).inDays;
    return days ~/ 7;
  }
}

/// O texto entre as setas: `OUTUBRO 2026` ou `05/10 – 11/10/2026`.
///
/// O mês é o rótulo do Ranking. A semana leva o ano uma vez quando as duas
/// pontas são do mesmo ano, e nas duas quando ela atravessa a virada — senão
/// `29/12 – 04/01/2026` diria que dezembro é de 2026.
String periodSelectionLabel(PeriodSelection selection) {
  final start = selection.range.start;
  final end = selection.range.end;

  if (selection.kind == PeriodKind.mes) {
    return '${monthLabel(start.month).toUpperCase()} ${start.year}';
  }

  String dayMonth(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  return start.year == end.year
      ? '${dayMonth(start)} – ${dayMonth(end)}/${end.year}'
      : '${dayMonth(start)}/${start.year} – ${dayMonth(end)}/${end.year}';
}
