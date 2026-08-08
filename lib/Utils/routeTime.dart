/// Conversões de data e hora das rotas.
///
/// Fica fora das telas porque é onde mora o erro silencioso: formato de data
/// gravado como texto, rota que vira o dia, duração calculada errado.
class RouteTime {
  /// `dd/MM/yyyy` → data. `null` quando o formato não bate.
  static DateTime? parseDate(String raw) {
    final parts = raw.split('/');
    if (parts.length != 3) return null;

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    return DateTime(year, month, day);
  }

  /// `HH:mm` → (hora, minuto). `null` quando o formato não bate.
  static ({int hour, int minute})? parseTime(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return (hour: hour, minute: minute);
  }

  /// Junta a data da rota com um horário `HH:mm`.
  static DateTime? combine(DateTime date, String time) {
    final parsed = parseTime(time);
    if (parsed == null) return null;

    return DateTime(
      date.year,
      date.month,
      date.day,
      parsed.hour,
      parsed.minute,
    );
  }

  /// Resolve o fim da rota a partir de [start] e do horário digitado.
  ///
  /// Fim menor ou igual ao início significa que a rota virou o dia: 22:00 às
  /// 02:00 termina no dia seguinte, e não 20 horas antes de começar.
  static DateTime? resolveEnd(DateTime start, String? rawEnd) {
    if (rawEnd == null || rawEnd.isEmpty) return null;

    final end = combine(start, rawEnd);
    if (end == null) return null;

    return end.isAfter(start) ? end : end.add(const Duration(days: 1));
  }

  /// `HH:mm` para exibição.
  static String formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// Duração legível: `9h30`, `45min`, `2h`.
  static String? formatDuration(DateTime start, DateTime? end) {
    if (end == null) return null;

    final total = end.difference(start);
    if (total.isNegative || total == Duration.zero) return null;

    return formatMinutes(total.inMinutes);
  }

  /// `4h22`, `45min`, `2h` — a partir dos minutos, sem inventar um par de
  /// datas para chegar lá.
  ///
  /// É o primitivo que [formatDuration] sempre foi por dentro. Ganhou nome
  /// próprio quando o ranking precisou do mesmo "4h22" que o dialog de perfil
  /// mostra: aquele card vinha somando a média a uma data arbitrária só para
  /// poder formatar, e uma segunda implementação do mesmo texto diverge na
  /// primeira vez que alguém mexe numa só.
  static String formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;

    if (hours == 0) return '${rest}min';
    if (rest == 0) return '${hours}h';
    return '${hours}h${rest.toString().padLeft(2, '0')}';
  }
}
