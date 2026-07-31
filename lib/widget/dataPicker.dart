import 'package:flutter/cupertino.dart';

void showCupertinoDatePicker(
  BuildContext context,
  DateTime selectedDate,
  Function(DateTime) onDateChanged,
) {
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
