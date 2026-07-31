import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Shared low-level motion helpers used by every splash variant so each
/// variant file only has to describe what it looks like, not how springs
/// or phase windows are computed.
class SplashMotion {
  const SplashMotion._();

  /// A slower-settling "expo out" deceleration — reads as considered rather
  /// than bouncy. Used across variants in place of stock Flutter curves.
  static const Cubic expoOut = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Analytic under-damped harmonic oscillator, normalized to settle at 1.
  /// Higher [zeta] (closer to 1) means less overshoot/bounce.
  static double spring(
    double seconds, {
    double zeta = 0.85,
    double omega = 10,
  }) {
    if (seconds <= 0) return 0;
    final wd = omega * math.sqrt(1 - zeta * zeta);
    final decay = math.exp(-zeta * omega * seconds);
    return 1 -
        decay *
            (math.cos(wd * seconds) +
                (zeta * omega / wd) * math.sin(wd * seconds));
  }

  /// Maps [t] linearly from the [start]..[end] window to 0..1, clamped.
  static double phase(double t, double start, double end) {
    return ((t - start) / (end - start)).clamp(0.0, 1.0);
  }
}
