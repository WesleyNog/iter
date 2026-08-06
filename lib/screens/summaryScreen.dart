import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:iter/Utils/companySummary.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/widget/companySummaryCard.dart';
import 'package:iter/widget/periodFilter.dart';

/// `AGOSTO 2026` quando o filtro cobre um mês inteiro, as duas datas quando
/// não.
///
/// Vale a distinção: o card de total é o número que se leva na cabeça, e
/// "AGOSTO" diz o que ele cobre sem obrigar a reler o filtro lá em cima.
///
/// A comparação é por **dia**, não por `DateTime`: as roletas de data devolvem
/// o horário junto, e `==` entre `DateTime` faria 01/08 às 00:00 e 01/08 às
/// 14:30 serem meses diferentes.
String periodLabel(DateTime start, DateTime end) {
  final month = PeriodFilter.currentMonth(start);

  if (_sameDay(start, month.start) && _sameDay(end, month.end)) {
    return '${monthLabel(start.month).toUpperCase()} ${start.year}';
  }

  return '${PeriodFilter.formatDate(start)} a ${PeriodFilter.formatDate(end)}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// A aba Resumo: quanto entrou, quanto sobrou, quanto rodei e onde.
///
/// É a primeira tela a somar `NewRouteModal.provision` — sem ela, o lucro de
/// cada rota ficava gravado e ninguém via o total. Ver
/// `docs/specs/resumo-por-empresa.md`.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.user});

  final User user;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  /// Criado uma única vez: montar o stream dentro do build reinscreveria no
  /// Firestore a cada rebuild.
  late final Stream<List<NewRouteModal>> _routes = RouteController.watchAll(
    widget.user.uid,
  );

  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    // Mês corrente: "quanto fiz este mês" é a pergunta que se faz olhando um
    // resumo, e é o recorte de uma aba da planilha.
    final period = PeriodFilter.currentMonth();
    _start = period.start;
    _end = period.end;
  }

  /// Respiro do fim da lista: a `GlassNavBar` flutua por cima do conteúdo.
  double get _bottomGap => 24 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          // Fora do StreamBuilder: o filtro continua visível mesmo enquanto a
          // lista carrega, está vazia ou deu erro.
          child: PeriodFilter(
            start: _start,
            end: _end,
            onChanged: (start, end) => setState(() {
              _start = start;
              _end = end;
            }),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    return StreamBuilder<List<NewRouteModal>>(
      stream: _routes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Erro ao ler as rotas: ${snapshot.error}');
          return _message(
            icon: Icons.error_outline,
            title: 'Não foi possível carregar seu resumo.',
            subtitle: kDebugMode ? '${snapshot.error}' : 'Tente novamente.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final period = inPeriod(
          snapshot.data ?? const <NewRouteModal>[],
          start: _start,
          end: _end,
        );

        final total = companySummary(period);

        // Período sem rota realizada nenhuma: quatro cards repetindo "sem
        // rotas" é a mesma frase quatro vezes. Uma linha basta.
        if (total.isEmpty) {
          return _message(
            icon: Icons.calendar_today_outlined,
            title: 'Nenhuma rota entre '
                '${PeriodFilter.formatDate(_start)} e '
                '${PeriodFilter.formatDate(_end)}.',
            subtitle: 'Troque o período ou cadastre uma rota.',
          );
        }

        final byCompany = summaryByCompany(period);

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, _bottomGap),
          children: [
            CompanySummaryCard(
              summary: total,
              totalLabel: periodLabel(_start, _end),
            ),
            const SizedBox(height: 12),
            // `Company.values` e não as chaves do mapa: a ordem do enum é
            // estável, e a posição de cada card não muda de um mês para o
            // outro.
            for (final company in Company.values) ...[
              CompanySummaryCard(
                summary: byCompany[company]!,
                company: company,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 0, 32, _bottomGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
