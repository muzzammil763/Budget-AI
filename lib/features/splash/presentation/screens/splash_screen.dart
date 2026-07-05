import 'dart:math' as math;

import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _showApp = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    Future<void>.delayed(const Duration(milliseconds: 1250), () {
      if (mounted) setState(() => _showApp = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showApp
          ? widget.child
          : Scaffold(
              key: const ValueKey('budget_ai_splash'),
              body: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _BudgetSplashPainter(
                      progress: Curves.easeOutCubic.transform(
                        _controller.value,
                      ),
                      primary: theme.colorScheme.primary,
                      surface: theme.scaffoldBackgroundColor,
                      onSurface: theme.colorScheme.onSurface,
                    ),
                    child: Center(
                      child: Transform.scale(
                        scale: 0.96 + (_controller.value * 0.04),
                        child: Opacity(
                          opacity: (_controller.value * 1.4).clamp(0, 1),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 82,
                                height: 82,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.14),
                                      blurRadius: 34,
                                      offset: const Offset(0, 18),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: theme.colorScheme.primary,
                                  size: 38,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Budget AI',
                                style: AppTheme.headingSmall.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Money, memory, momentum',
                                style: AppTheme.bodySmall.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _BudgetSplashPainter extends CustomPainter {
  const _BudgetSplashPainter({
    required this.progress,
    required this.primary,
    required this.surface,
    required this.onSurface,
  });

  final double progress;
  final Color primary;
  final Color surface;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(surface, BlendMode.src);

    final center = Offset(size.width / 2, size.height / 2);
    final shortest = math.min(size.width, size.height);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final radius = shortest * (0.22 + (i * 0.075));
      final alpha = (0.12 - (i * 0.025)) * progress;
      ringPaint.color = primary.withValues(alpha: alpha);
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2 + (i * 0.45),
        (math.pi * 1.25) * progress,
        false,
        ringPaint,
      );
    }

    final dotPaint = Paint()..color = primary.withValues(alpha: 0.18);
    for (var i = 0; i < 10; i++) {
      final angle = (math.pi * 2 / 10) * i + (progress * 0.5);
      final radius = shortest * 0.34;
      final offset = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawCircle(offset, 2.2 + (1.8 * progress), dotPaint);
    }

    final baseLinePaint = Paint()
      ..color = onSurface.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final y = center.dy + shortest * 0.22;
    canvas.drawLine(
      Offset(size.width * 0.22, y),
      Offset(size.width * (0.22 + (0.56 * progress)), y),
      baseLinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BudgetSplashPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        primary != oldDelegate.primary ||
        surface != oldDelegate.surface ||
        onSurface != oldDelegate.onSurface;
  }
}
