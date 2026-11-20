import 'dart:math' as math;

import '../core/engine_constants.dart';
import 'dsp_math.dart';

/// One-pole smoother advanced once per engine block.
final class Smoother {
  double _value;
  double _target;
  double _coefficient = 1.0;

  /// Starts at rest on [initial]. Until [prepare], [next] jumps to the target.
  Smoother(double initial) : _value = initial, _target = initial;

  /// Sets the block coefficient for [timeConstant] at [sampleRate]. The time
  /// constant is clamped to 1 ms..60 s.
  void prepare(int sampleRate, Duration timeConstant) {
    final tau = clampD(timeConstant.inMicroseconds / 1e6, 0.001, 60.0);
    _coefficient = 1.0 - math.exp(-kBlockFrames / (tau * sampleRate));
  }

  double get value => _value;

  double get target => _target;

  /// Sets the value to move toward. NaN is ignored.
  set target(double v) {
    if (v.isNaN) return;
    _target = v;
  }

  bool get isMoving => _value != _target;

  /// Advances one block and returns the new value.
  double next() {
    final d = _target - _value;
    if (d.abs() < 1e-5) {
      _value = _target;
    } else {
      _value += d * _coefficient;
    }
    return _value;
  }

  /// Jumps to the target.
  void snap() {
    _value = _target;
  }
}
