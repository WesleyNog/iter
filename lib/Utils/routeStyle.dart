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

/// A empresa de um rótulo, ou `null` quando o rótulo não é de nenhuma.
///
/// **Derivada de [companyLabel], nunca de uma segunda tabela** — mesma regra
/// que `nightVariantOf`/`daytimeOf` seguem no clima: um par que existisse só de
/// um lado traduziria numa direção e não desfaria na outra.
///
/// Existe porque `ProfileStats.topCompany` guarda o **rótulo**, não o enum:
/// `profiles/{uid}/stats/all` é documento publicado e já tem `topCompanyLabel`
/// gravado assim na carreira de todo mundo. Recuperar a empresa a partir dele
/// deixa o dialog desenhar a logo sem migrar documento nenhum — e devolve
/// `null`, que a tela sabe desenhar, para o rótulo que este app não conhece.
Company? companyFromLabel(String label) {
  for (final company in Company.values) {
    if (companyLabel(company) == label) return company;
  }
  return null;
}

/// Cor da empresa nos gráficos.
///
/// Não são as do seletor de `addIter` (âmbar/azul/laranja): ali o fundo é
/// branco, aqui é o gradiente azul do card, onde o azul da Amazon sumiria.
Color companyColor(Company company) {
  switch (company) {
    case Company.mercadolivre:
      return const Color(0xFFFFE082);
    case Company.amazon:
      return const Color(0xFF84FFFF);
    case Company.shopee:
      return const Color(0xFFFF8A80);
  }
}

/// Cor do status nos gráficos.
///
/// Não é [statusColor]: aquelas foram escolhidas para fundo branco, e o azul do
/// agendado com o teal do pago somem no gradiente do card. Aqui verde é pago —
/// dinheiro na conta — e o resto clareia na ordem do ciclo.
///
/// A Sem Rota é o **mesmo verde, mais claro**, e é a única cor deste arquivo
/// escolhida por parentesco: na barra do Resumo ela aparece colada no Pago, e no
/// card seguinte as duas somam num número só. Família igual diz isso sem
/// legenda; uma cor de outra matiz diria o contrário do que a conta faz.
Color statusChartColor(StatusRoute status) {
  switch (status) {
    case StatusRoute.agendado:
      return const Color(0xFF90CAF9);
    case StatusRoute.andamento:
      return const Color(0xFFFFCC80);
    case StatusRoute.concluido:
      return const Color(0xFFCE93D8);
    case StatusRoute.pago:
      return const Color(0xFF69F0AE);
    case StatusRoute.semRota:
      return const Color(0xFFB9F6CA);
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
    case StatusRoute.semRota:
      return 'Sem Rota';
  }
}

/// Cor do status no card branco da lista.
///
/// Aqui a Sem Rota **não** acompanha o verde do Pago, ao contrário de
/// [statusChartColor]: no gráfico o que importa é que as duas somam, e no card o
/// que importa é ler "esta não aconteceu". O cinza-azulado é o único tom apagado
/// da paleta, e é o ponto.
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
    case StatusRoute.semRota:
      return Colors.blueGrey.shade400;
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
    case StatusRoute.semRota:
      return Icons.do_not_disturb_on_outlined;
  }
}

/// `DateTime.month` vai de 1 (janeiro) a 12 (dezembro).
String monthLabel(int month) {
  const labels = [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];
  if (month < 1 || month > labels.length) return '';
  return labels[month - 1];
}

/// `DateTime.weekday` vai de 1 (segunda) a 7 (domingo).
String weekdayLabel(int weekday) {
  const labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  if (weekday < 1 || weekday > labels.length) return '';
  return labels[weekday - 1];
}

/// Nome por extenso, para onde cabe — o tooltip do gráfico de linha.
String weekdayFullLabel(int weekday) {
  const labels = [
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo',
  ];
  if (weekday < 1 || weekday > labels.length) return '';
  return labels[weekday - 1];
}
