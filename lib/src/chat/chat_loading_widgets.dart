import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:flutter/cupertino.dart';
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

class ChatWorkingWord extends StatefulWidget {
  const ChatWorkingWord({super.key, this.fontSize = 22});

  final double fontSize;

  @override
  State<ChatWorkingWord> createState() => _ChatWorkingWordState();
}

class _ChatWorkingWordState extends State<ChatWorkingWord> {
  static const _words = [
    'Clauding',
    'Bruzzling',
    'Snuzzing',
    'Zuzzling',
    'Brewzing',
    'Thinkling',
    'Floopzing',
    'Glimbling',
    'Juzzling',
    'Klinkling',
    'Luzzling',
    'Mibbling',
    'Pluzzling',
    'Ruzzling',
    'Truzzling',
    'Vizzling',
    'Wuzzling',
    'Yuzzling',
    'Zibbling',
    'Brumbling',
    'Chuzzling',
    'Dazzmbling',
    'Frumbling',
    'Kluzzing',
    'Ploofing',
    'Squzzing',
    'Thrumbling',
    'Bloopling',
    'Crimbling',
    'Drumbling',
    'Fluzzing',
    'Grozzling',
    'Huzzling',
    'Prumbling',
    'Swoozling',
    'Bluzzing',
    'Crumblingo',
    'Drizzbling',
    'Frozzling',
    'Quzzling',
    'Snimbling',
    'Vroombling',
  ];

  final math.Random _random = math.Random();
  late final Timer _timer;
  late List<int> _shuffledWordIndexes;
  int _shufflePosition = 0;
  late int _wordIndex;
  int _dotCount = 1;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _shuffledWordIndexes = List.generate(_words.length, (index) => index)
      ..shuffle(_random);
    _wordIndex = _shuffledWordIndexes.first;
    _timer = Timer.periodic(const Duration(milliseconds: 480), (_) {
      if (!mounted) return;
      setState(() {
        _dotCount = (_dotCount % 3) + 1;
        _ticks++;
        if (_ticks % 4 == 0) {
          _shufflePosition++;
          if (_shufflePosition >= _shuffledWordIndexes.length) {
            final previousIndex = _wordIndex;
            do {
              _shuffledWordIndexes.shuffle(_random);
            } while (_shuffledWordIndexes.first == previousIndex);
            _shufflePosition = 0;
          }
          _wordIndex = _shuffledWordIndexes[_shufflePosition];
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
    final style = AppTheme.bodyMedium.copyWith(
      color: color,
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w400,
      height: 1,
      fontFamily: AppTheme.defaultFontFamily,
    );
    return Semantics(
      liveRegion: true,
      label: 'Budget AI is working',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeInOutCubic,
              alignment: AlignmentDirectional.centerStart,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 520),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.985, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                ),
                child: Text(
                  _words[_wordIndex],
                  key: ValueKey(_wordIndex),
                  maxLines: 1,
                  style: style,
                ),
              ),
            ),
            SizedBox(
              width: widget.fontSize * 0.9,
              child: Text(
                List.filled(_dotCount, '.').join(),
                maxLines: 1,
                style: style,
              ),
            ),
          ],
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

class ChatVoiceRecordingPulse extends StatefulWidget {
  const ChatVoiceRecordingPulse({super.key, this.size = 44});

  final double size;

  @override
  State<ChatVoiceRecordingPulse> createState() =>
      _ChatVoiceRecordingPulseState();
}

class _ChatVoiceRecordingPulseState extends State<ChatVoiceRecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _VoiceRecordingPulsePainter(
            progress: _controller.value,
            primary: theme.colorScheme.primary,
            accent: AppTheme.highlight,
          ),
          child: SizedBox.square(
            dimension: widget.size,
            child: Icon(
              CupertinoIcons.mic_fill,
              size: widget.size * 0.38,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class ChatVoiceRecordingStatus extends StatefulWidget {
  const ChatVoiceRecordingStatus({super.key});

  @override
  State<ChatVoiceRecordingStatus> createState() =>
      _ChatVoiceRecordingStatusState();
}

class _ChatVoiceRecordingStatusState extends State<ChatVoiceRecordingStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    _controller.dispose();
    super.dispose();
  }

  String get _elapsedLabel {
    final elapsed = _stopwatch.elapsed;
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: 'Recording voice message. Release to send.',
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 6, end: 5),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppTheme.highlight,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.highlight.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'Listening  $_elapsedLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyMedium.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Release to transcribe & send',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 54,
              height: 30,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _VoiceWavePainter(
                    progress: _controller.value,
                    primary: theme.colorScheme.primary,
                    accent: AppTheme.highlight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatVoiceRecordingButtonIcon extends StatefulWidget {
  const ChatVoiceRecordingButtonIcon({super.key});

  @override
  State<ChatVoiceRecordingButtonIcon> createState() =>
      _ChatVoiceRecordingButtonIconState();
}

class _ChatVoiceRecordingButtonIconState
    extends State<ChatVoiceRecordingButtonIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      lowerBound: 0.92,
      upperBound: 1.08,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _controller,
      child: Icon(
        CupertinoIcons.mic_fill,
        color: Theme.of(context).colorScheme.onPrimary,
        size: 23,
      ),
    );
  }
}

class _VoiceRecordingPulsePainter extends CustomPainter {
  const _VoiceRecordingPulsePainter({
    required this.progress,
    required this.primary,
    required this.accent,
  });

  final double progress;
  final Color primary;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    final radius = size.shortestSide * (0.37 + pulse * 0.05);
    canvas.drawCircle(
      center,
      size.shortestSide * (0.47 - progress * 0.06),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = accent.withValues(alpha: (1 - progress) * 0.5),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - radius, center.dy - radius),
          Offset(center.dx + radius, center.dy + radius),
          [primary, Color.lerp(primary, accent, 0.36)!],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _VoiceRecordingPulsePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      primary != oldDelegate.primary ||
      accent != oldDelegate.accent;
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({
    required this.progress,
    required this.primary,
    required this.accent,
  });

  final double progress;
  final Color primary;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 7;
    const barWidth = 3.2;
    final gap = (size.width - count * barWidth) / (count - 1);
    for (var index = 0; index < count; index++) {
      final phase = progress * math.pi * 2 + index * 0.86;
      final secondary = progress * math.pi * 4 - index * 0.48;
      final energy =
          (0.58 + 0.28 * math.sin(phase) + 0.14 * math.sin(secondary)).abs();
      final height = 6 + energy * (size.height - 6);
      final left = index * (barWidth + gap);
      final rect = Rect.fromLTWH(
        left,
        (size.height - height) / 2,
        barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = Color.lerp(
            primary,
            accent,
            index / (count - 1),
          )!.withValues(alpha: 0.72 + energy * 0.28),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      primary != oldDelegate.primary ||
      accent != oldDelegate.accent;
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
      ..strokeWidth = 1.7
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

  const _BudgetAiLoadingPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final chartBottom = center.dy + shortest * 0.25;
    final barWidth = shortest * 0.16;
    final gap = shortest * 0.09;
    final maxHeight = shortest * 0.64;
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
  }

  @override
  bool shouldRepaint(covariant _BudgetAiLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary;
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
