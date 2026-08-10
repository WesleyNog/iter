import 'package:flutter/material.dart';
import 'package:iter/model/report.dart';

/// Escolher o motivo da denúncia. Devolve `null` se o usuário desistir.
///
/// Uma folha e não um `AlertDialog`: são cinco linhas tocáveis, e a lista
/// fechada é o desenho — ver `ReportReason`. Ver `docs/specs/amigos.md`.
Future<ReportReason?> showReportSheet(
  BuildContext context, {
  required bool isComment,
}) {
  return showModalBottomSheet<ReportReason>(
    context: context,
    showDragHandle: true,
    // `SingleChildScrollView` e não uma `Column` solta: uma folha comum é
    // limitada a 9/16 da altura da tela, e sete filhos fixos estouram isso num
    // aparelho baixo ou de lado. Rolar é o comportamento certo — cortar o
    // último motivo, não.
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                isComment ? 'Denunciar comentário' : 'Denunciar publicação',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                // Prometer moderação instantânea seria mentira: quem lê é uma
                // pessoa, e ela lê depois.
                'A denúncia é enviada para análise. Se quiser parar de ver essa '
                'pessoa agora, bloqueie.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
            for (final reason in ReportReason.values)
              ListTile(
                key: ValueKey('motivo-${reason.name}'),
                dense: true,
                title: Text(reason.label),
                onTap: () => Navigator.of(sheetContext).pop(reason),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
