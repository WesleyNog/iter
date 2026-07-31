import 'package:flutter/material.dart';

Image getWeekdayIcon(int weekday) {
  switch (weekday) {
    case 1:
      return Image.asset('assets/images/SEG.png');
    case 2:
      return Image.asset('assets/images/TER.png');
    case 3:
      return Image.asset('assets/images/QUA.png');
    case 4:
      return Image.asset('assets/images/QUI.png');
    case 5:
      return Image.asset('assets/images/SEX.png');
    case 6:
      return Image.asset('assets/images/SAB.png');
    case 7:
      return Image.asset('assets/images/DOM.png');
    default:
      return Image.asset('assets/images/HELP.png');
  }
}
