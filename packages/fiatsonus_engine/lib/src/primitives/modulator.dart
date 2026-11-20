import '../core/engine_constants.dart';
import 'dsp_math.dart';
import 'rng.dart';

/// Smooth random walk advanced once per engine block. Each segment glides
/// from one random point in [-1, 1] to the next along a smoothstep curve and
/// lasts half a period of a frequency drawn from `minHz..maxHz`.
final class Modulator {
  final Rng _rng;
  final double _minHz;
  final double _maxHz;
  int _rate = 48000;
  double _a = 0.0;
  double _b = 0.0;
  double _phase = 0.0;
  double _inc = 0.0;
  double _value = 0.0;

  /// Clamps both bounds to 0.001..20 Hz and swaps them when reversed.
  Modulator(Rng rng, {required double minHz, required double maxHz})
    : _rng = rng,
      _minHz = _lower(_clampHz(minHz), _clampHz(maxHz)),
      _maxHz = _upper(_clampHz(minHz), _clampHz(maxHz));

  static double _clampHz(double hz) => clampD(hz, 0.001, 20.0);
  static double _lower(double a, double b) => a <= b ? a : b;
  static double _upper(double a, double b) => a <= b ? b : a;

  /// Stores the rate and starts a new walk from the generator.
  void prepare(int sampleRate) {
    _rate = sampleRate;
    _a = _rng.range(-1.0, 1.0);
    _b = _rng.range(-1.0, 1.0);
    _phase = 0.0;
    _newSegment();
    _value = _a;
  }

  void _newSegment() {
    final f = _rng.range(_minHz, _maxHz);
    final inc = kBlockFrames * 2.0 * f / _rate;
    _inc = inc < 1.0 ? inc : 1.0;
  }

  /// Advances one block and returns the new value in [-1, 1].
  double next() {
    _phase += _inc;
    if (_phase >= 1.0) {
      _phase -= 1.0;
      _a = _b;
      _b = _rng.range(-1.0, 1.0);
      _newSegment();
    }
    final t = _phase;
    _value = _a + (_b - _a) * t * t * (3.0 - 2.0 * t);
    return _value;
  }

  double get value => _value;

  /// [base] moved by at most [depth] × [base] (S3); depth is clamped to 0..1.
  double modulate(double base, double depth) =>
      base * (1.0 + clampD(depth, 0.0, 1.0) * _value);
}
