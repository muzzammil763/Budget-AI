import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key, required this.onPromptTap});

  final ValueChanged<String> onPromptTap;

  static const _prompts = <(IconData, String)>[
    (Icons.pie_chart_outline_rounded, 'Break down my spending by category'),
    (Icons.savings_outlined, 'Help me plan a savings goal'),
    (Icons.trending_down_rounded, 'Where can I cut back this month?'),
    (Icons.calculate_outlined, 'Build me a 50/30/20 budget'),
    (Icons.calendar_month_outlined, 'What bills are coming up soon?'),
    (Icons.shopping_cart_outlined, 'Create a weekly grocery budget'),
    (
      Icons.account_balance_wallet_outlined,
      'How much can I safely spend today?',
    ),
    (Icons.query_stats_rounded, 'Compare this month with last month'),
    (Icons.manage_search_rounded, 'Find unusual transactions'),
    (Icons.credit_score_outlined, 'Make a debt payoff plan'),
  ];

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  double _stagger(double t, double start, double end) {
    return Curves.easeOutCubic.transform(
      ((t - start) / (end - start)).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _EdgeFadeMask(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 112, 12, 112),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1100),
              builder: (context, t, _) {
                final markT = _stagger(t, 0.0, 0.55);
                final headT = _stagger(t, 0.15, 0.6);
                final tagT = _stagger(t, 0.25, 0.7);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: markT,
                      child: CustomPaint(
                        size: const Size(96, 96),
                        painter: _BudgetMarkPainter(
                          progress: t,
                          primary: theme.colorScheme.primary,
                          surface: theme.scaffoldBackgroundColor,
                          accent: AppTheme.highlight,
                          isDark: theme.brightness == Brightness.dark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Opacity(
                      opacity: headT,
                      child: Transform.translate(
                        offset: Offset(0, (1 - headT) * 10),
                        child: Column(
                          children: [
                            Text(
                              _greeting.toUpperCase(),
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.highlight,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Let\'s make your money\nmake sense',
                              textAlign: TextAlign.center,
                              style: AppTheme.headingLarge.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1.22,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _prompts.length; i++)
                      _PromptCard(
                        icon: _prompts[i].$1,
                        label: _prompts[i].$2,
                        reveal: _stagger(t, 0.38 + i * 0.045, 0.72 + i * 0.045),
                        onTap: () => onPromptTap(_prompts[i].$2),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.icon,
    required this.label,
    required this.reveal,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double reveal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, (1 - reveal) * 14),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            borderRadius: BorderRadius.circular(32),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(32),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: onSurface.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 22, color: AppTheme.highlight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: AppTheme.bodyMedium.copyWith(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 15,
                      color: onSurface.withValues(alpha: 0.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeFadeMask extends StatelessWidget {
  const _EdgeFadeMask({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.12, 0.88, 1.0],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

class _BudgetMarkPainter extends CustomPainter {
  const _BudgetMarkPainter({
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
  bool shouldRepaint(covariant _BudgetMarkPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        primary != oldDelegate.primary ||
        surface != oldDelegate.surface ||
        isDark != oldDelegate.isDark;
  }
}
