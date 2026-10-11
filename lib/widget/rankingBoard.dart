import 'package:flutter/material.dart';
import 'package:iter/Utils/ranking.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/chartCard.dart';
import 'package:iter/widget/rankTile.dart';
import 'package:iter/widget/sectionCard.dart';
import 'package:iter/widget/segmentedSelector.dart';

/// O placar do mês: um card com a cabeça azul (mês, critério, dica) e o corpo
/// com as linhas.
///
/// **Um card só** porque mês e critério são os controles *daquela* lista — em
/// dois blocos, a relação entre eles voltava a ser só proximidade. E a cabeça
/// azul separa os dois níveis de navegação: antes as abas do topo e o critério
/// eram duas barras cinzas idênticas, e o olho não sabia qual mandava na outra.
///
/// Fora da `RankingTab` pelo motivo que tirou o `RankTile` de lá: a aba abre o
/// Firestore no `initState`, e nada que mora dentro dela é alcançável por teste
/// de widget. Aqui tudo chega pronto e nada é lido.
///
/// ### Trocar de critério reordena, não troca a lista
///
/// Cada linha é um `AnimatedPositioned` com key por uid. O `Stack` casa as keys
/// entre um build e outro, então mudar a ordem **é** animar a posição — sem
/// medir nada depois do layout. Os participantes são sempre você e seus
/// amigos; só a régua muda, e a tela mostra exatamente isso: as mesmas pessoas
/// trocando de lugar. Números, medalhas e rótulos trocam no primeiro quadro —
/// anima a grandeza, nunca o número, a regra de `chartCard.dart`. Ver
/// `docs/specs/redesenho-amigos.md`.
class RankingBoard extends StatelessWidget {
  const RankingBoard({
    super.key,
    required this.month,
    required this.criterion,
    required this.onCriterion,
    required this.onPrevious,
    required this.onNext,
    required this.rows,
    required this.profiles,
    required this.me,
    required this.hasFriends,
    required this.loading,
    required this.failed,
    this.onRetry,
  });

  final DateTime month;
  final RankCriterion criterion;
  final ValueChanged<RankCriterion> onCriterion;

  /// `null` desabilita a seta — fora da janela de doze meses não há balde.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// A classificação já montada por `rankBy`. `null` é "nada carregado ainda".
  final List<RankRow>? rows;

  final Map<String, PublicProfile?> profiles;

  /// O uid de quem está olhando — a linha em gradiente.
  final String me;

  final bool hasFriends;

  /// Buscando baldes. Com [rows] na tela, quer dizer que **elas são do mês
  /// anterior**: o corpo esmaece e a cabeça mostra o progresso até o mês novo
  /// chegar.
  final bool loading;

  final bool failed;
  final VoidCallback? onRetry;

  /// A troca de lugar: mais longa que o indicador, porque o olho acompanha
  /// várias linhas ao mesmo tempo, e na curva de `ChartMotion`.
  static const Duration move = Duration(milliseconds: 450);

  static const double _pad = 8;

  /// O recuo lateral das linhas — o que sobra de largura vai para o nome.
  static const double _inset = 6;
  static const double _gap = 4;
  static const double _sectionGap = 10;

  static const _sectionStyle = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: SectionCard.decoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SectionCard.radius),
        // Transparente, mas `Material`: as setas do mês e o "Tentar de novo"
        // pintam o toque aqui, por cima do gradiente — sem ele, pintariam no
        // `Scaffold`, por baixo do card, e o toque não apareceria.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_header(), _body(context)],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ChartPalette.azul.gradient,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _monthBar(),
                SegmentedSelector<RankCriterion>(
                  keyPrefix: 'criterio',
                  tone: SegmentedTone.onBlue,
                  selected: criterion,
                  onChanged: onCriterion,
                  segments: [
                    for (final c in RankCriterion.values)
                      SegmentOption(
                        value: c,
                        label: c.label,
                        keySuffix: c.name,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    criterion.hint,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.84),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sempre os 2 px, com ou sem barra: a cabeça não pula de altura
          // quando a busca começa e termina.
          SizedBox(
            height: 2,
            child: loading
                ? LinearProgressIndicator(
                    minHeight: 2,
                    color: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _monthBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('mes-anterior'),
          icon: const Icon(Icons.chevron_left),
          color: Colors.white,
          disabledColor: Colors.white.withValues(alpha: 0.32),
          onPressed: onPrevious,
        ),
        SizedBox(
          width: 170,
          child: Text(
            '${monthLabel(month.month).toUpperCase()} ${month.year}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.6,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('mes-seguinte'),
          icon: const Icon(Icons.chevron_right),
          color: Colors.white,
          disabledColor: Colors.white.withValues(alpha: 0.32),
          onPressed: onNext,
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final rows = this.rows;

    if (rows == null && loading) return _skeleton(context);
    if (failed) {
      return _aviso(
        'Não foi possível carregar o ranking.',
        action: onRetry == null
            ? null
            : TextButton(
                key: const ValueKey('ranking-tentar-de-novo'),
                onPressed: onRetry,
                child: const Text('Tentar de novo'),
              ),
      );
    }
    if (rows == null) return const SizedBox(height: _pad * 2);

    if (!hasFriends) {
      return _aviso(
        'Adicione amigos para comparar. Por enquanto o ranking só tem você.',
      );
    }

    final disputa = rows.where((r) => r.ranked).toList();

    return AnimatedOpacity(
      key: const ValueKey('ranking-corpo'),
      // Os números na tela são do mês anterior enquanto o novo não chega. É a
      // regra do `getWeather`: "não sei ainda" não pode ter a aparência de um
      // dado — antes, setembro aparecia inteiro sob o título "OUTUBRO".
      opacity: loading ? 0.5 : 1,
      duration: const Duration(milliseconds: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (disputa.isEmpty)
            // O texto nomeia a amostra do critério, não "rotas": desde que a
            // porta passou a olhar a população da média, alguém pode ter vinte
            // rotas no mês e nenhuma com hora de fim — e "ninguém tem 5 rotas"
            // seria falso na cara de quem tem vinte.
            _aviso(
              'Ninguém tem $minimumRoutes ${criterion.sampleName} neste mês '
              'ainda — sem amostra não dá para comparar.',
            ),
          _rows(context, rows),
        ],
      ),
    );
  }

  /// As linhas, cada uma num `y` calculado.
  Widget _rows(BuildContext context, List<RankRow> rows) {
    final animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final duration = animate ? move : Duration.zero;
    final rowHeight = RankTile.heightFor(context);
    final sectionHeight = _sectionHeightFor(context);

    final disputa = rows.where((r) => r.ranked).toList();
    final fora = rows.where((r) => !r.ranked).toList();

    final children = <Widget>[];
    // A própria linha vai por último na lista, e é pintada por cima: quando as
    // linhas se cruzam na troca de critério, a que o usuário acompanha é a
    // dele. A ordem dos filhos do `Stack` só decide a pintura — o lugar de
    // cada um é o `top`.
    Widget? mine;
    var y = _pad;

    void addRow(RankRow row, int? position) {
      final tile = AnimatedPositioned(
        key: ValueKey('rank-${row.uid}'),
        duration: duration,
        curve: ChartMotion.curve,
        left: _inset,
        right: _inset,
        top: y,
        height: rowHeight,
        child: _FadeIn(
          animate: animate,
          child: RankTile(
            row: row,
            criterion: criterion,
            profile: profiles[row.uid],
            position: position,
            isMe: row.uid == me,
          ),
        ),
      );
      if (row.uid == me) {
        mine = tile;
      } else {
        children.add(tile);
      }
      y += rowHeight + _gap;
    }

    for (var i = 0; i < disputa.length; i++) {
      addRow(disputa[i], i + 1);
    }

    if (fora.isNotEmpty) {
      if (disputa.isNotEmpty) y += _sectionGap;
      children.add(
        AnimatedPositioned(
          key: const ValueKey('secao-sem-amostra'),
          duration: duration,
          curve: ChartMotion.curve,
          left: _pad * 2,
          right: _pad * 2,
          top: y,
          height: sectionHeight,
          child: _FadeIn(animate: animate, child: _sectionHeader()),
        ),
      );
      y += sectionHeight;
      for (final row in fora) {
        addRow(row, null);
      }
    }

    final own = mine;
    if (own != null) children.add(own);

    final height = rows.isEmpty ? _pad * 2 : y - _gap + _pad;

    return AnimatedContainer(
      duration: duration,
      curve: ChartMotion.curve,
      height: height,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  /// O traço que corre ao lado do título: a seção é parte do mesmo placar,
  /// não um card à parte.
  Widget _sectionHeader() {
    return Row(
      children: [
        Text(
          'AINDA SEM AMOSTRA',
          style: _sectionStyle.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE6E1EA)),
        ),
      ],
    );
  }

  static double _sectionHeightFor(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'A',
        style: DefaultTextStyle.of(context).style.merge(_sectionStyle),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height + 14;
  }

  /// Três linhas cinzas no lugar do spinner solto: o card já tem o tamanho e o
  /// desenho do que vem, e a tela não pula quando os baldes chegam.
  Widget _skeleton(BuildContext context) {
    final rowHeight = RankTile.heightFor(context);
    final fill = Colors.grey.shade200;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );

    return Padding(
      key: const ValueKey('ranking-esqueleto'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: _pad),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            SizedBox(
              height: rowHeight + _gap,
              child: Row(
                children: [
                  const SizedBox(width: 36),
                  CircleAvatar(radius: 19, backgroundColor: fill),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(120, 10),
                        const SizedBox(height: 6),
                        bar(80, 8),
                      ],
                    ),
                  ),
                  bar(44, 12),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _aviso(String message, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          if (action != null) ...[const SizedBox(height: 4), action],
        ],
      ),
    );
  }
}

/// Aparece em fade na primeira vez que monta, e fica.
///
/// `begin: 0` só vale no primeiro build: depois o `TweenAnimationBuilder` parte
/// de onde está, e como o fim é sempre 1, reordenar não pisca a linha. Quem
/// entra no ranking (o card montando, um amigo aceito) surge no lugar em vez de
/// estalar.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      child: child,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
    );
  }
}
