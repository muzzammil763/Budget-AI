import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';

/// A compact, fully revealed version of the Budget AI brand mark for controls
/// such as app-bar actions.
class BudgetMarkIcon extends StatelessWidget {
  const BudgetMarkIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: BudgetMarkPainter(
          progress: 1,
          primary: theme.colorScheme.primary,
          surface: theme.colorScheme.surface,
          accent: AppTheme.highlight,
          isDark: theme.brightness == Brightness.dark,
        ),
      ),
    );
  }
}

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
          barsLeft + 2 * (barWidth + gap) + barWidth / 2 + 1,
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

/// Transaction list with incoming and outgoing arrows for Finances.
class FinanceMarkIcon extends StatelessWidget {
  const FinanceMarkIcon({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FinanceMarkPainter(Theme.of(context).colorScheme),
  );
}

class _FinanceMarkPainter extends CustomPainter {
  const _FinanceMarkPainter(this.colors);
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    final card = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 2, 22, 24),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      card,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(3, 2),
          const Offset(25, 26),
          [
            colors.primary,
            Color.lerp(colors.primary, AppTheme.highlight, .25)!,
          ],
        ),
    );
    final ink = Paint()
      ..color = colors.onPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Two ledger rows with opposite directions: money in and money out.
    canvas.drawPath(
      Path()
        ..moveTo(9, 6)
        ..lineTo(9, 12)
        ..moveTo(6.5, 9.5)
        ..lineTo(9, 12)
        ..lineTo(11.5, 9.5),
      ink,
    );
    canvas.drawLine(const Offset(15, 9), const Offset(21, 9), ink);
    canvas.drawPath(
      Path()
        ..moveTo(9, 22)
        ..lineTo(9, 16)
        ..moveTo(6.5, 18.5)
        ..lineTo(9, 16)
        ..lineTo(11.5, 18.5),
      ink,
    );
    canvas.drawLine(const Offset(15, 19), const Offset(21, 19), ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FinanceMarkPainter oldDelegate) =>
      colors != oldDelegate.colors;
}
