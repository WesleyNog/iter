import 'package:flutter/material.dart';
import 'package:iter/Utils/packageLabel.dart';
import 'package:iter/Utils/packageSession.dart';
import 'package:iter/widget/packageCounterBar.dart';

/// Qual recorte da carga a lista mostra.
///
/// Existe por causa do A: numa carga de 100 pacotes, achar as cinco agências
/// para tirar a que está fechada não pode exigir rolar a lista inteira. Tocar
/// no chip do A na barra abre a lista já filtrada.
enum PackageListFilter { todos, agencia, comercial, residencial, semLetra }

bool _passes(PackageListFilter filter, PackageEntry entry) {
  switch (filter) {
    case PackageListFilter.todos:
      return true;
    case PackageListFilter.agencia:
      return entry.type == PackageType.agencia;
    case PackageListFilter.comercial:
      return entry.type == PackageType.comercial;
    case PackageListFilter.residencial:
      return entry.type == PackageType.residencial;
    case PackageListFilter.semLetra:
      return entry.type == null;
  }
}

String _filterLabel(PackageListFilter filter) {
  switch (filter) {
    case PackageListFilter.todos:
      return 'Todos';
    case PackageListFilter.agencia:
      return 'A';
    case PackageListFilter.comercial:
      return 'C';
    case PackageListFilter.residencial:
      return 'R';
    case PackageListFilter.semLetra:
      return '?';
  }
}

/// Os pacotes lidos nesta sessão: deslizar tira da carga, tocar na letra
/// corrige o tipo.
///
/// Recebe a **mesma** [PackageSession] da tela da câmera e só pede a mudança
/// por [onRemove]/[onSetType] — quem muda a sessão é a tela, que também
/// redesenha a barra. A lista se redesenha sozinha depois de pedir, porque ela
/// vive numa folha por cima, fora da árvore da tela.
///
/// Remover não tem "desfazer" aqui: tirou sem querer, é ler a etiqueta de novo
/// e tocar em "Contar de novo" — o pacote volta com tudo que a etiqueta diz.
/// Não volta **sozinho**, porque a etiqueta da agência fechada continua na
/// frente da câmera logo depois de ser tirada.
class PackageList extends StatefulWidget {
  const PackageList({
    super.key,
    required this.session,
    required this.onRemove,
    required this.onSetType,
    this.initialFilter = PackageListFilter.todos,
  });

  final PackageSession session;
  final void Function(String shipmentId) onRemove;
  final void Function(String shipmentId, PackageType type) onSetType;
  final PackageListFilter initialFilter;

  @override
  State<PackageList> createState() => _PackageListState();
}

class _PackageListState extends State<PackageList> {
  late PackageListFilter _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final entries = widget.session.entries
        .where((entry) => _passes(_filter, entry))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            _countLabel(widget.session.total),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Deslize para tirar da carga. Toque na letra para corrigir o tipo. '
            'Tirou sem querer? Leia a etiqueta de novo e toque em '
            '"Contar de novo".',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              for (final filter in PackageListFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('filtro-${filter.name}'),
                    label: Text(_filterLabel(filter)),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    _filter == PackageListFilter.todos
                        ? 'Nenhum pacote lido ainda.'
                        : 'Nenhum pacote ${_filterLabel(_filter)} lido.',
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _row(entries[index]),
                ),
        ),
      ],
    );
  }

  Widget _row(PackageEntry entry) {
    final id = entry.shipmentId;
    final raw = entry.rawBairro;

    return Dismissible(
      key: ValueKey('pacote-$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade600,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.remove_circle_outline, color: Colors.white),
      ),
      onDismissed: (_) {
        widget.onRemove(id);
        setState(() {});
      },
      child: ListTile(
        leading: PopupMenuButton<PackageType>(
          key: ValueKey('tipo-$id'),
          tooltip: 'Corrigir o tipo',
          onSelected: (type) {
            widget.onSetType(id, type);
            setState(() {});
          },
          itemBuilder: (_) => [
            for (final type in PackageType.values)
              PopupMenuItem(
                value: type,
                child: Text(
                  '${packageTypeLetter(type)} · ${packageTypeLabel(type)}',
                ),
              ),
          ],
          child: PackageTypeBadge(type: entry.type),
        ),
        title: Text(entry.bairro ?? 'Sem bairro'),
        // O que o OCR leu e não casou: é o que deixa o entregador conferir na
        // etiqueta, e o que avisa quando o leiaute dela mudou.
        subtitle: entry.bairro == null && raw != null
            ? Text('Lido: "$raw", fora da lista de bairros')
            : null,
        // Os últimos dígitos do envio, impressos embaixo do código de barras:
        // é como achar na mão o pacote que a linha descreve.
        trailing: Text(
          '…${id.length > 5 ? id.substring(id.length - 5) : id}',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

String _countLabel(int total) =>
    total == 1 ? '1 pacote lido' : '$total pacotes lidos';
