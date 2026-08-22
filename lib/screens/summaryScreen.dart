import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:iter/Utils/companySummary.dart';
import 'package:iter/Utils/dated.dart';
import 'package:iter/Utils/expenseSummary.dart';
import 'package:iter/Utils/fuelEconomy.dart';
import 'package:iter/Utils/periodPreset.dart';
import 'package:iter/Utils/routeStats.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/controller/routeController.dart';
import 'package:iter/controller/maintenanceController.dart';
import 'package:iter/controller/supplyController.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/screens/expensesScreen.dart';
import 'package:iter/widget/companySummaryCard.dart';
import 'package:iter/widget/expenseCard.dart';
import 'package:iter/widget/periodFilter.dart';
import 'package:iter/widget/periodPresetFilter.dart';

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
  late final Stream<List<Supply>> _supplies = SupplyController.watchAll(
    widget.user.uid,
  );
  late final Stream<List<Maintenance>> _maintenances =
      MaintenanceController.watchAll(widget.user.uid);

  late DateTime _start;
  late DateTime _end;

  /// Qual atalho está aceso. As datas continuam sendo a fonte do recorte — o
  /// preset só diz qual chip acende e se as roletas aparecem.
  PeriodPreset _preset = PeriodPreset.esteMes;

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
          child: PeriodPresetFilter(
            preset: _preset,
            start: _start,
            end: _end,
            // `allowAll` fica no padrão (`false`): aqui o período é
            // obrigatório, todo card fala de um recorte.
            //
            // O preset chega anulável porque o mesmo widget serve a folha de
            // filtros da lista, onde existe o chip "Todo o período" e `null` é
            // o recorte aberto. Com `allowAll` desligado ele nunca chega nulo —
            // o `??` é o que mantém esta tela num recorte se alguém ligar a
            // flag um dia sem olhar para cá.
            onChanged: (preset, start, end) => setState(() {
              _preset = preset ?? PeriodPreset.esteMes;
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
            // Stream próprio, e não o das rotas: os gastos vêm de outra
            // coleção, e um `StreamBuilder` só para este card mantém os cards
            // de empresa desenhados enquanto os abastecimentos carregam.
            _expenses(),
          ],
        );
      },
    );
  }

  /// O card de gastos.
  ///
  /// **Nada aqui altera o lucro dos cards acima.** Aquele lucro já desconta
  /// combustível como provisão; subtrair os abastecimentos contaria a gasolina
  /// duas vezes. O card é extrato, e diz isso em uma linha.
  Widget _expenses() {
    return StreamBuilder<List<Supply>>(
      stream: _supplies,
      builder: (context, supplySnapshot) {
        return StreamBuilder<List<Maintenance>>(
          stream: _maintenances,
          builder: (context, maintenanceSnapshot) {
            // Se **qualquer** um dos dois falhar, o card some inteiro.
            //
            // Mostrar só a metade que carregou seria pior: o total apareceria
            // menor do que é, com cara de número certo. Esconder é honesto;
            // os cards de empresa acima continuam de pé.
            if (supplySnapshot.hasError || maintenanceSnapshot.hasError) {
              debugPrint(
                'Erro ao ler os gastos: '
                '${supplySnapshot.error ?? maintenanceSnapshot.error}',
              );
              return const SizedBox.shrink();
            }

            final supplies = inPeriodByDate(
              supplySnapshot.data ?? const <Supply>[],
              start: _start,
              end: _end,
            );
            final maintenances = inPeriodByDate(
              maintenanceSnapshot.data ?? const <Maintenance>[],
              start: _start,
              end: _end,
            );

            final summary = expenseSummary(supplies, maintenances);

            return ExpenseCard(
              summary: summary,
              // `periodEconomy` devolve `null` quando o período mistura
              // veículos — um km/l único não descreveria nenhum deles.
              economy: periodEconomy(supplies),
              onDetail: summary.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ExpensesScreen(
                          // As mesmas listas que o card somou: o detalhe não
                          // tem como discordar do total.
                          rows: expenseRows(supplies, maintenances),
                          periodLabel: periodLabel(_start, _end),
                        ),
                      ),
                    ),
            );
          },
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
