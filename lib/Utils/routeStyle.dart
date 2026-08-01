import 'package:flutter/material.dart';
import 'package:iter/model/newRouteModal.dart';

/// Aparência compartilhada das rotas: logo por empresa, cor e rótulo por
/// status. Fica fora das telas porque a lista e o cadastro precisam dos
/// mesmos valores — duas cópias divergem no primeiro ajuste de cor.

String companyLogo(Company company) {
  switch (company) {
    case Company.mercadolivre:
      return 'assets/logo/ML.jpg';
    case Company.amazon:
      return 'assets/logo/Amazon.png';
    case Company.shopee:
      return 'assets/logo/Shopee.png';
  }
}

String companyLabel(Company company) {
  switch (company) {
    case Company.mercadolivre:
      return 'Mercado Livre';
    case Company.amazon:
      return 'Amazon';
    case Company.shopee:
      return 'Shopee';
  }
}

String statusLabel(StatusRoute status) {
  switch (status) {
    case StatusRoute.agendado:
      return 'Agendado';
    case StatusRoute.andamento:
      return 'Em rota';
    case StatusRoute.concluido:
      return 'Concluído';
    case StatusRoute.pago:
      return 'Pago';
  }
}

Color statusColor(StatusRoute status) {
  switch (status) {
    case StatusRoute.agendado:
      return Colors.blue.shade400;
    case StatusRoute.andamento:
      return Colors.orange.shade400;
    case StatusRoute.concluido:
      return Colors.purple.shade400;
    case StatusRoute.pago:
      return Colors.teal.shade400;
  }
}

IconData statusIcon(StatusRoute status) {
  switch (status) {
    case StatusRoute.agendado:
      return Icons.calendar_today;
    case StatusRoute.andamento:
      return Icons.directions_car;
    case StatusRoute.concluido:
      return Icons.check_circle_outline;
    case StatusRoute.pago:
      return Icons.monetization_on_outlined;
  }
}

/// `DateTime.weekday` vai de 1 (segunda) a 7 (domingo).
String weekdayLabel(int weekday) {
  const labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  if (weekday < 1 || weekday > labels.length) return '';
  return labels[weekday - 1];
}
