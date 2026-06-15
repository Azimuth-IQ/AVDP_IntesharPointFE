import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';

/// The Inteshar Store mark — an angular five-point sparkle with a slight
/// rightward lean that reads as motion ("launch", "go").
///
/// Default rendering is a thick ink-black outline; pass [filled] to render
/// a solid mark, or override [color] for tinted variants on yellow surfaces.
class IntesharStar extends StatelessWidget {
  final double size;
  final Color? color;
  final bool filled;

  /// Tilt in radians, applied as a slight forward lean.
  final double tilt;

  const IntesharStar({
    super.key,
    this.size = 36,
    this.color,
    this.filled = false,
    this.tilt = -0.18,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? IntesharColors.ink;
    return SizedBox(
      width: size,
      height: size,
      child: Transform.rotate(
        angle: tilt,
        child: CustomPaint(
          painter: _StarPainter(color: c, filled: filled),
        ),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  final Color color;
  final bool filled;

  _StarPainter({required this.color, required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final outer = math.min(w, h) / 2 * 0.96;
    // Inner radius tightened so the star feels angular/spiky, not chubby.
    final inner = outer * 0.38;

    final path = Path();
    const points = 5;
    // Start at the top point (rotate -90° so first vertex is up).
    for (int i = 0; i < points * 2; i++) {
      final r = (i.isEven) ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / points;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    if (filled) {
      final fill = Paint()..color = color;
      canvas.drawPath(path, fill);
    }

    // Stroke is the dominant rendering — matches the brand mark's outline weight.
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, outer * 0.18)
      ..strokeJoin = StrokeJoin.miter
      ..strokeMiterLimit = 3
      ..strokeCap = StrokeCap.butt;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) =>
      old.color != color || old.filled != filled;
}
