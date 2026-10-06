import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iter/Utils/bairros.dart';
import 'package:iter/Utils/packageLabel.dart';
import 'package:iter/Utils/packageSession.dart';
import 'package:iter/widget/selectAdress.dart';

/// A conferência antes de gravar: pacotes e paradas editáveis, bairros pelo
/// mesmo seletor do formulário, e o que a leitura **não** conseguiu dizer.
///
/// Os números saem da sessão, mas quem assina é o entregador. A câmera conta o
/// que viu; ele sabe que tirou duas caixas da agência fechada sem ler de novo.
///
/// O que não casou com a lista de bairros aparece aqui, com a contagem, em vez
/// de sumir: "40 pacotes sem bairro" é o único sinal de que a etiqueta mudou de
/// leiaute — o parser degrada sem erro nenhum.
class PackageReview extends StatefulWidget {
  const PackageReview({
    super.key,
    required this.session,
    required this.previousBairros,
    required this.onSave,
    required this.onBack,
  });

  final PackageSession session;

  /// Os bairros que a rota tinha antes, para dizer o que a leitura substitui.
  final List<String> previousBairros;

  final ValueChanged<PackageLoad> onSave;
  final VoidCallback onBack;

  @override
  State<PackageReview> createState() => _PackageReviewState();
}

class _PackageReviewState extends State<PackageReview> {
  late final _packages = TextEditingController(
    text: widget.session.total.toString(),
  );
  late final _stops = TextEditingController(
    text: widget.session.stops.toString(),
  );
  final _search = TextEditingController();

  /// Começa na ordem da sessão (mais pacotes primeiro); o seletor acrescenta no
  /// fim e tira no lugar, e é essa ordem que vai para `adress`.
  late final List<String> _bairros = [...widget.session.bairros];

  @override
  void dispose() {
    _packages.dispose();
    _stops.dispose();
    _search.dispose();
    super.dispose();
  }

  int? get _packageCount => int.tryParse(_packages.text);
  int? get _stopCount => int.tryParse(_stops.text);

  /// O que impede salvar, ou `null`. Parada é um endereço com ao menos um
  /// pacote: mais paradas que pacotes é digitação errada, não carga.
  String? get _problem {
    final packages = _packageCount;
    final stops = _stopCount;
    if (packages == null || packages <= 0) return 'Informe quantos pacotes.';
    if (stops == null || stops <= 0) return 'Informe quantas paradas.';
    if (stops > packages) return 'Mais paradas que pacotes.';
    return null;
  }

  void _save() {
    if (_problem != null) return;
    widget.onSave(
      loadOf(
        widget.session,
        packages: _packageCount!,
        stops: _stopCount!,
        bairros: _bairros,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final measured = session.pacotesPorBairro;
    final replaced = widget.previousBairros
        .where((bairro) => !_bairros.contains(bairro))
        .toList();
    final problem = _problem;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Conferir a carga', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            _typeSummary(session),
            key: const ValueKey('resumo-tipos'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          // Lado a lado e com a largura dividida: dois números curtos não
          // precisam de uma linha cada.
          Row(
            children: [
              Expanded(child: _number('Pacotes', _packages, 'campo-pacotes')),
              const SizedBox(width: 12),
              Expanded(child: _number('Paradas', _stops, 'campo-paradas')),
            ],
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                problem,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text('Bairros', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                key: const ValueKey('editar-bairros'),
                onPressed: () => showBairrosMultiSelect(
                  context,
                  fortaleza_bairros,
                  _bairros,
                  _search,
                  setState,
                ),
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Editar'),
              ),
            ],
          ),
          if (_bairros.isEmpty)
            const Text('Nenhum bairro reconhecido.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final bairro in _bairros)
                  Chip(
                    label: Text(
                      measured[bairro] == null
                          ? bairro
                          : '$bairro · ${measured[bairro]}',
                    ),
                  ),
              ],
            ),
          if (replaced.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Substitui o que estava marcado no agendamento: '
                '${replaced.join(', ')}.',
                key: const ValueKey('substitui'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (session.withoutBairro > 0) ...[
            const SizedBox(height: 16),
            _unmatched(session, theme),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('salvar-carga'),
            onPressed: problem == null ? _save : null,
            child: const Text('Salvar e iniciar a rota'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('voltar-a-ler'),
            onPressed: widget.onBack,
            child: const Text('Voltar a ler'),
          ),
        ],
      ),
    );
  }

  Widget _number(String label, TextEditingController controller, String key) {
    return TextField(
      key: ValueKey(key),
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _unmatched(PackageSession session, ThemeData theme) {
    final unmatched = session.unmatchedBairros;
    final unread =
        session.withoutBairro -
        unmatched.values.fold<int>(0, (total, n) => total + n);

    return Container(
      key: const ValueKey('sem-bairro'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.withoutBairro == 1
                ? '1 pacote sem bairro reconhecido'
                : '${session.withoutBairro} pacotes sem bairro reconhecido',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final entry in unmatched.entries)
            Text('${entry.value} em "${entry.key}", que não está na lista'),
          if (unread > 0)
            Text(
              unread == 1
                  ? '1 sem endereço legível'
                  : '$unread sem endereço legível',
            ),
          const SizedBox(height: 4),
          Text(
            'Eles contam no total. Se o bairro deles faltar acima, ponha em '
            'Editar.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// "R 70 · C 12 · A 5", e o "?" só quando existe — o mesmo que a barra
/// mostrava, para o lançamento no app do Mercado Livre.
String _typeSummary(PackageSession session) => [
  for (final type in PackageType.values)
    '${packageTypeLetter(type)} ${session.count(type)}',
  if (session.untyped > 0) '? ${session.untyped}',
].join('  ·  ');
