import 'dart:math' as math;

import 'dsp_math.dart';

/// Constant-power pan law. Called once per grain, never per sample.
abstract final class Panner {
  /// `cos((p + 1) · π/4)` for the clamped pan `p` (NaN acts as -1), written
  /// as `sin((1 − p) · π/4)` so hard right gives exactly 0.
  static double left(double pan) =>
      math.sin((1.0 - clampD(pan, -1.0, 1.0)) * math.pi / 4.0);

  /// `sin((p + 1) · π/4)` for the clamped pan `p` (NaN acts as -1).
  static double right(double pan) =>
      math.sin((clampD(pan, -1.0, 1.0) + 1.0) * math.pi / 4.0);
}
