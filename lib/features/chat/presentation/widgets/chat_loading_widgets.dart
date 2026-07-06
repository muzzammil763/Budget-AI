import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:budget_ai/app/theme/app_theme.dart';

class ChatShimmerBlock extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ChatShimmerBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<ChatShimmerBlock> createState() => _ChatShimmerBlockState();
}

class _ChatShimmerBlockState extends State<ChatShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.14,
    );
    final highlightColor = theme.colorScheme.surface.withValues(alpha: 0.50);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) {
                final width = bounds.width;
                final slide = width * 2 * _controller.value - width;
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    baseColor,
                    baseColor.withValues(alpha: 0.32),
                    highlightColor,
                    baseColor.withValues(alpha: 0.32),
                    baseColor,
                  ],
                  stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
                  transform: _SlidingGradientTransform(slide),
                ).createShader(bounds);
              },
              child: child,
            );
          },
          child: ColoredBox(color: baseColor),
        ),
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slide;

  const _SlidingGradientTransform(this.slide);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(slide, 0, 0);
  }
}

class ChatLoadingMessage extends StatelessWidget {
  final String iconPath;
  final String message;

  const ChatLoadingMessage({
    super.key,
    required this.iconPath,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: SvgPicture.asset(
              iconPath,
              colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
              width: 16,
              height: 16,
            ),
          ),
          const SizedBox(width: 8),
          const ChatBudgetLoadingIndicator(size: 48),
        ],
      ),
    );
  }
}

class ChatBudgetLoadingIndicator extends StatefulWidget {
  final double size;
  final bool reverse;

  const ChatBudgetLoadingIndicator({
    super.key,
    required this.size,
    this.reverse = false,
  });

  @override
  State<ChatBudgetLoadingIndicator> createState() =>
      _ChatBudgetLoadingIndicatorState();
}

class _ChatBudgetLoadingIndicatorState extends State<ChatBudgetLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    )..repeat(reverse: widget.reverse);
  }

  @override
  void didUpdateWidget(covariant ChatBudgetLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reverse != widget.reverse) {
      _controller.repeat(reverse: widget.reverse);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _BudgetAiLoadingPainter(
              progress: _controller.value,
              primary: theme.colorScheme.primary,
              secondary: theme.colorScheme.tertiary,
              surface: theme.colorScheme.surface,
              outline: theme.colorScheme.outline,
              onSurface: theme.colorScheme.onSurface,
            ),
          );
        },
      ),
    );
  }
}

class _BudgetAiLoadingPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color outline;
  final Color onSurface;

  const _BudgetAiLoadingPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.outline,
    required this.onSurface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = shortest * 0.43;
    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);

    final glowPaint = Paint()
      ..color = primary.withValues(alpha: 0.08 + pulse * 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * (0.95 + pulse * 0.08), glowPaint);

    final basePaint = Paint()
      ..color = surface
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.92, basePaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.055
      ..strokeCap = StrokeCap.round
      ..color = outline.withValues(alpha: 0.20);
    canvas.drawCircle(center, radius * 0.84, ringPaint);

    final activeRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.055
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          primary.withValues(alpha: 0),
          primary,
          secondary,
          primary.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.42, 0.72, 1.0],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.84),
      -math.pi / 2 + progress * math.pi * 2,
      math.pi * 1.35,
      false,
      activeRingPaint,
    );

    final chartBottom = center.dy + radius * 0.34;
    final barWidth = shortest * 0.105;
    final gap = shortest * 0.052;
    final maxHeight = radius * 0.82;
    final barStartX = center.dx - (barWidth * 1.5 + gap);
    final barPaint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < 3; index++) {
      final phase = (progress + index * 0.18) % 1.0;
      final heightFactor =
          0.42 + 0.38 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
      final barHeight = maxHeight * heightFactor;
      final left = barStartX + index * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, chartBottom - barHeight, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      barPaint.color = Color.lerp(
        primary,
        secondary,
        index / 2,
      )!.withValues(alpha: 0.86);
      canvas.drawRRect(rect, barPaint);
    }

    final axisPaint = Paint()
      ..color = onSurface.withValues(alpha: 0.18)
      ..strokeWidth = shortest * 0.025
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - radius * 0.42, chartBottom + shortest * 0.01),
      Offset(center.dx + radius * 0.43, chartBottom + shortest * 0.01),
      axisPaint,
    );

    final coinAngle = -math.pi / 2 + progress * math.pi * 2;
    final coinCenter =
        center +
        Offset(
          math.cos(coinAngle) * radius * 0.84,
          math.sin(coinAngle) * radius * 0.84,
        );
    final coinRadius = shortest * 0.105;
    final coinPaint = Paint()
      ..color = secondary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(coinCenter, coinRadius, coinPaint);

    final coinMarkPaint = Paint()
      ..color = surface.withValues(alpha: 0.94)
      ..strokeWidth = shortest * 0.026
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      coinCenter.translate(0, -coinRadius * 0.45),
      coinCenter.translate(0, coinRadius * 0.45),
      coinMarkPaint,
    );
    canvas.drawLine(
      coinCenter.translate(-coinRadius * 0.30, 0),
      coinCenter.translate(coinRadius * 0.30, 0),
      coinMarkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BudgetAiLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.surface != surface ||
        oldDelegate.outline != outline ||
        oldDelegate.onSurface != onSurface;
  }
}

class ChatInitializingSection extends StatelessWidget {
  const ChatInitializingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ChatShimmerBlock(
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(28),
          ),
          const SizedBox(height: 24),
          ChatShimmerBlock(
            width: 132,
            height: 14,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 12),
          Text(
            'Initializing ...',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
