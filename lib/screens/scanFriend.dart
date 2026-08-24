import 'package:flutter/material.dart';
import 'package:iter/Utils/friendShare.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Lê o QR Code de um colega e devolve o **apelido**.
///
/// Devolve e não convida: quem resolve apelido → perfil → convite é a
/// `AddFriend`, e aquele caminho já existe, já mostra "é essa a pessoa?" antes
/// de qualquer escrita e já sabe distinguir apelido inexistente de falta de
/// rede. Convidar daqui seria uma segunda implementação do mesmo fluxo, com a
/// diferença de mandar convite para quem a pessoa nem viu quem é.
///
/// A tela é fina de propósito: a decisão de o que é um convite mora em
/// [nicknameFromScan], que é função pura e tem teste. Aqui só sobra câmera,
/// que teste de widget não alcança. Ver `docs/specs/amigos.md`.
class ScanFriend extends StatefulWidget {
  const ScanFriend({super.key});

  @override
  State<ScanFriend> createState() => _ScanFriendState();
}

class _ScanFriendState extends State<ScanFriend> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  /// A câmera dispara a detecção **muitas vezes por segundo**, e o mesmo
  /// código volta enquanto continuar enquadrado. Sem esta trava, um único QR
  /// empilharia dezenas de `pop` e derrubaria a tela de baixo junto.
  bool _resolvido = false;

  /// O último código recusado, para a mensagem não piscar a cada quadro.
  String? _recusado;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_resolvido) return;

    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final nickname = nicknameFromScan(raw);
      if (nickname == null) {
        // Recusar é o caso comum: a câmera lê etiqueta de encomenda, QR de
        // Wi-Fi e cartaz de parede. Dizer o que o código **é** evita a
        // conclusão de que o leitor está quebrado.
        if (raw != _recusado && mounted) setState(() => _recusado = raw);
        continue;
      }

      _resolvido = true;
      Navigator.of(context).pop(nickname);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Ler QR Code')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // A mira: sem ela não há onde apontar, e a pessoa aproxima o celular
          // até o QR sair do quadro.
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              _recusado == null
                  ? 'Aponte para o QR Code que o colega abriu no perfil dele.'
                  : 'Esse código não é um convite do iter.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                shadows: [Shadow(blurRadius: 6, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
