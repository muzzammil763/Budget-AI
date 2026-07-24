import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/vibration_manager.dart';
import 'package:budget_ai/src/splash/splash_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _introDuration = Duration(milliseconds: 2400);
  static const _revealDuration = Duration(milliseconds: 560);
  static const _breathingPause = Duration(milliseconds: 180);

  late final AnimationController _intro;
  late final AnimationController _reveal;
  late final List<_Particle> _particles;
  late final List<bool> _particleHapticFired;

  bool _appMounted = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _particles = _Particle.field(count: 64, seed: 7);
    _particleHapticFired = List<bool>.filled(_particles.length, false);
    _intro = AnimationController(vsync: this, duration: _introDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _startReveal();
      })
      ..forward();
    _reveal = AnimationController(vsync: this, duration: _revealDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _done = true);
        }
      });
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted) HapticFeedback.lightImpact();
    });
  }

  void _triggerParticleHaptics(double time) {
    for (var i = 0; i < _particles.length; i++) {
      if (_particleHapticFired[i]) continue;
      if (time - _particles[i].delay <= 0) continue;
      _particleHapticFired[i] = true;
      VibrationManager.instance.triggerParticleFeedback();
    }
  }

  void _startReveal() {
    if (!mounted) return;
    setState(() => _appMounted = true);
    void beginReveal() {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _reveal.forward();
    }

    Future<void>.delayed(_breathingPause, beginReveal);
  }

  @override
  void dispose() {
    _intro.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontFamily = theme.textTheme.bodyLarge?.fontFamily;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_appMounted) widget.child,
        if (!_done)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _appMounted,
              child: AnimatedBuilder(
                animation: Listenable.merge([_intro, _reveal]),
                builder: (context, _) {
                  final revealT = SplashMotion.expoOut.transform(
                    _reveal.value,
                  );
                  final time =
                      _intro.value * _introDuration.inMilliseconds / 1000 +
                      _reveal.value * _revealDuration.inMilliseconds / 1000;
                  _triggerParticleHaptics(time);
                  return ClipPath(
                    clipper: _CircleRevealClipper(progress: revealT),
                    child: Transform.scale(
                      scale: 1 + 0.05 * revealT,
                      child: CustomPaint(
                        isComplex: true,
                        painter: _SplashPainter(
                          t: _intro.value,
                          time: time,
                          revealT: revealT,
                          particles: _particles,
                          surface: theme.scaffoldBackgroundColor,
                          primary: theme.colorScheme.primary,
                          onSurface: theme.colorScheme.onSurface,
                          accent: AppTheme.highlight,
                          isDark: theme.brightness == Brightness.dark,
                          fontFamily: fontFamily,
                          bottomInset: bottomInset,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  const _CircleRevealClipper({required this.progress});

  final double progress;

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius =
        0.5 * math.sqrt(size.width * size.width + size.height * size.height);
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(
        Rect.fromCircle(center: center, radius: maxRadius * progress),
      ),
    );
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper oldClipper) {
    return progress != oldClipper.progress;
  }
}

class _Particle {
  const _Particle({
    required this.startAngle,
    required this.startRadius,
    required this.orbitAngle,
    required this.orbitRadius,
    required this.orbitSpeed,
    required this.size,
    required this.delay,
    required this.zeta,
    required this.omega,
    required this.wobblePhase,
    required this.alpha,
  });

  final double startAngle;
  final double startRadius;
  final double orbitAngle;
  final double orbitRadius;
  final double orbitSpeed;
  final double size;
  final double delay;
  final double zeta;
  final double omega;
  final double wobblePhase;
  final double alpha;

  static List<_Particle> field({required int count, required int seed}) {
    final rnd = math.Random(seed);
    return List<_Particle>.generate(count, (i) {
      final ring = i % 3;
      return _Particle(
        startAngle: rnd.nextDouble() * math.pi * 2,
        startRadius: 0.6 + rnd.nextDouble() * 0.55,
        orbitAngle: (i / count) * math.pi * 2 + (rnd.nextDouble() - 0.5) * 0.5,
        orbitRadius: 0.27 + ring * 0.055 + rnd.nextDouble() * 0.03,
        orbitSpeed:
            (0.08 + rnd.nextDouble() * 0.16) * (rnd.nextBool() ? 1 : -1),
        size: 0.9 + rnd.nextDouble() * 1.7,
        delay: rnd.nextDouble() * 0.45,
        zeta: 0.5 + rnd.nextDouble() * 0.3,
        omega: 5.5 + rnd.nextDouble() * 3.5,
        wobblePhase: rnd.nextDouble() * math.pi * 2,
        alpha: 0.10 + rnd.nextDouble() * 0.22,
      );
    });
  }
}

class _SplashPainter extends CustomPainter {
  _SplashPainter({
    required this.t,
    required this.time,
    required this.revealT,
    required this.particles,
    required this.surface,
    required this.primary,
    required this.onSurface,
    required this.accent,
    required this.isDark,
    required this.fontFamily,
    required this.bottomInset,
  });

  final double t;
  final double time;
  final double revealT;
  final List<_Particle> particles;
  final Color surface;
  final Color primary;
  final Color onSurface;
  final Color accent;
  final bool isDark;
  final String? fontFamily;
  final double bottomInset;

  static const _chartValues = <double>[
    0.18,
    0.32,
    0.26,
    0.48,
    0.40,
    0.62,
    0.55,
    0.80,
    0.72,
    0.96,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final shortest = math.min(size.width, size.height);

    canvas.drawColor(surface, BlendMode.src);
    _paintAmbient(canvas, size, center, shortest);
    _paintParticles(canvas, center, shortest);
    _paintChart(canvas, size, center, shortest);
    _paintLogo(canvas, center, shortest);
    _paintWordmark(canvas, center, shortest);
    _paintProgress(canvas, size, center);
    _paintRevealRing(canvas, size, center);
  }

  void _paintAmbient(Canvas canvas, Size size, Offset center, double shortest) {
    final glowIn = SplashMotion.expoOut.transform(
      SplashMotion.phase(t, 0.0, 0.4),
    );
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(center, shortest * 0.72, [
        accent.withValues(alpha: (isDark ? 0.10 : 0.05) * glowIn),
        accent.withValues(alpha: 0),
      ]);
    canvas.drawCircle(center, shortest * 0.72, glowPaint);

    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var k = 0; k < 2; k++) {
      final pulseT = (time * 0.42 + k * 0.5) % 1.0;
      final radius = shortest * (0.16 + 0.42 * pulseT);
      pulsePaint.color = onSurface.withValues(
        alpha: 0.07 * (1 - pulseT) * glowIn,
      );
      canvas.drawCircle(center, radius, pulsePaint);
    }
  }

  void _paintParticles(Canvas canvas, Offset center, double shortest) {
    final paint = Paint();
    for (final p in particles) {
      final arriveT = math.max(0.0, time - p.delay);
      if (arriveT <= 0) continue;
      final s = SplashMotion.spring(arriveT, zeta: p.zeta, omega: p.omega);

      final angle = p.orbitAngle + time * p.orbitSpeed;
      final wobble = 1 + 0.04 * math.sin(time * 1.8 + p.wobblePhase);
      final target =
          center +
          Offset(math.cos(angle), math.sin(angle)) *
              (p.orbitRadius * shortest * wobble);
      final start =
          center +
          Offset(math.cos(p.startAngle), math.sin(p.startAngle)) *
              (p.startRadius * shortest);
      final pos = Offset.lerp(start, target, s)!;

      final fadeIn = (arriveT * 2.4).clamp(0.0, 1.0);
      paint.color = onSurface.withValues(alpha: p.alpha * fadeIn);
      canvas.drawCircle(pos, p.size, paint);
      if (p.size > 2.0) {
        paint.color = onSurface.withValues(alpha: p.alpha * fadeIn * 0.25);
        canvas.drawCircle(pos, p.size * 2.4, paint);
      }
    }
  }

  void _paintChart(Canvas canvas, Size size, Offset center, double shortest) {
    final drawT = SplashMotion.expoOut.transform(
      SplashMotion.phase(t, 0.28, 0.70),
    );
    if (drawT <= 0) return;

    final chartWidth = size.width * 0.86;
    final left = center.dx - chartWidth / 2;
    final baseY = center.dy + shortest * 0.20;
    final amplitude = shortest * 0.36;

    final points = <Offset>[
      for (var i = 0; i < _chartValues.length; i++)
        Offset(
          left + chartWidth * i / (_chartValues.length - 1),
          baseY - amplitude * _chartValues[i],
        ),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[math.max(0, i - 1)];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[math.min(points.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    final metric = path.computeMetrics().first;
    final trimmed = metric.extractPath(0, metric.length * drawT);

    final tip = metric.getTangentForOffset(metric.length * drawT)!.position;

    final areaPath = Path.from(trimmed)
      ..lineTo(tip.dx, baseY)
      ..lineTo(points.first.dx, baseY)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, baseY - amplitude),
          Offset(0, baseY),
          [accent.withValues(alpha: 0.07 * drawT), accent.withValues(alpha: 0)],
        ),
    );

    canvas.drawPath(
      trimmed,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = onSurface.withValues(alpha: 0.10 * drawT),
    );

    if (drawT < 1) {
      canvas.drawCircle(
        tip,
        7,
        Paint()
          ..color = accent.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(tip, 2.6, Paint()..color = accent);
    }
  }

  void _paintLogo(Canvas canvas, Offset center, double shortest) {
    final entrySeconds = math.max(0.0, time - 0.25);
    if (entrySeconds <= 0) return;

    final scale = SplashMotion.spring(entrySeconds, zeta: 0.9, omega: 10);
    final fadeIn = (entrySeconds * 3.5).clamp(0.0, 1.0);
    final cardSize = shortest * 0.34;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale.clamp(0.0, 1.5));
    canvas.translate(-center.dx, -center.dy);

    final rect = Rect.fromCenter(
      center: center,
      width: cardSize,
      height: cardSize,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(cardSize * 0.30),
    );
    final cardPath = Path()..addRRect(rrect);

    if (isDark) {
      canvas.drawRRect(
        rrect.inflate(2),
        Paint()
          ..color = accent.withValues(alpha: 0.16 * fadeIn)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
    } else {
      canvas.drawShadow(
        cardPath,
        Colors.black.withValues(alpha: fadeIn),
        14,
        true,
      );
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          primary.withValues(alpha: fadeIn),
          Color.lerp(primary, accent, 0.28)!.withValues(alpha: fadeIn),
        ]),
    );

    final barWidth = cardSize * 0.13;
    final gap = cardSize * 0.075;
    final baseline = rect.bottom - cardSize * 0.22;
    final maxHeights = [cardSize * 0.24, cardSize * 0.38, cardSize * 0.52];
    final barsLeft = center.dx - (barWidth * 3 + gap * 2) / 2;
    final barPaint = Paint()..color = surface.withValues(alpha: fadeIn);

    for (var i = 0; i < 3; i++) {
      final barSeconds = math.max(0.0, time - (0.55 + i * 0.10));
      final growth = SplashMotion.spring(
        barSeconds,
        zeta: 0.85,
        omega: 9,
      ).clamp(0.0, 1.1);
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

    canvas.restore();
  }

  void _paintWordmark(Canvas canvas, Offset center, double shortest) {
    final wordT = SplashMotion.expoOut.transform(
      SplashMotion.phase(t, 0.42, 0.72),
    );
    if (wordT <= 0) return;

    final cardSize = shortest * 0.26;
    final wordY = center.dy + cardSize * 0.80 + 18;
    final tracking = ui.lerpDouble(9.0, 0.6, wordT)!;
    final fontSize = shortest * 0.058;

    final wordStyle = TextStyle(
      fontFamily: 'Boldonse',
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: tracking,
      color: onSurface.withValues(alpha: wordT),
    );
    final wordPainter = TextPainter(
      text: TextSpan(text: 'Budget AI', style: wordStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final wordOffset = Offset(
      center.dx - wordPainter.width / 2 + tracking / 2,
      wordY + (1 - wordT) * 12,
    );
    final taglineGap = (shortest * 0.026).clamp(10.0, 15.0);
    wordPainter.paint(canvas, wordOffset);

    final shimmerT = SplashMotion.phase(t, 0.68, 0.94);
    if (shimmerT > 0 && shimmerT < 1) {
      final sweepX = ui.lerpDouble(
        wordOffset.dx - 70,
        wordOffset.dx + wordPainter.width + 70,
        Curves.easeInOut.transform(shimmerT),
      )!;
      final shimmerPainter = TextPainter(
        text: TextSpan(
          text: 'Budget AI',
          style: wordStyle.copyWith(
            color: null,
            foreground: Paint()
              ..shader = ui.Gradient.linear(
                Offset(sweepX - 60, 0),
                Offset(sweepX + 60, 0),
                [
                  accent.withValues(alpha: 0),
                  accent.withValues(alpha: 0.75),
                  accent.withValues(alpha: 0),
                ],
                [0.0, 0.5, 1.0],
              ),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      shimmerPainter.paint(canvas, wordOffset);
    }

    final tagT = SplashMotion.expoOut.transform(
      SplashMotion.phase(t, 0.56, 0.86),
    );
    if (tagT > 0) {
      final tagPainter = TextPainter(
        text: TextSpan(
          text: 'MONEY · CLARITY · MOMENTUM',
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: shortest * 0.027,
            fontWeight: FontWeight.w600,
            letterSpacing: ui.lerpDouble(5.0, 2.2, tagT)!,
            color: onSurface.withValues(alpha: 0.55 * tagT),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tagPainter.paint(
        canvas,
        Offset(
          center.dx - tagPainter.width / 2,
          wordOffset.dy + wordPainter.height + taglineGap + (1 - tagT) * 8,
        ),
      );
    }
  }

  void _paintProgress(Canvas canvas, Size size, Offset center) {
    final y = size.height - bottomInset - 48;
    const trackWidth = 64.0;
    final left = center.dx - trackWidth / 2;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, y, trackWidth, 3),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(track, Paint()..color = onSurface.withValues(alpha: 0.08));
    final fill = trackWidth * SplashMotion.expoOut.transform(t);
    if (fill > 3) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y, fill, 3),
          const Radius.circular(1.5),
        ),
        Paint()..color = accent,
      );
    }
  }

  void _paintRevealRing(Canvas canvas, Size size, Offset center) {
    if (revealT <= 0 || revealT >= 1) return;
    final maxRadius =
        0.5 * math.sqrt(size.width * size.width + size.height * size.height);
    final radius = maxRadius * revealT;
    final fade = 1 - revealT;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..color = accent.withValues(alpha: 0.22 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = accent.withValues(alpha: 0.6 * fade),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashPainter oldDelegate) {
    return t != oldDelegate.t ||
        time != oldDelegate.time ||
        revealT != oldDelegate.revealT ||
        surface != oldDelegate.surface ||
        primary != oldDelegate.primary ||
        onSurface != oldDelegate.onSurface;
  }
}
