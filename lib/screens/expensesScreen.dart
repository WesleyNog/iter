import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iter/Utils/currencyFormat.dart';
import 'package:iter/Utils/dated.dart';
import 'package:iter/Utils/expenseSummary.dart';
import 'package:iter/controller/maintenanceController.dart';
import 'package:iter/controller/supplyController.dart';
import 'package:iter/model/maintenance.dart';
import 'package:iter/model/supply.dart';
import 'package:iter/screens/addMaintenance.dart';
import 'package:iter/screens/addSupply.dart';
import 'package:iter/widget/iconSlideAction.dart';
import 'package:iter/widget/notificationPush.dart';

/// O extrato do período: abastecimentos e manutenções na mesma lista, por data
/// — e o lugar de corrigir um lançamento errado, deslizando a linha.
///
/// Recebe as **mesmas listas** que o card somou, em vez de abrir os próprios
/// streams: o detalhe nunca discorda do total que levou o usuário até aqui.
/// Dois streams poderiam divergir por um instante e mostrar um valor que não
/// fecha.
///
/// Editar e excluir mudam a **cópia** que a tela guarda, com o que o formulário
/// devolveu ou o que acabou de ser apagado — sem reler o banco. O card do
/// Resumo se atualiza sozinho pelo stream dele; ao voltar, os dois batem. Uma
/// edição que leve o lançamento para fora do período o tira daqui, pelo mesmo
/// filtro de datas do card.
///
/// Os dois tipos vêm misturados de propósito. O extrato responde "quanto saiu
/// do bolso e quando"; separar por natureza obrigaria a somar duas listas de
/// cabeça para ter a ordem cronológica.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.uid,
    required this.supplies,
    required this.maintenances,
    required this.start,
    required this.end,
    required this.periodLabel,
    this.supplyEditor,
    this.maintenanceEditor,
    this.supplyDeleter,
    this.maintenanceDeleter,
  });

  final String uid;
  final List<Supply> supplies;
  final List<Maintenance> maintenances;
  final DateTime start;
  final DateTime end;
  final String periodLabel;

  /// Abre o formulário de edição e devolve o que foi gravado, ou `null` se o
  /// usuário voltou sem salvar. Em produção, os formulários de verdade; no
  /// teste, uma resposta pronta — os formulários têm os testes deles.
  final Future<Supply?> Function(BuildContext context, Supply supply)?
  supplyEditor;
  final Future<Maintenance?> Function(
    BuildContext context,
    Maintenance maintenance,
  )?
  maintenanceEditor;

  /// Apaga o documento. Em produção, os controllers; no teste, sem Firestore.
  final Future<void> Function(String uid, String id)? supplyDeleter;
  final Future<void> Function(String uid, String id)? maintenanceDeleter;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late List<Supply> _supplies = [...widget.supplies];
  late List<Maintenance> _maintenances = [...widget.maintenances];

  List<ExpenseRow> get _rows => expenseRows(
    inPeriodByDate(_supplies, start: widget.start, end: widget.end),
    inPeriodByDate(_maintenances, start: widget.start, end: widget.end),
  );

  @override
  Widget build(BuildContext context) {
    final rows = _rows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.periodLabel,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ),
      ),
      body: rows.isEmpty
          ? Center(
              child: Text(
                'Nenhum gasto no período.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _slidable(rows[index], _row(rows[index], index)),
            ),
    );
  }

  /// Editar e excluir do lado direito, como na lista de rotas — o mesmo gesto
  /// para a mesma ideia, e o mesmo [iconSlideAction].
  Widget _slidable(ExpenseRow row, Widget child) {
    return Slidable(
      key: ValueKey('${row.kind.name}-${row.id}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.32,
        children: [
          iconSlideAction(
            keyName: 'gasto-editar-${row.id}',
            onPressed: () => _edit(row),
            icon: Icons.edit_outlined,
            color: Colors.blue.shade600,
            tooltip: 'Editar',
          ),
          iconSlideAction(
            keyName: 'gasto-excluir-${row.id}',
            onPressed: () => _confirmDelete(row),
            icon: Icons.delete_outline,
            color: Colors.red.shade600,
            tooltip: 'Excluir',
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _edit(ExpenseRow row) async {
    switch (row.kind) {
      case ExpenseKind.abastecimento:
        final supply = _supplies.where((s) => s.id == row.id).firstOrNull;
        if (supply == null) return;
        final editor = widget.supplyEditor ?? _openSupply;
        final saved = await editor(context, supply);
        if (saved == null || !mounted) return;
        setState(() {
          _supplies = [
            for (final item in _supplies) item.id == saved.id ? saved : item,
          ];
        });
      case ExpenseKind.manutencao:
        final maintenance = _maintenances
            .where((m) => m.id == row.id)
            .firstOrNull;
        if (maintenance == null) return;
        final editor = widget.maintenanceEditor ?? _openMaintenance;
        final saved = await editor(context, maintenance);
        if (saved == null || !mounted) return;
        setState(() {
          _maintenances = [
            for (final item in _maintenances)
              item.id == saved.id ? saved : item,
          ];
        });
    }
  }

  Future<Supply?> _openSupply(BuildContext context, Supply supply) {
    return Navigator.of(context).push<Supply>(
      MaterialPageRoute(
        builder: (_) => AddSupply(uid: widget.uid, supply: supply),
      ),
    );
  }

  Future<Maintenance?> _openMaintenance(
    BuildContext context,
    Maintenance maintenance,
  ) {
    return Navigator.of(context).push<Maintenance>(
      MaterialPageRoute(
        builder: (_) =>
            AddMaintenance(uid: widget.uid, maintenance: maintenance),
      ),
    );
  }

  /// Excluir pergunta antes, como na lista de rotas: é um gesto de deslizar,
  /// fácil de disparar sem querer, e não tem volta.
  ///
  /// O relato de preço que um abastecimento mandou ao posto **fica** — as
  /// regras de `gastop` não deixam apagar relato, e é de propósito: histórico
  /// de preço que se reescreve não é histórico.
  Future<void> _confirmDelete(ExpenseRow row) async {
    final isFuel = row.kind == ExpenseKind.abastecimento;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isFuel ? 'Excluir abastecimento?' : 'Excluir manutenção?'),
        content: Text(
          '${row.title} — ${CurrencyFormatterHelper.formatMoney(row.value)}. '
          'Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('gasto-confirmar-exclusao'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Excluir', style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (isFuel) {
        await (widget.supplyDeleter ?? SupplyController.delete)(
          widget.uid,
          row.id,
        );
      } else {
        await (widget.maintenanceDeleter ?? MaintenanceController.delete)(
          widget.uid,
          row.id,
        );
      }
      if (!mounted) return;

      setState(() {
        if (isFuel) {
          _supplies = [
            for (final item in _supplies)
              if (item.id != row.id) item,
          ];
        } else {
          _maintenances = [
            for (final item in _maintenances)
              if (item.id != row.id) item,
          ];
        }
      });
      showNotification(
        context: context,
        type: 'success',
        msg: isFuel ? 'Abastecimento excluído.' : 'Manutenção excluída.',
      );
    } catch (e) {
      debugPrint('Erro ao excluir o gasto: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível excluir. Tente novamente.',
      );
    }
  }

  Widget _row(ExpenseRow row, int index) {
    final isFuel = row.kind == ExpenseKind.abastecimento;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Fundo branco e não transparente: o deslizar move o card por cima da
        // lista, e um card vazado deixaria os ícones aparecerem através dele.
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // O ícone distingue as duas naturezas de relance, sem obrigar a ler
          // a linha de baixo.
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (isFuel ? Colors.orange : Colors.blueGrey).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isFuel ? Icons.local_gas_station_outlined : Icons.build_outlined,
              key: Key('expense-icon-$index'),
              size: 20,
              color: isFuel ? Colors.orange.shade700 : Colors.blueGrey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.title,
                        key: Key('expense-title-$index'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      CurrencyFormatterHelper.formatMoney(row.value),
                      key: Key('expense-value-$index'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _detail(row),
                  key: Key('expense-detail-$index'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `06/08/2026 · Substituição · Auto Center do Zé`.
  ///
  /// A data entra aqui e não no `ExpenseRow` porque o record guarda ISO, que
  /// ordena; quem formata para leitura é a tela.
  String _detail(ExpenseRow row) {
    final parsed = DateTime.tryParse(row.date);
    final data = parsed == null
        ? null
        : '${parsed.day.toString().padLeft(2, '0')}/'
              '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';

    return [
      ?data,
      if (row.subtitle.isNotEmpty) row.subtitle,
    ].join(' · ');
  }
}
