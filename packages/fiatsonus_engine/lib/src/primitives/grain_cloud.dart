import 'dart:math' as math;

import 'dsp_math.dart';
import 'rng.dart';

/// Poisson grain timer. It only decides when grains start; the layer draws
/// each grain's values from its own generator.
final class GrainCloud {
  final Rng _rng;
  int _sampleRate = 48000;
  double _rate = 0.0;

  /// Frames from [_cursor] to the next grain, fractional; -1 = not drawn.
  double _until = -1.0;

  /// Position reached in the current block.
  double _cursor = 0.0;

  GrainCloud(Rng rng) : _rng = rng;

  /// Stores the rate and forgets any drawn gap.
  void prepare(int sampleRate) {
    _sampleRate = sampleRate;
    _until = -1.0;
    _cursor = 0.0;
  }

  /// Grains per second.
  double get rate => _rate;

  /// Clamped to 0..4000, NaN acts as 0. Applies from the next gap drawn.
  set rate(double grainsPerSecond) {
    _rate = clampD(grainsPerSecond, 0.0, 4000.0);
  }

  /// Exponentially distributed gap in frames.
  double _gap() => -math.log(1.0 - _rng.nextDouble()) / _rate * _sampleRate;

  /// The next grain offset in `[0, frames)`, or -1 when none is left in this
  /// block. Call it until it returns -1, once per block.
  int nextStart(int frames) {
    if (_rate <= 0.0) {
      _until = -1.0;
      _cursor = 0.0;
      return -1;
    }
    if (_until < 0.0) _until = _gap();
    final at = _cursor + _until;
    if (at >= frames) {
      _until = at - frames;
      _cursor = 0.0;
      return -1;
    }
    _cursor = at;
    _until = _gap();
    return at.toInt();
  }
}
