import 'dart:ui';

import 'package:flutter/material.dart';

/// A janela de leitura por cima da câmera: fora dela fosco e escuro, dentro
/// nítido, com a borda.
///
/// Só **guia**. O QR é detectado no quadro inteiro e o OCR lê o quadro inteiro
/// — o endereço às vezes passa da borda, e recortar a leitura pela janela
/// perderia o bairro. O que a máscara faz é dizer onde pôr a etiqueta, que é o
/// que os leitores de código que o entregador já usa fazem.
class ScanFrame extends StatelessWidget {
  const ScanFrame({super.key, required this.window});

  /// O tamanho da janela, sempre centrada.
  final Size window;

  static const radius = Radius.circular(18);

  /// Onde a janela fica numa área de [area].
  static Rect windowIn(Size area, Size window) => Rect.fromCenter(
    center: area.center(Offset.zero),
    width: window.width,
    height: window.height,
  );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hole = RRect.fromRectAndRadius(
            windowIn(constraints.biggest, window),
            radius,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // O desfoque é recortado para **fora** da janela: o
              // `BackdropFilter` respeita o `ClipPath` acima dele. Sigma baixo
              // de propósito — ele repinta a cada quadro da câmera.
              ClipPath(
                clipper: OutsideWindowClipper(hole),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
              CustomPaint(painter: _BorderPainter(hole)),
            ],
          );
        },
      ),
    );
  }
}

/// A tela inteira menos a janela: `evenOdd` faz do retângulo de dentro um
/// furo.
class OutsideWindowClipper extends CustomClipper<Path> {
  const OutsideWindowClipper(this.hole);

  final RRect hole;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addRRect(hole);

  @override
  bool shouldReclip(OutsideWindowClipper oldClipper) => oldClipper.hole != hole;
}

class _BorderPainter extends CustomPainter {
  const _BorderPainter(this.hole);

  final RRect hole;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      hole,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_BorderPainter oldDelegate) => oldDelegate.hole != hole;
}

/// O que o sinal no meio da tela diz.
enum ScanMarkKind {
  /// Pacote novo, contado: ✓ verde.
  counted,

  /// Lido, mas não contado — já estava na carga, ou foi tirado dela: ✗.
  notCounted,
}

/// O sinal no meio da tela a cada leitura, que aparece e some sozinho.
///
/// [serial] é o que faz ele aparecer **de novo**: o ✓ do pacote seguinte é o
/// mesmo ✓ com outro serial, e a chave nova reinicia a animação. Sem isso, dois
/// pacotes novos seguidos mostrariam um sinal só.
class ScanMark extends StatelessWidget {
  const ScanMark({super.key, required this.kind, required this.serial});

  final ScanMarkKind kind;
  final int serial;

  /// Curto o bastante para não cobrir a próxima etiqueta, longo o bastante para
  /// o olho pegar de relance.
  static const duration = Duration(milliseconds: 900);

  @override
  Widget build(BuildContext context) {
    final counted = kind == ScanMarkKind.counted;
    final color = counted ? Colors.green.shade600 : Colors.red.shade600;

    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(serial),
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        builder: (context, t, child) {
          // Entra rápido, fica, e sai no último terço.
          final opacity = t < 0.15
              ? t / 0.15
              : t > 0.7
              ? (1 - t) / 0.3
              : 1.0;
          final grow = Curves.easeOutBack.transform((t / 0.3).clamp(0.0, 1.0));
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.7 + 0.3 * grow, child: child),
          );
        },
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.9),
          ),
          child: Icon(
            counted ? Icons.check_rounded : Icons.close_rounded,
            key: ValueKey(counted ? 'marca-contou' : 'marca-nao-contou'),
            color: Colors.white,
            size: 76,
          ),
        ),
      ),
    );
  }
}
