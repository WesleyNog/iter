import 'package:delightful_toast/delight_toast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

showNotification({
  required BuildContext context,
  required String type,
  required String msg,
  String? learnMoreText,
  VoidCallback? onLearnMoreTap,
}) {
  Color primaryColor;
  Color secondaryColor;
  IconData iconData;

  switch (type) {
    case "success":
      primaryColor = const Color(0xFF10B981); // Green moderno
      secondaryColor = const Color(0xFF059669);
      iconData = Icons.check_circle_rounded;
      break;
    case "alert":
      primaryColor = const Color(0xFFF59E0B); // Amber moderno
      secondaryColor = const Color(0xFFD97706);
      iconData = Icons.warning_amber_rounded;
      break;
    case "error":
      primaryColor = const Color(0xFFEF4444); // Red moderno
      secondaryColor = const Color(0xFFDC2626);
      iconData = Icons.error_rounded;
      break;
    default:
      primaryColor = const Color(0xFF3B82F6); // Blue moderno
      secondaryColor = const Color(0xFF2563EB);
      iconData = Icons.info_rounded;
  }

  List<InlineSpan> textSpans = [
    TextSpan(
      text: msg,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 15,
        color: Colors.white,
        letterSpacing: 0.3,
        height: 1.4,
      ),
    ),
  ];

  if (learnMoreText != null && onLearnMoreTap != null) {
    textSpans.add(const TextSpan(text: '\n'));
    textSpans.add(
      TextSpan(
        text: learnMoreText,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Color(0xFF93C5FD),
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF93C5FD),
          decorationThickness: 2,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            try {
              DelightToastBar.removeAll();
              onLearnMoreTap();
            } catch (e) {
              onLearnMoreTap();
            }
          },
      ),
    );
  }

  if (!context.mounted) return;

  try {
    return DelightToastBar(
      autoDismiss: true,
      snackbarDuration: Duration(seconds: learnMoreText != null ? 5 : 3),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryColor, secondaryColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ícone com fundo circular
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            // Texto
            Expanded(
              child: RichText(
                text: TextSpan(children: textSpans),
                overflow: TextOverflow.visible,
              ),
            ),
            // Indicador visual decorativo
            Container(
              width: 4,
              height: 40,
              margin: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    ).show(context);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: Duration(seconds: learnMoreText != null ? 5 : 3),
        ),
      );
    }
  }
}
