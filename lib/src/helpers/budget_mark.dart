import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The animated Budget AI brand mark (gradient card, growing bars, coin and
/// spark) shared by the chat empty state and onboarding.
class BudgetMarkPainter extends CustomPainter {
  const BudgetMarkPainter({
    required this.progress,
    required this.primary,
    required this.surface,
    required this.accent,
    required this.isDark,
  });

  final double progress;
  final Color primary;
  final Color surface;
  final Color accent;
  final bool isDark;

  double _stagger(double start, double end, Curve curve) {
    return curve.transform(
      ((progress - start) / (end - start)).clamp(0.0, 1.0),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final cardSize = size.shortestSide * 0.78;
    final entry = _stagger(0.0, 0.5, Curves.easeOutBack);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(0.85 + 0.15 * entry);
    canvas.translate(-center.dx, -center.dy);

    final ringT = _stagger(0.3, 0.8, Curves.easeOut);
    if (ringT > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: size.shortestSide * 0.485),
        -math.pi / 2,
        math.pi * 1.5 * ringT,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.sweep(
            center,
            [accent.withValues(alpha: 0), accent.withValues(alpha: 0.65)],
            [0.0, 0.75],
            TileMode.clamp,
            -math.pi / 2,
            math.pi,
          ),
      );
    }

    final rect = Rect.fromCenter(
      center: center,
      width: cardSize,
      height: cardSize,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(cardSize * 0.30),
    );

    if (isDark) {
      canvas.drawRRect(
        rrect.inflate(1.5),
        Paint()
          ..color = accent.withValues(alpha: 0.14 * entry)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    } else {
      canvas.drawShadow(
        Path()..addRRect(rrect),
        Colors.black.withValues(alpha: entry),
        10,
        true,
      );
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          primary,
          Color.lerp(primary, accent, 0.28)!,
        ]),
    );

    final barWidth = cardSize * 0.13;
    final gap = cardSize * 0.075;
    final baseline = rect.bottom - cardSize * 0.22;
    final maxHeights = [cardSize * 0.24, cardSize * 0.38, cardSize * 0.52];
    final barsLeft = center.dx - (barWidth * 3 + gap * 2) / 2;
    final barPaint = Paint()..color = surface;

    for (var i = 0; i < 3; i++) {
      final growth = _stagger(
        0.25 + i * 0.12,
        0.7 + i * 0.12,
        Curves.elasticOut,
      );
      final height = maxHeights[i] * growth;
      if (height <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            barsLeft + i * (barWidth + gap),
            baseline - height,
            barWidth,
            height,
          ),
          Radius.circular(barWidth / 2),
        ),
        barPaint,
      );
    }

    final coinT = _stagger(0.65, 1.0, Curves.easeOutBack);
    if (coinT > 0) {
      canvas.drawCircle(
        Offset(
          barsLeft + 2 * (barWidth + gap) + barWidth / 2,
          baseline - maxHeights[2] - cardSize * 0.115,
        ),
        cardSize * 0.052 * coinT,
        Paint()..color = accent,
      );
    }

    final sparkT = _stagger(0.75, 1.0, Curves.easeOutBack);
    if (sparkT > 0) {
      canvas.save();
      canvas.translate(
        rect.right + cardSize * 0.05,
        rect.top - cardSize * 0.05,
      );
      canvas.rotate(0.3);
      canvas.drawPath(
        _sparkPath(cardSize * 0.11 * sparkT),
        Paint()..color = accent,
      );
      canvas.restore();
    }

    canvas.restore();
  }

  Path _sparkPath(double r) {
    const pinch = 0.22;
    return Path()
      ..moveTo(0, -r)
      ..quadraticBezierTo(r * pinch, -r * pinch, r, 0)
      ..quadraticBezierTo(r * pinch, r * pinch, 0, r)
      ..quadraticBezierTo(-r * pinch, r * pinch, -r, 0)
      ..quadraticBezierTo(-r * pinch, -r * pinch, 0, -r)
      ..close();
  }

  @override
  bool shouldRepaint(covariant BudgetMarkPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        primary != oldDelegate.primary ||
        surface != oldDelegate.surface ||
        isDark != oldDelegate.isDark;
  }
}
