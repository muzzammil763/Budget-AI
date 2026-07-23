import 'dart:math' as math;

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:flutter/material.dart';

class UserBubbleStyleSurface extends StatelessWidget {
  const UserBubbleStyleSurface({
    super.key,
    required this.style,
    required this.child,
    this.preview = false,
  });

  final UserBubbleStyle style;
  final Widget child;
  final bool preview;

  static Color foregroundColor(BuildContext context, UserBubbleStyle style) {
    final background = _palette(Theme.of(context), style).background;
    return AppTheme.readableOn(background);
  }

  static TextStyle messageTextStyle(
    BuildContext context,
    UserBubbleStyle style,
  ) {
    return AppTheme.bodyMedium.copyWith(
      color: foregroundColor(context, style),
      fontSize: 16,
      fontFamily: chatFontFamily(style),
    );
  }

  static String? chatFontFamily(UserBubbleStyle style) {
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette(Theme.of(context), style);
    final insets = _contentInsets(style, preview: preview);

    return CustomPaint(
      painter: _UserBubblePainter(style: style, palette: palette),
      child: Padding(padding: insets, child: child),
    );
  }
}

EdgeInsets _contentInsets(UserBubbleStyle style, {required bool preview}) {
  if (preview) {
    return switch (style) {
      UserBubbleStyle.paperCurl => const EdgeInsets.fromLTRB(14, 12, 20, 12),
      UserBubbleStyle.sketchFrame => const EdgeInsets.fromLTRB(18, 12, 18, 12),
      _ => const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    };
  }
  return switch (style) {
    UserBubbleStyle.paperCurl => const EdgeInsets.fromLTRB(18, 17, 24, 17),
    UserBubbleStyle.sketchFrame => const EdgeInsets.fromLTRB(22, 17, 22, 19),
    UserBubbleStyle.vault => const EdgeInsets.fromLTRB(18, 16, 38, 16),
    UserBubbleStyle.cashFlow ||
    UserBubbleStyle.receipt => const EdgeInsets.fromLTRB(18, 16, 18, 21),
    _ => const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  };
}

class _BubblePalette {
  const _BubblePalette(this.background, this.accent, this.detail);

  final Color background;
  final Color accent;
  final Color detail;
}

_BubblePalette _palette(ThemeData theme, UserBubbleStyle style) {
  final dark = theme.brightness == Brightness.dark;
  return switch (style) {
    UserBubbleStyle.classic => _BubblePalette(
      theme.colorScheme.primary,
      theme.colorScheme.primary,
      theme.colorScheme.onPrimary,
    ),
    UserBubbleStyle.ledger => _BubblePalette(
      dark ? const Color(0xFF006B68) : const Color(0xFF087F79),
      const Color(0xFF74E0D1),
      const Color(0xFFFFD166),
    ),
    UserBubbleStyle.savings => _BubblePalette(
      dark ? const Color(0xFF176B4B) : const Color(0xFFDCF7D9),
      dark ? const Color(0xFF7FE0A5) : const Color(0xFF248A58),
      const Color(0xFFFFC857),
    ),
    UserBubbleStyle.cashFlow => _BubblePalette(
      dark ? const Color(0xFF173963) : const Color(0xFF2364AA),
      const Color(0xFF58C7E8),
      const Color(0xFFB8F2E6),
    ),
    UserBubbleStyle.growth => _BubblePalette(
      dark ? const Color(0xFF315B32) : const Color(0xFFE5F4C9),
      dark ? const Color(0xFF9ED67D) : const Color(0xFF4F8F3B),
      const Color(0xFFF3B61F),
    ),
    UserBubbleStyle.receipt => _BubblePalette(
      dark ? const Color(0xFF4A4238) : const Color(0xFFFFF3D6),
      dark ? const Color(0xFFD9C7A4) : const Color(0xFF876D45),
      const Color(0xFFE07A5F),
    ),
    UserBubbleStyle.nightBudget => const _BubblePalette(
      Color(0xFF483D8B),
      Color(0xFFB7A6FF),
      Color(0xFFFFE07A),
    ),
    UserBubbleStyle.vault => _BubblePalette(
      dark ? const Color(0xFF3E4A57) : const Color(0xFF526777),
      const Color(0xFF9FB3C2),
      const Color(0xFFFFC857),
    ),
    UserBubbleStyle.paperCurl => _BubblePalette(
      dark ? const Color(0xFF303236) : const Color(0xFFFDFDFD),
      dark ? const Color(0xFFE8EAED) : const Color(0xFF24262A),
      dark ? const Color(0xFFB9E6D3) : const Color(0xFF537A6B),
    ),
    UserBubbleStyle.sketchFrame => _BubblePalette(
      dark ? const Color(0xFF342E2B) : const Color(0xFFFFFEFC),
      dark ? const Color(0xFFF1E9E4) : const Color(0xFF35231D),
      dark ? const Color(0xFFE5B89D) : const Color(0xFF9A654D),
    ),
  };
}

class _UserBubblePainter extends CustomPainter {
  const _UserBubblePainter({required this.style, required this.palette});

  final UserBubbleStyle style;
  final _BubblePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = palette.background;
    final accent = Paint()
      ..color = palette.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final detail = Paint()..color = palette.detail;
    final bubble = _bubblePath(size);

    canvas.drawPath(bubble, body);
    if (style == UserBubbleStyle.receipt ||
        style == UserBubbleStyle.paperCurl ||
        style == UserBubbleStyle.sketchFrame) {
      canvas.drawPath(bubble, accent);
    }

    switch (style) {
      case UserBubbleStyle.classic:
        break;
      case UserBubbleStyle.ledger:
        _drawLedger(canvas, size, accent, detail);
      case UserBubbleStyle.savings:
        _drawSavings(canvas, size, accent, detail);
      case UserBubbleStyle.cashFlow:
        _drawCashFlow(canvas, size, accent);
      case UserBubbleStyle.growth:
        _drawGrowth(canvas, size, accent, detail);
      case UserBubbleStyle.receipt:
        _drawReceipt(canvas, size, accent, detail);
      case UserBubbleStyle.nightBudget:
        _drawNight(canvas, size, accent, detail);
      case UserBubbleStyle.vault:
        _drawVault(canvas, size, accent, detail);
      case UserBubbleStyle.paperCurl:
      case UserBubbleStyle.sketchFrame:
    }
  }

  Path _bubblePath(Size size) {
    final w = size.width;
    final h = size.height;
    switch (style) {
      case UserBubbleStyle.classic:
        return Path()..addRRect(
          RRect.fromRectAndCorners(
            Offset.zero & size,
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(18),
            bottomLeft: const Radius.circular(18),
            bottomRight: const Radius.circular(4),
          ),
        );
      case UserBubbleStyle.ledger:
        return Path()
          ..moveTo(12, 0)
          ..lineTo(w - 18, 0)
          ..quadraticBezierTo(w, 0, w, 18)
          ..lineTo(w, h - 7)
          ..lineTo(w - 8, h)
          ..lineTo(16, h)
          ..quadraticBezierTo(0, h, 0, h - 16)
          ..lineTo(0, 12)
          ..lineTo(12, 0)
          ..close();
      case UserBubbleStyle.savings:
        return Path()
          ..moveTo(20, 0)
          ..lineTo(w - 28, 0)
          ..quadraticBezierTo(w - 5, 0, w, 20)
          ..quadraticBezierTo(w + 2, h * .55, w - 13, h - 2)
          ..quadraticBezierTo(w * .55, h + 3, 20, h)
          ..quadraticBezierTo(0, h, 0, h - 20)
          ..quadraticBezierTo(-2, 5, 20, 0)
          ..close();
      case UserBubbleStyle.cashFlow:
        return Path()
          ..moveTo(15, 0)
          ..lineTo(w - 18, 0)
          ..quadraticBezierTo(w, 0, w, 18)
          ..lineTo(w, h - 14)
          ..cubicTo(w * .75, h + 3, w * .48, h - 8, w * .25, h - 1)
          ..quadraticBezierTo(0, h + 5, 0, h - 16)
          ..lineTo(0, 15)
          ..quadraticBezierTo(0, 0, 15, 0)
          ..close();
      case UserBubbleStyle.growth:
        return Path()
          ..moveTo(18, 0)
          ..lineTo(w - 24, 0)
          ..quadraticBezierTo(w - 3, 2, w, 20)
          ..lineTo(w, h - 15)
          ..lineTo(w + 7, h - 5)
          ..lineTo(w - 12, h - 9)
          ..quadraticBezierTo(w - 17, h, w - 32, h)
          ..lineTo(18, h)
          ..quadraticBezierTo(0, h, 0, h - 18)
          ..lineTo(0, 18)
          ..quadraticBezierTo(0, 0, 18, 0)
          ..close();
      case UserBubbleStyle.receipt:
        final path = Path()
          ..moveTo(8, 0)
          ..lineTo(w - 8, 0)
          ..quadraticBezierTo(w, 0, w, 8)
          ..lineTo(w, h - 7);
        for (double x = w; x > 7; x -= 9) {
          path
            ..lineTo(math.max(0.0, x - 4.5), h)
            ..lineTo(math.max(0.0, x - 9), h - 7);
        }
        return path
          ..lineTo(0, 8)
          ..quadraticBezierTo(0, 0, 8, 0)
          ..close();
      case UserBubbleStyle.nightBudget:
        return Path()
          ..moveTo(24, 0)
          ..cubicTo(8, -2, 0, 8, 3, 23)
          ..quadraticBezierTo(-4, h * .55, 5, h - 16)
          ..quadraticBezierTo(8, h + 2, 27, h)
          ..lineTo(w - 19, h)
          ..quadraticBezierTo(w + 2, h, w - 1, h - 20)
          ..quadraticBezierTo(w + 4, 5, w - 21, 2)
          ..close();
      case UserBubbleStyle.vault:
        return Path()
          ..moveTo(12, 0)
          ..lineTo(w - 12, 0)
          ..lineTo(w, 12)
          ..lineTo(w, h - 12)
          ..lineTo(w - 12, h)
          ..lineTo(12, h)
          ..lineTo(0, h - 12)
          ..lineTo(0, 12)
          ..close();
      case UserBubbleStyle.paperCurl:
        return Path()
          ..moveTo(9, 5)
          ..quadraticBezierTo(2, 3, 4, 13)
          ..lineTo(1, h - 13)
          ..quadraticBezierTo(0, h - 3, 10, h - 5)
          ..quadraticBezierTo(w * .42, h + 1, w - 14, h - 4)
          ..quadraticBezierTo(w - 3, h, w - 6, h - 13)
          ..lineTo(w - 3, 15)
          ..quadraticBezierTo(w, 5, w - 12, 6)
          ..quadraticBezierTo(w * .56, 1, 9, 5)
          ..close();
      case UserBubbleStyle.sketchFrame:
        return Path()
          ..moveTo(22, 5)
          ..quadraticBezierTo(w * .3, -2, w - 16, 5)
          ..quadraticBezierTo(w, 6, w - 2, 22)
          ..lineTo(w - 3, h - 16)
          ..quadraticBezierTo(w, h - 3, w - 15, h - 5)
          ..quadraticBezierTo(w * .46, h + 2, 18, h - 4)
          ..quadraticBezierTo(3, h - 3, 5, h - 17)
          ..lineTo(3, 22)
          ..quadraticBezierTo(3, 8, 22, 5)
          ..close();
    }
  }

  void _drawLedger(Canvas canvas, Size size, Paint line, Paint detail) {
    canvas.drawLine(Offset(14, 6), Offset(size.width - 18, 6), line);
    canvas.drawLine(
      Offset(size.width - 25, size.height - 7),
      Offset(size.width - 11, size.height - 7),
      line,
    );
    canvas.drawCircle(Offset(size.width - 14, 12), 4, detail);
  }

  void _drawSavings(Canvas canvas, Size size, Paint line, Paint detail) {
    canvas.drawCircle(Offset(14, size.height - 11), 5, detail);
    canvas.drawCircle(Offset(23, size.height - 7), 3.5, detail);
    canvas.save();
    canvas.clipPath(_bubblePath(size));
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size.width, 13), radius: 10),
      0,
      math.pi * 2,
      false,
      line,
    );
    canvas.restore();
  }

  void _drawCashFlow(Canvas canvas, Size size, Paint line) {
    final wave = Path()
      ..moveTo(8, size.height - 10)
      ..cubicTo(
        size.width * .28,
        size.height - 22,
        size.width * .52,
        size.height,
        size.width - 8,
        size.height - 12,
      );
    canvas.drawPath(wave, line);
  }

  void _drawGrowth(Canvas canvas, Size size, Paint line, Paint detail) {
    final origin = Offset(size.width - 17, 18);
    canvas.drawLine(origin, Offset(origin.dx, 7), line);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(origin.dx - 5, 8), width: 9, height: 5),
      line,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(origin.dx + 5, 7), width: 9, height: 5),
      line,
    );
    canvas.drawCircle(Offset(12, size.height - 10), 3, detail);
  }

  void _drawReceipt(Canvas canvas, Size size, Paint line, Paint detail) {
    for (double x = 12; x < size.width - 10; x += 9) {
      canvas.drawCircle(Offset(x, size.height - 5), 1.5, line);
    }
    canvas.drawLine(Offset(12, 7), Offset(28, 7), line);
    canvas.drawCircle(Offset(size.width - 13, 11), 3, detail);
  }

  void _drawNight(Canvas canvas, Size size, Paint line, Paint detail) {
    final moonCenter = Offset(size.width - 17, 14);
    canvas.drawCircle(moonCenter, 7, detail);
    canvas.drawCircle(
      moonCenter.translate(4, -3),
      7,
      Paint()..color = palette.background,
    );
    canvas.drawCircle(Offset(14, 11), 1.7, detail);
    canvas.drawCircle(Offset(23, 7), 1.2, line);
  }

  void _drawVault(Canvas canvas, Size size, Paint line, Paint detail) {
    for (final point in [
      const Offset(12, 11),
      Offset(size.width - 12, 11),
      Offset(12, size.height - 11),
      Offset(size.width - 12, size.height - 11),
    ]) {
      canvas.drawCircle(point, 2.5, detail);
    }
    canvas.drawCircle(Offset(size.width - 18, size.height / 2), 7, line);
    canvas.drawLine(
      Offset(size.width - 18, size.height / 2 - 5),
      Offset(size.width - 18, size.height / 2 + 5),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _UserBubblePainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.palette.background != palette.background ||
      oldDelegate.palette.accent != palette.accent ||
      oldDelegate.palette.detail != palette.detail;
}
