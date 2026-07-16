import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:flutter/material.dart';

class ChatShimmerBlock extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final bool reverse;

  const ChatShimmerBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.reverse = false,
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
    )..repeat(reverse: widget.reverse);
  }

  @override
  void didUpdateWidget(covariant ChatShimmerBlock oldWidget) {
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

class ChatShimmerText extends StatefulWidget {
  const ChatShimmerText({
    super.key,
    required this.text,
    required this.style,
    this.reverse = true,
  });

  final String text;
  final TextStyle style;
  final bool reverse;

  @override
  State<ChatShimmerText> createState() => _ChatShimmerTextState();
}

class _ChatShimmerTextState extends State<ChatShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: widget.reverse);
  }

  @override
  void didUpdateWidget(covariant ChatShimmerText oldWidget) {
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final progress = Curves.easeInOutCubic.transform(_controller.value);
            final bandRadius = math.max(28.0, bounds.width * 0.18);
            final centerX =
                -bandRadius + ((bounds.width + bandRadius * 2) * progress);
            return ui.Gradient.linear(
              Offset(centerX - bandRadius, bounds.center.dy),
              Offset(centerX + bandRadius, bounds.center.dy),
              [
                onSurface.withValues(alpha: 0.42),
                onSurface.withValues(alpha: 0.48),
                onSurface,
                onSurface.withValues(alpha: 0.48),
                onSurface.withValues(alpha: 0.42),
              ],
              const [0, 0.34, 0.5, 0.66, 1],
              TileMode.clamp,
            );
          },
          child: child,
        );
      },
      child: Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.start,
        style: widget.style.copyWith(color: Colors.white),
      ),
    );
  }
}

class ChatResponseShimmer extends StatelessWidget {
  const ChatResponseShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Budget AI is preparing a response',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(0, constraints.maxWidth - 24);
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChatShimmerBlock(
                    width: width * 0.88,
                    height: 14,
                    reverse: true,
                  ),
                  const SizedBox(height: 9),
                  ChatShimmerBlock(
                    width: width * 0.96,
                    height: 14,
                    reverse: true,
                  ),
                  const SizedBox(height: 9),
                  ChatShimmerBlock(
                    width: width * 0.58,
                    height: 14,
                    reverse: true,
                  ),
                ],
              ),
            );
          },
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
  final String message;
  final bool animateEntrance;

  const ChatLoadingMessage({
    super.key,
    required this.message,
    this.animateEntrance = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final content = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 2, 12, 12),
      child: SizedBox(
        width: double.infinity,
        child: Semantics(
          liveRegion: true,
          excludeSemantics: true,
          label: message,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primary.withValues(alpha: isDark ? 0.42 : 0.30),
                  AppTheme.highlight.withValues(alpha: isDark ? 0.26 : 0.18),
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? primary.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.055),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(1),
              padding: const EdgeInsetsDirectional.fromSTEB(9, 8, 13, 8),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  primary.withValues(alpha: isDark ? 0.07 : 0.035),
                  theme.colorScheme.surface,
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RepaintBoundary(
                    child: ChatBudgetLoadingIndicator(size: 42),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyMedium.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontSize: 14,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Budget AI is preparing your response',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!animateEntrance) return content;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: content,
      builder: (context, progress, child) {
        return ClipRect(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            heightFactor: progress,
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.97 + (0.03 * progress),
                alignment: AlignmentDirectional.topStart,
                child: child,
              ),
            ),
          ),
        );
      },
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

class ChatWorkingComposerFrame extends StatefulWidget {
  const ChatWorkingComposerFrame({
    super.key,
    required this.isWorking,
    required this.child,
    this.borderRadius = 28,
  });

  final bool isWorking;
  final Widget child;
  final double borderRadius;

  @override
  State<ChatWorkingComposerFrame> createState() =>
      _ChatWorkingComposerFrameState();
}

class _ChatWorkingComposerFrameState extends State<ChatWorkingComposerFrame>
    with SingleTickerProviderStateMixin {
  static const _normalDuration = Duration(milliseconds: 3600);
  static const _workingDuration = Duration(milliseconds: 1900);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.isWorking ? _workingDuration : _normalDuration,
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant ChatWorkingComposerFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isWorking == widget.isWorking) return;
    _controller.duration = widget.isWorking
        ? _workingDuration
        : _normalDuration;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return CustomPaint(
          foregroundPainter: _WorkingComposerBorderPainter(
            progress: _controller.value,
            isWorking: widget.isWorking,
            borderRadius: widget.borderRadius,
            primary: theme.colorScheme.primary,
            accent: AppTheme.highlight,
            normalAlpha: theme.brightness == Brightness.dark ? 0.78 : 0.72,
          ),
          child: child,
        );
      },
    );
  }
}

class _WorkingComposerBorderPainter extends CustomPainter {
  const _WorkingComposerBorderPainter({
    required this.progress,
    required this.isWorking,
    required this.borderRadius,
    required this.primary,
    required this.accent,
    required this.normalAlpha,
  });

  final double progress;
  final bool isWorking;
  final double borderRadius;
  final Color primary;
  final Color accent;
  final double normalAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    final rect = (Offset.zero & size).deflate(1.25);
    final border = RRect.fromRectAndRadius(
      rect,
      Radius.circular(borderRadius - 1.25),
    );

    if (isWorking) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = primary.withValues(alpha: 0.045 + pulse * 0.035);
      canvas.drawRRect(border, glowPaint);
    }

    final baseAlpha = isWorking ? 0.16 : normalAlpha * 0.22;
    final highlightAlpha = isWorking ? 1.0 : normalAlpha;
    final accentAlpha = isWorking ? 1.0 : normalAlpha * 0.82;
    final tailAlpha = isWorking ? 0.20 : normalAlpha * 0.45;

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isWorking ? 1.7 : 1
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          primary.withValues(alpha: baseAlpha),
          primary.withValues(alpha: highlightAlpha),
          accent.withValues(alpha: accentAlpha),
          primary.withValues(alpha: tailAlpha),
          primary.withValues(alpha: baseAlpha),
        ],
        stops: const [0, 0.26, 0.48, 0.76, 1],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(rect);
    canvas.drawRRect(border, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _WorkingComposerBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isWorking != isWorking ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.primary != primary ||
        oldDelegate.accent != accent ||
        oldDelegate.normalAlpha != normalAlpha;
  }
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
