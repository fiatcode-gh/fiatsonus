import 'dart:math' as math;

import 'dsp_math.dart';
import 'rng.dart';

/// Poisson grain timer. It only decides when grains start; the layer draws
/// each grain's values from its own generator.
///
/// The wait for the next grain is kept as a rate-free exponential variate
/// and converted to frames with the current rate when consumed, so a rate
/// change rescales the pending wait at once: the exact timing of a Poisson
/// process whose rate changes over time.
final class GrainCloud {
  final Rng _rng;
  int _sampleRate = 48000;
  double _rate = 0.0;

  /// Exponential variate still to elapse before the next grain, in mean
  /// gaps; -1 = not drawn.
  double _pending = -1.0;

  /// Frames reached in the current block.
  double _cursor = 0.0;

  GrainCloud(Rng rng) : _rng = rng;

  /// Stores the sample rate and forgets any drawn gap.
  void prepare(int sampleRate) {
    _sampleRate = sampleRate;
    _pending = -1.0;
    _cursor = 0.0;
  }

  /// Grains per second.
  double get rate => _rate;

  /// Clamped to 0..4000, NaN acts as 0. Rescales the pending wait at once.
  set rate(double grainsPerSecond) {
    _rate = clampD(grainsPerSecond, 0.0, 4000.0);
  }

  /// Exponential variate with mean 1.
  double _draw() => -math.log(1.0 - _rng.nextDouble());

  /// The next grain offset in `[0, frames)`, or -1 when none is left in this
  /// block. Call it until it returns -1, once per block.
  int nextStart(int frames) {
    if (_rate <= 0.0) {
      _pending = -1.0;
      _cursor = 0.0;
      return -1;
    }
    if (_pending < 0.0) _pending = _draw();
    final framesPerGap = _sampleRate / _rate;
    final at = _cursor + _pending * framesPerGap;
    // Also waits when `at` is not finite (a rate near zero).
    if (!(at < frames)) {
      final left = _pending - (frames - _cursor) / framesPerGap;
      _pending = left > 0.0 ? left : 0.0;
      _cursor = 0.0;
      return -1;
    }
    _cursor = at;
    _pending = _draw();
    return at.toInt();
  }
}
