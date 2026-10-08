import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

/// Paints [data] as a QR code, dark modules on a transparent ground. The
/// encoded value is never shown as text or logged.
class QrView extends StatelessWidget {
  const QrView({
    super.key,
    required this.data,
    required this.size,
    this.color = const Color(0xFF000000),
  });

  final String data;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _QrPainter(image, color)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image, this.color);

  final QrImage image;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final cell = size.width / count;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    final path = Path();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (image.isDark(row, col)) {
          // Slight overlap avoids hairline seams between modules.
          path.addRect(
            Rect.fromLTWH(col * cell, row * cell, cell + 0.4, cell + 0.4),
          );
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_QrPainter old) =>
      old.image != image || old.color != color;
}
