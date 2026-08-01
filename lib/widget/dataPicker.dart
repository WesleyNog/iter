import 'package:flutter/cupertino.dart';

/// Seletor de hora e minuto, no mesmo formato do seletor de data.
///
/// [initialTime] é só o ponto de partida da roleta — a data em si é ignorada,
/// interessa apenas hora e minuto.
void showCupertinoTimePicker(
  BuildContext context,
  DateTime initialTime,
  Function(DateTime) onTimeChanged,
) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) => Container(
      height: 250,
      padding: const EdgeInsets.only(top: 6.0),
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: SafeArea(
        top: false,
        child: CupertinoDatePicker(
          initialDateTime: initialTime,
          mode: CupertinoDatePickerMode.time,
          use24hFormat: true,
          onDateTimeChanged: (DateTime newTime) {
            onTimeChanged(newTime);
          },
        ),
      ),
    ),
  );
}

/// [minimumDate] e [maximumDate] travam a roleta no intervalo permitido.
///
/// É o jeito de impedir uma escolha inválida em vez de avisar depois dela: o
/// filtro de período usa isso para o fim nunca poder ser anterior ao início.
/// Ambos são opcionais — quem não passa nada continua com a roleta livre.
void showCupertinoDatePicker(
  BuildContext context,
  DateTime selectedDate,
  Function(DateTime) onDateChanged, {
  DateTime? minimumDate,
  DateTime? maximumDate,
}) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) => Container(
      height: 250,
      padding: const EdgeInsets.only(top: 6.0),
      // Margem inferior para evitar que o seletor fique sob a barra de navegação do iPhone
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: SafeArea(
        top: false,
        child: CupertinoDatePicker(
          initialDateTime: selectedDate,
          minimumDate: minimumDate,
          maximumDate: maximumDate,
          mode: CupertinoDatePickerMode.date,
          use24hFormat: true,
          // Atualiza o estado conforme o usuário gira a roleta
          onDateTimeChanged: (DateTime newDate) {
            onDateChanged(newDate);
          },
        ),
      ),
    ),
  );
}
