import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/periodPreset.dart';
import 'package:iter/widget/periodFilter.dart';
import 'package:iter/widget/periodPresetFilter.dart';

/// O recorte que a tela já estava mostrando quando o usuário toca num chip.
/// Datas de mentira, e é o ponto: nenhum atalho devolveria estas — só o
/// Personalizado, que é justamente quem tem de devolvê-las intactas.
final _inicio = DateTime(2026, 3, 7);
final _fim = DateTime(2026, 3, 19);

/// O que o widget emitiu, com os três valores juntos: preset separado das datas
/// esconderia exatamente o erro que o teste do Personalizado procura.
typedef _Emissao = ({PeriodPreset? preset, DateTime start, DateTime end});

Future<List<_Emissao>> _pump(
  WidgetTester tester, {
  PeriodPreset? preset = PeriodPreset.esteMes,
  bool allowAll = false,
}) async {
  // 411 pontos é a largura de Android barato — a mesma do teste do formulário
  // de manutenção. Aqui ela serve para o conteúdo dos chips ser mais largo que
  // a viewport, que é a situação real do seletor.
  tester.view.physicalSize = const Size(411, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final emitidas = <_Emissao>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PeriodPresetFilter(
          preset: preset,
          start: _inicio,
          end: _fim,
          allowAll: allowAll,
          onChanged: (p, s, e) => emitidas.add((preset: p, start: s, end: e)),
        ),
      ),
    ),
  );
  return emitidas;
}

/// Toca num chip **depois de trazê-lo para dentro da viewport**.
///
/// Sem o `ensureVisible`, os últimos chips ficam fora dos 411 pontos e o
/// `tap` cai no vazio — é a linha do scroll horizontal existindo de verdade.
/// Um trilho de segmentos iguais nunca precisaria disto, e é exatamente por
/// isso que ele apertaria os rótulos até quebrarem.
Future<void> _tocar(WidgetTester tester, String chave) async {
  final chip = find.byKey(ValueKey(chave));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  group('os chips', () {
    testWidgets('os cinco atalhos estão na linha', (tester) async {
      await _pump(tester);

      for (final option in PeriodPreset.values) {
        expect(
          find.byKey(ValueKey('periodo-${option.name}')),
          findsOneWidget,
          reason: 'faltou o chip de ${presetLabel(option)}',
        );
      }
    });

    testWidgets('sem allowAll não existe "Todo o período"', (tester) async {
      await _pump(tester);

      expect(find.byKey(const ValueKey('periodo-todo')), findsNothing);
    });

    testWidgets('com allowAll o "Todo o período" aparece', (tester) async {
      await _pump(tester, allowAll: true);

      expect(find.byKey(const ValueKey('periodo-todo')), findsOneWidget);
    });

    // A causa, não a aparência: rolando, cada chip recebe a largura do próprio
    // texto. É isso que garante que "Semana Anterior" não quebre linha, e vale
    // para qualquer fonte — a do teste é quadrada e mede outra coisa que a do
    // aparelho.
    testWidgets('vivem num scroll horizontal', (tester) async {
      await _pump(tester);

      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );

      expect(scroll.scrollDirection, Axis.horizontal);
    });

    // Segunda metade da mesma defesa: se este seletor for parar numa largura
    // fixa, o rótulo corta com "…" em vez de virar duas linhas. Quebra de linha
    // não levanta exceção, então nenhum teste de largura pegaria isso.
    testWidgets('cada rótulo é de uma linha só, com reticências', (
      tester,
    ) async {
      await _pump(tester, allowAll: true);

      final chaves = [
        'periodo-todo',
        for (final option in PeriodPreset.values) 'periodo-${option.name}',
      ];

      for (final chave in chaves) {
        final rotulo = tester.widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey(chave)),
            matching: find.byType(Text),
          ),
        );

        expect(rotulo.maxLines, 1, reason: '$chave quebra linha');
        expect(rotulo.overflow, TextOverflow.ellipsis, reason: '$chave corta');
      }
    });
  });

  group('as roletas de data', () {
    testWidgets('não estão na árvore fora do Personalizado', (tester) async {
      for (final option in PeriodPreset.values) {
        if (option == PeriodPreset.personalizado) continue;

        await _pump(tester, preset: option);
        expect(
          find.byType(PeriodFilter),
          findsNothing,
          reason: '${presetLabel(option)} não deveria mostrar Início e Fim',
        );
      }
    });

    testWidgets('não estão na árvore em "Todo o período"', (tester) async {
      await _pump(tester, preset: null, allowAll: true);

      expect(find.byType(PeriodFilter), findsNothing);
    });

    testWidgets('estão na árvore dentro do Personalizado', (tester) async {
      await _pump(tester, preset: PeriodPreset.personalizado);

      expect(find.byType(PeriodFilter), findsOneWidget);
    });
  });

  group('o toque', () {
    // Comparado contra `currentWeek()` do mesmo Utils, e não contra uma data
    // escrita à mão: "esta semana" muda de resposta toda segunda-feira, e um
    // literal aqui ficaria vermelho sozinho sete dias depois de ser escrito.
    testWidgets('em Esta Semana emite o recorte de currentWeek()', (
      tester,
    ) async {
      final emitidas = await _pump(tester);

      await _tocar(tester, 'periodo-estaSemana');

      final semana = currentWeek();
      expect(emitidas, hasLength(1));
      expect(emitidas.single.preset, PeriodPreset.estaSemana);
      expect(emitidas.single.start, semana.start);
      expect(emitidas.single.end, semana.end);
    });

    testWidgets('em Mês Anterior emite o recorte de previousMonth()', (
      tester,
    ) async {
      final emitidas = await _pump(tester);

      await _tocar(tester, 'periodo-mesAnterior');

      final mes = previousMonth();
      expect(emitidas.single.preset, PeriodPreset.mesAnterior);
      expect(emitidas.single.start, mes.start);
      expect(emitidas.single.end, mes.end);
    });

    // `rangeOf` devolve `null` no Personalizado, e esse `null` é "a pergunta
    // não se aplica", nunca "deu zero". Devolver o mês corrente aqui apagaria o
    // recorte do usuário toda vez que ele abrisse a seção para ajustá-lo.
    testWidgets('em Personalizado não altera as datas', (tester) async {
      final emitidas = await _pump(tester, preset: PeriodPreset.estaSemana);

      await _tocar(tester, 'periodo-personalizado');

      expect(emitidas.single.preset, PeriodPreset.personalizado);
      expect(emitidas.single.start, _inicio);
      expect(emitidas.single.end, _fim);
    });

    testWidgets('em Todo o período emite preset nulo e as mesmas datas', (
      tester,
    ) async {
      final emitidas = await _pump(tester, allowAll: true);

      await _tocar(tester, 'periodo-todo');

      expect(emitidas.single.preset, isNull);
      expect(emitidas.single.start, _inicio);
      expect(emitidas.single.end, _fim);
    });

    // O `PeriodFilter` só sabe de datas; quem carimba o preset é o pai. Sem
    // isso, girar uma roleta emitiria o recorte novo com o preset antigo e o
    // chip aceso passaria a mentir sobre o período.
    testWidgets('girar uma roleta continua sendo Personalizado', (
      tester,
    ) async {
      final emitidas = await _pump(tester, preset: PeriodPreset.personalizado);

      final roletas = tester.widget<PeriodFilter>(find.byType(PeriodFilter));
      roletas.onChanged(DateTime(2026, 1, 2), DateTime(2026, 1, 9));

      expect(emitidas.single.preset, PeriodPreset.personalizado);
      expect(emitidas.single.start, DateTime(2026, 1, 2));
      expect(emitidas.single.end, DateTime(2026, 1, 9));
    });
  });
}
