import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:iter/Utils/profileStats.dart';
import 'package:iter/Utils/routePace.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/Utils/routeTime.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Perfil do entregador, quase em tela cheia.
///
/// O widget **recebe** tudo que mostra e não lê o usuário logado por dentro:
/// assim dá para testá-lo sem Firebase, e a aba Friends só vai precisar passar
/// outro uid. O botão de ação também é parâmetro — "Compartilhar" hoje,
/// "Seguir" amanhã, sem tocar aqui.
Future<void> showProfileDialog(
  BuildContext context, {
  required String name,
  String? nickName,
  String? photoUrl,
  required Future<ProfileStats?> stats,
  required String actionLabel,
  VoidCallback? onAction,
  VoidCallback? onBlock,
  String? qrPayload,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ProfileDialog(
      name: name,
      nickName: nickName,
      photoUrl: photoUrl,
      stats: stats,
      actionLabel: actionLabel,
      onAction: onAction,
      onBlock: onBlock,
      qrPayload: qrPayload,
    ),
  );
}

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({
    super.key,
    required this.name,
    required this.stats,
    required this.actionLabel,
    this.onAction,
    this.onBlock,
    this.nickName,
    this.photoUrl,
    this.qrPayload,
  });

  final String name;
  final String? nickName;
  final String? photoUrl;

  /// Nome e foto já vêm da AppBar e aparecem na hora; só os números esperam o
  /// Firestore. Segurar o dialog fechado por meio segundo faz o toque parecer
  /// que não funcionou.
  ///
  /// Resolver em `null` significa **"não posso ver"**, não "zero": os números
  /// de carreira são legíveis só por amigos, e mostrar zeros para um
  /// desconhecido seria dizer que ele nunca rodou.
  final Future<ProfileStats?> stats;

  final String actionLabel;

  /// `null` desabilita o botão de verdade.
  ///
  /// É o que a aba Amigos precisa para o perfil do próprio usuário: um
  /// `onPressed` vazio deixaria o botão clicável sem efeito, que é pior do que
  /// apagado — parece que o toque não funcionou.
  final VoidCallback? onAction;

  /// Bloquear, discreto, embaixo da ação principal. `null` esconde a linha —
  /// é o que o próprio perfil do usuário e a tela de busca usam.
  ///
  /// Aqui e não num menu porque este dialog **é** a tela de "quem é essa
  /// pessoa?": é olhando para o nome e a foto de quem insiste em te convidar
  /// que a decisão de bloquear é tomada. Recusar sozinho não resolve — quem é
  /// recusado reconvida, e o badge acende de novo.
  final VoidCallback? onBlock;

  /// O conteúdo do QR Code — `friendQrPayload(apelido)`. `null` esconde o
  /// botão e a face de trás inteira.
  ///
  /// Vem de fora, como todo o resto: o dialog não sabe quem está logado, e é
  /// isso que o mantém testável sem Firebase. Só o **próprio** perfil passa
  /// este parâmetro — o QR é o seu convite, e oferecer o de um amigo seria
  /// deixar qualquer um distribuir o convite de outra pessoa.
  final String? qrPayload;

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog>
    with SingleTickerProviderStateMixin {
  static const _bannerHeight = 116.0;
  static const _avatarRadius = 46.0;
  static const _flipDuration = Duration(milliseconds: 420);

  /// Criado no `initState`, **não** num `late final` inicializado por uso.
  ///
  /// Com o `late`, o perfil de um amigo — que não tem QR e portanto nunca lê
  /// este campo no `build` — só tocava nele dentro do `dispose()`, e aí
  /// `vsync: this` procura o `TickerMode` num contexto já desativado:
  /// "Looking up a deactivated widget's ancestor is unsafe" ao **fechar** o
  /// dialog. O teste do flip é que revelou; o caminho quebrado era o dos
  /// perfis alheios, que nem flip têm.
  late final AnimationController _flip;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this, duration: _flipDuration);
  }

  /// A face de trás só existe depois de meio giro. Antes disso o que se vê é
  /// a frente girando, e desenhar o QR ali o mostraria espelhado — um QR
  /// espelhado não é ilegível, é **outro** dado, e o leitor recusa.
  bool get _showingBack => _flip.value > 0.5;

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_flip.isCompleted || _flip.velocity > 0) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            const SizedBox(height: 10),
            Text(
              widget.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            if (widget.nickName != null && widget.nickName!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '@${widget.nickName}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 22),
            // Só o miolo gira. O banner, a foto, o nome e o apelido ficam de
            // fora do `Transform` de propósito: é o que faz o giro ler como
            // "o mesmo cartão virou", e não como "abriu outra tela". Também é
            // o que garante que o apelido continue à vista na face do QR —
            // quando a câmera do outro não coopera, digitar é a saída.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _flipavel(),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                widget.onBlock == null ? 24 : 4,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        widget.actionLabel.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  if (widget.qrPayload != null) ...[
                    const SizedBox(width: 8),
                    _botaoQr(),
                  ],
                ],
              ),
            ),
            if (widget.onBlock != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton.icon(
                  key: const ValueKey('bloquear-perfil'),
                  onPressed: widget.onBlock,
                  icon: Icon(
                    Icons.block,
                    size: 17,
                    color: Colors.grey.shade600,
                  ),
                  label: Text(
                    'Bloquear',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// O botão que vira o cartão.
  ///
  /// Fica **ao lado** do compartilhar, e não dentro dele, porque são duas
  /// ações diferentes: compartilhar manda o convite para longe, o QR resolve
  /// o caso de estar perto — os dois no galpão, um mostrando a tela para o
  /// outro. É esse o caso em que digitar apelido no celular alheio é o que
  /// acontece hoje.
  Widget _botaoQr() {
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final voltando = _showingBack;
        return Container(
          decoration: BoxDecoration(
            color: voltando
                ? const Color(0xFF1976D2)
                : const Color(0xFF1976D2).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(30),
          ),
          child: IconButton(
            key: const ValueKey('girar-qr'),
            tooltip: voltando ? 'Ver os números' : 'Mostrar meu QR Code',
            onPressed: _toggle,
            icon: Icon(
              voltando ? Icons.badge_outlined : Icons.qr_code_2_rounded,
              color: voltando ? Colors.white : const Color(0xFF1976D2),
            ),
          ),
        );
      },
    );
  }

  /// O miolo que gira: os números de um lado, o QR do outro.
  ///
  /// `AnimatedSize` porque as duas faces **não** têm a mesma altura, e nenhuma
  /// das duas tem altura fixa: a dos números muda com o perfil (uma carreira
  /// sem empresa mede 158 px, uma completa 144). Cravar uma constante aqui
  /// serviria a um perfil e faria o cartão pular no meio do giro em todos os
  /// outros — é a mesma armadilha do `_StatsPlaceholder`, e lá ela já custou
  /// dois números errados. Deixar a altura ser animada junto com a rotação
  /// resolve sem constante nenhuma.
  Widget _flipavel() {
    if (widget.qrPayload == null) return _stats();

    return AnimatedSize(
      duration: _flipDuration,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final angulo = _flip.value * math.pi;

          return Transform(
            alignment: Alignment.center,
            // A perspectiva é o que faz o giro parecer um cartão virando e
            // não um desenho encolhendo na horizontal.
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angulo),
            child: _showingBack
                // Desvira o conteúdo: sem esta segunda rotação o QR fica
                // espelhado, e QR espelhado não é um QR difícil de ler — é
                // outro dado, que o leitor recusa.
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _faceQr(),
                  )
                : _stats(),
          );
        },
      ),
    );
  }

  /// A face de trás: o QR e o que fazer com ele.
  Widget _faceQr() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          // Branco atrás e uma margem clara em volta não são enfeite: leitor
          // de QR precisa de contraste e da "zona quieta" da borda para achar
          // os três quadrados de canto.
          child: QrImageView(
            key: const ValueKey('qr-amigo'),
            data: widget.qrPayload!,
            version: QrVersions.auto,
            size: 190,
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero,
            // O apelido é curto e o QR sai com pouca informação; a correção
            // mais alta cabe de graça e sobrevive a tela suja e foto tremida.
            errorCorrectionLevel: QrErrorCorrectLevel.H,
          ),
        ),
        const SizedBox(height: 12),
        _note(
          'Peça para o colega ler este código em Amigos › Adicionar amigo.',
        ),
      ],
    );
  }

  /// Banner com a foto cavalgando a borda de baixo.
  ///
  /// A altura reservada é a do banner **mais** o pedaço da foto que vaza, para
  /// nada depender de o `Stack` conseguir desenhar fora do card — o `Dialog`
  /// recorta nos cantos arredondados.
  Widget _header(BuildContext context) {
    return SizedBox(
      height: _bannerHeight + _avatarRadius,
      child: Stack(
        children: [
          Container(
            height: _bannerHeight,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0D47A1),
                  Color(0xFF1976D2),
                  Color(0xFF42A5F5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            top: _bannerHeight - _avatarRadius,
            left: 0,
            right: 0,
            child: Center(child: _avatar()),
          ),
        ],
      ),
    );
  }

  Widget _avatar() {
    final url = widget.photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    final initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim().characters.first.toUpperCase();

    return CircleAvatar(
      radius: _avatarRadius,
      backgroundColor: Colors.white,
      child: CircleAvatar(
        radius: _avatarRadius - 4,
        backgroundColor: Colors.blue.shade100,
        backgroundImage: hasPhoto ? NetworkImage(url) : null,
        child: hasPhoto
            ? null
            : Text(
                initial,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _stats() {
    return FutureBuilder<ProfileStats?>(
      future: widget.stats,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Erro ao ler as métricas do perfil: ${snapshot.error}');
          return _note(
            kDebugMode
                ? '${snapshot.error}'
                : 'Não foi possível carregar suas métricas.',
          );
        }

        // "Ainda não chegou" e "não posso ver" são estados diferentes, e o
        // `data == null` sozinho os confundiria — o shimmer ficaria para
        // sempre em quem não é amigo.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _StatsPlaceholder();
        }

        final data = snapshot.data;
        if (data == null) {
          return _note('Os números aparecem depois que vocês forem amigos.');
        }

        return Column(
          children: [
            Row(
              children: [
                _bigStat('${data.routes}', 'Rotas'),
                _bigStat('${data.deliveredPackages}', 'Pacotes'),
                _bigStat('${data.stops}', 'Paradas'),
              ],
            ),
            const SizedBox(height: 18),
            Divider(color: Colors.grey.shade200, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                _smallStat(
                  Icons.report_gmailerrorred_outlined,
                  'Insucesso',
                  data.failureRate == null
                      ? '—'
                      : '${data.failureRate!.toStringAsFixed(1)}%',
                ),
                _smallStatOf(
                  Icons.local_shipping_outlined,
                  'Mais rodada',
                  _empresa(data.topCompany),
                ),
                // Os dois números na mesma linha, e nesta ordem: a duração é
                // o que o entregador reconhece do próprio dia, o ritmo é o que
                // o compara com quem pega rota de outro tamanho. Trocar um
                // pelo outro perderia metade da resposta — quem vê "6,0 m/p"
                // sozinho não sabe se rodou duas horas ou nove.
                _smallStatOf(
                  Icons.timer_outlined,
                  'Tempo médio',
                  _tempo(data.averageDuration, data.minutesPerStop),
                ),
              ],
            ),
            if (data.routes == 0) ...[
              const SizedBox(height: 16),
              _note('Cadastre sua primeira rota para ver seus números.'),
            ],
          ],
        );
      },
    );
  }

  /// O mesmo formato da lista e do ranking (`9h30`, `45min`).
  String _duration(Duration? average) {
    if (average == null) return '—';
    return RouteTime.formatMinutes(average.inMinutes);
  }

  /// A duração média e o ritmo, numa linha só: `4h26 · 6,0 m/p`.
  ///
  /// Ritmo `null` deixa só a duração, em vez de um segundo `—` pendurado
  /// depois do separador: é a carreira publicada antes deste número existir,
  /// que não guardou as paradas cronometradas e volta sozinha quando o dono do
  /// perfil reabrir o app.
  ///
  /// `FittedBox` porque o pior caso não cabe. Medido com Roboto em 390 dp, a
  /// coluna tem ~103 px e `12h30 · 22,4 m/p` pede mais — sem ele, o texto
  /// quebraria em duas linhas e desalinharia a coluna em relação às vizinhas,
  /// que é exatamente o defeito que juntar os dois números veio corrigir. O
  /// mesmo recurso que `_bigStat` já usa neste arquivo, e pela mesma razão:
  /// encolher um pouco é melhor do que quebrar.
  Widget _tempo(Duration? average, double? minutesPerStop) {
    final texto = minutesPerStop == null
        ? _duration(average)
        : '${_duration(average)} · ${formatPaceShort(minutesPerStop)}';

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        texto,
        maxLines: 1,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _bigStat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1976D2),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _smallStat(IconData icon, String label, String value) {
    return _smallStatOf(
      icon,
      label,
      Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// A logo da empresa e a fatia dela, lado a lado.
  ///
  /// Era `Mercado Livre\n60%`, duas linhas — e duas linhas numa coluna só
  /// desalinham o valor dela em relação às vizinhas, que têm uma. A logo diz a
  /// mesma coisa em menos espaço e é o que o entregador reconhece primeiro; o
  /// nome continua alcançável por toque longo e pelo leitor de tela.
  ///
  /// Rótulo que este app não conhece cai no texto: `companyFromLabel` devolve
  /// `null` e não há logo para desenhar. É o caso do documento de carreira
  /// escrito por uma versão com uma empresa a mais.
  Widget _empresa(TopCompany? company) {
    const estilo = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    if (company == null) return const Text('—', style: estilo);

    final pct = '${company.share.toStringAsFixed(0)}%';
    final empresa = companyFromLabel(company.label);
    if (empresa == null) {
      return Text(
        '${company.label}\n$pct',
        textAlign: TextAlign.center,
        style: estilo,
      );
    }

    return Tooltip(
      message: company.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            label: company.label,
            child: SizedBox(
              width: 20,
              height: 20,
              child: Image.asset(
                companyLogo(empresa),
                fit: BoxFit.contain,
                // Logo ausente não pode apagar a métrica: sem isto a coluna
                // ficaria só com o percentual, sem dizer de quem ele é.
                errorBuilder: (_, _, _) => Icon(
                  Icons.local_shipping_outlined,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(pct, style: estilo),
        ],
      ),
    );
  }

  Widget _smallStatOf(IconData icon, String label, Widget value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          value,
        ],
      ),
    );
  }

  Widget _note(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
    );
  }
}

/// Espaço dos números enquanto o Firestore responde, com a mesma altura do
/// conteúdo final para o dialog não pular de tamanho ao carregar.
class _StatsPlaceholder extends StatelessWidget {
  const _StatsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 144 px é a altura **medida** do bloco carregado (390 dp, Roboto de
      // verdade, perfil completo), e é para isso que esta constante existe: o
      // dialog não pode mudar de tamanho quando o Firestore responde.
      //
      // Quem manda na altura da fileira é a "Mais rodada", com a logo de 20 px
      // no lugar do valor de 12. As três colunas voltaram a ter uma linha cada
      // quando a duração e o ritmo passaram a dividir a mesma — e o efeito
      // colateral bom é que **a carreira sem ritmo mede os mesmos 144**: o
      // documento publicado antes daquele número existir desenha exatamente a
      // mesma altura, e não há caso comum contra caso legado aqui.
      //
      // É a quarta vez que esta constante muda, e por isso ela não é chutada.
      // Os valores medidos que sobram, para quem for mexer: 158 com uma
      // empresa que este app não conhece (volta a ser texto de duas linhas) e
      // 174 na conta sem rota nenhuma, que ganha a linha do convite a
      // cadastrar. Nenhuma constante serve às três — fica com o caso comum.
      height: 144,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}
