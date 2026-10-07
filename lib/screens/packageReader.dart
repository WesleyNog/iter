import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iter/Utils/packageLabel.dart';
import 'package:iter/Utils/packageSession.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/services/textReader.dart';
import 'package:iter/widget/packageCounterBar.dart';
import 'package:iter/widget/packageList.dart';
import 'package:iter/widget/packageReview.dart';
import 'package:iter/widget/scanFrame.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Quantas olhadas um pacote ganha para a leitura completar o que faltou (a
/// letra, o bairro), e por quanto tempo. Depois disso, fecha com o que tem —
/// o "?" e o "Sem bairro" se resolvem na lista ou na revisão, não segurando a
/// fila de pacotes.
const _maxAttempts = 3;
const _retryWindow = Duration(milliseconds: 1500);

/// O quadro vai para um arquivo porque o OCR lê de arquivo; o prefixo é o que
/// deixa apagar sobra de uma sessão que morreu no meio.
const _tempPrefix = 'iter_etiqueta_';

/// O leitor de pacotes: a câmera lê cada etiqueta do Mercado Livre, a barra
/// conta, e ao finalizar devolve a [PackageLoad] conferida — ou nada, se o
/// entregador desistiu.
///
/// **Fina de propósito**, como `ScanFriend`: o que a etiqueta diz é
/// `readLabel`, o que conta é `PackageSession`, e os dois são puros e têm
/// teste. Aqui sobra o que teste de widget não alcança — câmera, OCR, arquivo
/// temporário, vibração. Gravar é de quem abriu a tela. Ver
/// `docs/specs/leitor-de-pacotes.md`.
///
/// A etiqueta tem nome, rua e CEP de terceiros. O quadro existe só pelo tempo
/// do OCR e é apagado num `finally`; nenhum texto lido vai para log —
/// `debugPrint` também imprime em release.
class PackageReader extends StatefulWidget {
  const PackageReader({super.key, required this.route});

  /// A rota agendada que a leitura vai iniciar. Daqui só sai `adress`, para a
  /// revisão dizer o que a leitura substitui.
  final NewRouteModal route;

  @override
  State<PackageReader> createState() => _PackageReaderState();
}

class _PackageReaderState extends State<PackageReader>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    // O quadro vem junto com o QR: é nele que o OCR lê bairro e letra, e é
    // no mesmo espaço dele que o plugin dá os cantos do QR — nas duas
    // plataformas o JPEG devolvido é a imagem já em pé sobre a qual os cantos
    // foram calculados.
    returnImage: true,
    detectionSpeed: DetectionSpeed.normal,
    // Com `returnImage`, cada quadro com QR vira um JPEG. 300 ms limita isso
    // a ~3 por segundo, que é mais do que alguém troca de pacote.
    detectionTimeoutMs: 300,
    // A documentação diz que o Android cai em 640×480 sem isto, e o código
    // usa 1920×1080. Endereço em letra miúda precisa dos pixels: declarado,
    // para não depender de qual dos dois está certo.
    cameraResolution: const Size(1920, 1080),
  );

  final _session = PackageSession();

  final _attempts = <String, _Attempts>{};

  /// Tirados da carga pela lista. Não voltam sozinhos: a etiqueta da agência
  /// fechada continua na frente da câmera logo depois de ser tirada.
  final _removed = <String>{};

  /// O OCR em andamento — um por vez.
  Future<void>? _inFlight;

  /// Lista ou revisão por cima: a câmera não conta nada por baixo.
  bool _sheetOpen = false;

  /// A revisão desligou a câmera; voltar do segundo plano não pode religar.
  bool _reviewing = false;

  /// O último pacote visto, para o cartão do topo.
  _Flash? _flash;

  /// O último QR recusado, para a mensagem não piscar a cada quadro.
  String? _rejected;

  /// O ✓ ou ✗ do meio da tela, e o número que o faz aparecer de novo.
  ScanMarkKind? _mark;
  int _markSerial = 0;

  // Só em debug: o que o OCR e o QR viram, desenhado sobre a câmera.
  bool _debug = false;
  _DebugFrame? _debugFrame;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _purgeTempFiles();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    _purgeTempFiles();
    super.dispose();
  }

  /// O controller é nosso (a lanterna precisa dele), então pausar e retomar
  /// com o app é nosso também — e o `MobileScanner` vai com
  /// `useAppLifecycleState: false`, para não haver duas mãos no mesmo botão.
  ///
  /// É o caso comum no CD: abrir o app do Mercado Livre para comparar a
  /// contagem e voltar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (!_reviewing) unawaited(_controller.start());
      case AppLifecycleState.inactive:
        unawaited(_controller.stop());
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
    }
  }

  // -------------------------------------------------------------------------
  // Leitura

  void _onDetect(BarcodeCapture capture) {
    if (_sheetOpen || _inFlight != null) return;

    String? repeated;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final id = shipmentIdFromQr(raw);
      if (id == null) {
        if (raw != _rejected) setState(() => _rejected = raw);
        continue;
      }

      if (_removed.contains(id)) {
        _show(_Flash(id, _FlashKind.removed));
        return;
      }

      final entry = _session[id];
      if (entry != null && !_wantsAnotherLook(id, entry)) {
        repeated ??= id;
        continue;
      }

      final image = capture.image;
      if (image == null) {
        // Não acontece com `returnImage`; se acontecer, o QR basta para
        // contar, e a letra fica "?".
        _record(LabelRead(shipmentId: id));
        return;
      }

      _inFlight = _read(
        id,
        barcode.corners,
        capture.size,
        image,
      ).whenComplete(() => _inFlight = null);
      return;
    }

    if (repeated != null) _show(_Flash(repeated, _FlashKind.repeated));
  }

  /// Faltou letra ou bairro, e a janela de novas olhadas ainda está aberta.
  bool _wantsAnotherLook(String id, PackageEntry entry) {
    if (entry.type != null && entry.bairro != null) return false;

    final attempts = _attempts[id];
    if (attempts == null) return false;
    return attempts.count < _maxAttempts &&
        DateTime.now().difference(attempts.first) < _retryWindow;
  }

  Future<void> _read(
    String id,
    List<Offset> corners,
    Size frameSize,
    Uint8List jpeg,
  ) async {
    var read = LabelRead(shipmentId: id);
    final watch = Stopwatch()..start();
    final file = File(
      '${Directory.systemTemp.path}/$_tempPrefix'
      '${DateTime.now().microsecondsSinceEpoch}.jpg',
    );

    try {
      await file.writeAsBytes(jpeg, flush: true);
      final lines = await TextReader.read(file.path);
      read = readLabel(shipmentId: id, qrCorners: corners, lines: lines);
      var fromStripe = false;
      if (read.type == null) {
        read = read.withType(await _lookAtStripe(file.path, corners));
        fromStripe = read.type != null;
      }
      if (_debug) _debugFrame = _DebugFrame(frameSize, corners, lines);
      // Em debug, o que a leitura conseguiu — sim ou não, e o tempo. Nenhum
      // texto e nenhum número de envio: é o que mede, no aparelho, o
      // critério de 1 s e as taxas de letra e bairro, sem pôr o endereço de
      // ninguém no log.
      if (kDebugMode) {
        debugPrint(
          'Leitura: ${_summary(read, lines, watch)}'
          '${fromStripe ? ' (letra da tarja)' : ''}',
        );
        debugPrint(
          'Diagnóstico: quadro ${frameSize.width.round()}x'
          '${frameSize.height.round()}; '
          '${labelDiagnostics(qrCorners: corners, lines: lines)}',
        );
      }
    } catch (e) {
      // OCR falhou neste quadro: o pacote conta pelo QR, e a próxima olhada
      // tenta de novo. Em debug, só o **código** do erro — a mensagem de um
      // motor de OCR pode carregar o texto da etiqueta. É o que diz, no
      // primeiro teste no aparelho, se o canal nativo nem foi registrado.
      if (kDebugMode) {
        debugPrint(
          'OCR falhou: ${e is PlatformException ? e.code : e.runtimeType}',
        );
      }
    } finally {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }

    if (mounted) _record(read);
  }

  /// A segunda olhada: só a tarja abaixo do QR, recortada e ampliada.
  ///
  /// Na imagem inteira a letra tem ~12 px e o OCR nem a devolve — medido no
  /// aparelho. Invertida primeiro, porque a tarja é branco sobre preto; sem
  /// inverter só se a primeira não achar nada. São no máximo duas leituras de
  /// uma imagem pequena, e só quando a letra faltou.
  Future<PackageType?> _lookAtStripe(String path, List<Offset> corners) async {
    final window = letterWindow(corners);
    if (window == null) return null;

    for (final invert in const [true, false]) {
      final letter = letterIn(
        await TextReader.readRegion(path, window, invert: invert),
      );
      if (letter != null) return letter;
    }
    return null;
  }

  void _record(LabelRead read) {
    final id = read.shipmentId;
    final before = _session[id]?.type;
    final outcome = _session.add(read);
    _attempts.putIfAbsent(id, () => _Attempts(DateTime.now())).count++;

    // Uma olhada a mais que não trouxe nada novo: o pacote continua na mão,
    // o cartão continua o mesmo.
    if (outcome == ReadOutcome.repeated) return;

    final entry = _session[id]!;
    _vibrate(
      outcome,
      becameAgency: entry.type == PackageType.agencia && before == null,
    );
    setState(() {
      _rejected = null;
      _flash = _Flash(id, _FlashKind.read);
      // O ✓ só no pacote **novo**: a letra que chega numa segunda olhada é o
      // mesmo pacote, e um segundo ✓ diria que contou duas vezes.
      if (outcome == ReadOutcome.added) {
        _mark = ScanMarkKind.counted;
        _markSerial++;
      }
    });
  }

  /// O A vibra forte, duas vezes: é o pacote que pode sair da rota, e o
  /// momento de olhar se a agência está aberta é este, com ele na mão.
  void _vibrate(ReadOutcome outcome, {required bool becameAgency}) {
    if (becameAgency) {
      HapticFeedback.heavyImpact();
      Future.delayed(
        const Duration(milliseconds: 160),
        HapticFeedback.heavyImpact,
      );
    } else if (outcome == ReadOutcome.added) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// Troca o cartão sem piscar: o mesmo pacote continua enquadrado por vários
  /// quadros, e só um pacote **diferente** muda o que está escrito.
  ///
  /// Também apaga o "não é uma etiqueta": quem acabou de apontar para uma
  /// etiqueta de verdade, mesmo já lida, não está mais olhando para o código
  /// recusado.
  void _show(_Flash flash) {
    if (_flash?.shipmentId == flash.shipmentId && _rejected == null) return;
    setState(() {
      // O ✗ só quando o pacote **muda**: o mesmo continua enquadrado por
      // vários quadros, e piscar ✗ sobre o ✓ que acabou de aparecer diria o
      // contrário do que aconteceu.
      if (_flash?.shipmentId != flash.shipmentId &&
          flash.kind != _FlashKind.read) {
        _mark = ScanMarkKind.notCounted;
        _markSerial++;
      }
      _flash = flash;
      _rejected = null;
    });
  }

  // -------------------------------------------------------------------------
  // Correções

  void _setType(String id, PackageType type) =>
      setState(() => _session.setType(id, type));

  void _remove(String id) => setState(() {
    _session.remove(id);
    _attempts.remove(id);
    _removed.add(id);
    if (_flash?.shipmentId == id) _flash = null;
  });

  void _countAgain(String id) => setState(() {
    _removed.remove(id);
    _flash = null;
  });

  // -------------------------------------------------------------------------
  // Folhas

  Future<void> _openList(PackageListFilter filter) async {
    setState(() => _sheetOpen = true);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.of(sheet).size.height * 0.75,
        child: PackageList(
          session: _session,
          initialFilter: filter,
          onRemove: _remove,
          onSetType: _setType,
        ),
      ),
    );

    if (mounted) setState(() => _sheetOpen = false);
  }

  Future<void> _openReview() async {
    setState(() => _sheetOpen = true);
    // A leitura que estava no meio entra antes da conferência; senão o
    // pacote contaria na sessão e não no número que o entregador confirmou.
    await _inFlight;
    if (!mounted) return;

    _reviewing = true;
    unawaited(_controller.stop());

    final load = await showModalBottomSheet<PackageLoad>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        final media = MediaQuery.of(sheet);
        final keyboard = media.viewInsets.bottom;
        // A altura desconta o teclado: corrigir Pacotes abre o teclado, e
        // 85% da tela mais o teclado embaixo passaria da tela.
        final height = media.size.height * 0.85 - keyboard;

        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: height < 240 ? 240 : height,
            child: PackageReview(
              session: _session,
              previousBairros: widget.route.adress ?? const [],
              onSave: (load) => Navigator.of(sheet).pop(load),
              onBack: () => Navigator.of(sheet).pop(),
            ),
          ),
        );
      },
    );
    if (!mounted) return;

    if (load != null) {
      Navigator.of(context).pop(load);
      return;
    }

    _reviewing = false;
    unawaited(_controller.start());
    setState(() => _sheetOpen = false);
  }

  Future<void> _confirmDiscard() async {
    final total = _session.total;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          total == 1
              ? 'Descartar 1 pacote lido?'
              : 'Descartar $total pacotes lidos?',
        ),
        content: const Text(
          'A leitura não foi salva. A rota continua agendada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Continuar lendo'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------------
  // Tela

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // `Navigator.pop` direto (salvar, descartar) não passa por aqui; só o
      // gesto de voltar e a seta da AppBar.
      canPop: _session.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Ler pacotes'),
          actions: [
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) => IconButton(
                tooltip: 'Lanterna',
                onPressed: _controller.toggleTorch,
                icon: Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                ),
              ),
            ),
            if (kDebugMode)
              IconButton(
                tooltip: 'Depurar leitura',
                onPressed: () => setState(() => _debug = !_debug),
                icon: Icon(
                  _debug ? Icons.bug_report : Icons.bug_report_outlined,
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                useAppLifecycleState: false,
              ),
            ),
            if (_debug && _debugFrame != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _DebugPainter(_debugFrame!)),
                ),
              ),
            // A janela tem o formato da metade de baixo da etiqueta: o OCR
            // precisa do endereço **e** do QR no mesmo quadro.
            const Positioned.fill(child: ScanFrame(window: Size(300, 260))),
            if (_mark != null)
              Center(
                child: ScanMark(kind: _mark!, serial: _markSerial),
              ),
            Positioned(top: 12, left: 12, right: 12, child: _flashCard()),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12 + MediaQuery.of(context).padding.bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_rejected != null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Esse código não é uma etiqueta do Mercado Livre.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 6)],
                        ),
                      ),
                    ),
                  PackageCounterBar(
                    session: _session,
                    onOpenList: _openList,
                    onFinish: _openReview,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flashCard() {
    final flash = _flash;
    if (flash == null) {
      return _card(
        color: Colors.black.withValues(alpha: 0.7),
        child: const Text(
          'Enquadre o endereço e o QR da etiqueta.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    if (flash.kind == _FlashKind.removed) {
      return _card(
        color: Colors.blueGrey.shade700,
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Este pacote foi tirado da carga.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () => _countAgain(flash.shipmentId),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Contar de novo'),
            ),
          ],
        ),
      );
    }

    final entry = _session[flash.shipmentId];
    if (entry == null) return const SizedBox.shrink();

    final type = entry.type;
    final bairro = entry.bairro ?? 'Sem bairro';
    final repeated = flash.kind == _FlashKind.repeated;

    final Color color;
    final String title;
    if (repeated) {
      color = Colors.grey.shade800;
      title = 'Já lido · $bairro';
    } else if (type == PackageType.agencia) {
      // Por extenso e em caixa alta: é a leitura que pede ação.
      color = Colors.deepOrange.shade600;
      title = 'AGÊNCIA · $bairro';
    } else if (type == PackageType.comercial) {
      color = Colors.amber.shade800;
      title = 'Comercial · $bairro';
    } else if (type == PackageType.residencial) {
      color = Colors.green.shade700;
      title = 'Residencial · $bairro';
    } else {
      color = Colors.grey.shade700;
      title = 'Sem letra · $bairro';
    }

    return _card(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PackageTypeBadge(type: type),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          // A letra não veio: o pacote já conta, e o entregador responde com
          // ele na mão. Ler o próximo sem responder deixa este como "?".
          if (type == null && !repeated) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final option in PackageType.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilledButton(
                        key: ValueKey('escolher-${packageTypeLetter(option)}'),
                        onPressed: () => _setType(entry.shipmentId, option),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        child: Text(packageTypeLetter(option)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Color color, required Widget child}) => Material(
    color: color,
    borderRadius: BorderRadius.circular(16),
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );
}

String _summary(LabelRead read, List<OcrLine> lines, Stopwatch watch) {
  final bairro = read.bairro != null
      ? 'sim'
      : read.rawBairro != null
      ? 'fora da lista'
      : 'não';
  return '${watch.elapsedMilliseconds} ms, ${lines.length} linhas, '
      'letra ${read.type == null ? 'não' : packageTypeLetter(read.type!)}, '
      'bairro $bairro, parada ${read.stopKey == null ? 'não' : 'sim'}';
}

/// Apaga quadros que sobraram — de uma sessão que o sistema matou no meio do
/// OCR, por exemplo. Roda ao abrir e ao fechar a tela.
void _purgeTempFiles() {
  try {
    for (final entity in Directory.systemTemp.listSync()) {
      final name = entity.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
        orElse: () => '',
      );
      if (entity is File && name.startsWith(_tempPrefix)) {
        entity.deleteSync();
      }
    }
  } catch (_) {}
}

class _Attempts {
  _Attempts(this.first);

  final DateTime first;
  int count = 0;
}

enum _FlashKind { read, repeated, removed }

class _Flash {
  const _Flash(this.shipmentId, this.kind);

  final String shipmentId;
  final _FlashKind kind;
}

class _DebugFrame {
  const _DebugFrame(this.size, this.corners, this.lines);

  final Size size;
  final List<Offset> corners;
  final List<OcrLine> lines;
}

/// Desenha os cantos do QR (verde) e as caixas do OCR (amarelo) sobre a
/// câmera. É o teste de que os dois estão no mesmo espaço de coordenadas: se
/// a tarja da letra não cair dentro de uma caixa amarela logo abaixo do verde,
/// a janela da letra está no lugar errado. Só existe em debug, e não escreve
/// texto nenhum — só retângulos.
class _DebugPainter extends CustomPainter {
  const _DebugPainter(this.frame);

  final _DebugFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.size.isEmpty) return;

    // O `MobileScanner` desenha a câmera com `BoxFit.cover`.
    final scale = [
      size.width / frame.size.width,
      size.height / frame.size.height,
    ].reduce((a, b) => a > b ? a : b);
    final dx = (size.width - frame.size.width * scale) / 2;
    final dy = (size.height - frame.size.height * scale) / 2;
    Offset map(Offset point) =>
        Offset(point.dx * scale + dx, point.dy * scale + dy);

    final ocr = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final line in frame.lines) {
      canvas.drawRect(
        Rect.fromPoints(map(line.box.topLeft), map(line.box.bottomRight)),
        ocr,
      );
    }

    if (frame.corners.length >= 3) {
      final qr = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawPath(
        Path()..addPolygon(frame.corners.map(map).toList(), true),
        qr,
      );
    }
  }

  @override
  bool shouldRepaint(_DebugPainter old) => old.frame != frame;
}
