import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp_math.dart';

enum BiquadType { lowPass, highPass, bandPass }

/// RBJ-cookbook biquad in transposed direct form II, with independent left
/// and right state. Coefficients change only through [set], which callers
/// drive at block rate; there is no internal smoothing.
final class Biquad {
  int _rate = 48000;
  BiquadType? _type;
  double _freq = 0.0;
  double _q = 0.0;
  int _updates = 0;

  double _b0 = 1.0;
  double _b1 = 0.0;
  double _b2 = 0.0;
  double _a1 = 0.0;
  double _a2 = 0.0;

  double _l1 = 0.0;
  double _l2 = 0.0;
  double _r1 = 0.0;
  double _r2 = 0.0;

  /// A passthrough until the first [set].
  Biquad();

  /// Stores the rate, resets the state and returns to passthrough.
  void prepare(int sampleRate) {
    _rate = sampleRate;
    _type = null;
    _freq = 0.0;
    _q = 0.0;
    _b0 = 1.0;
    _b1 = 0.0;
    _b2 = 0.0;
    _a1 = 0.0;
    _a2 = 0.0;
    reset();
  }

  /// Sets the response. [freqHz] is clamped to 20 Hz..0.45 × rate and [q] to
  /// 0.1..50. Coefficients are recomputed only when the type or a clamped
  /// value changed. The state is left untouched.
  void set(BiquadType type, double freqHz, double q) {
    final f = clampD(freqHz, 20.0, 0.45 * _rate);
    final qc = clampD(q, 0.1, 50.0);
    if (type == _type && f == _freq && qc == _q) return;
    _type = type;
    _freq = f;
    _q = qc;
    _updates++;

    final w0 = 2.0 * math.pi * f / _rate;
    final cs = math.cos(w0);
    final al = math.sin(w0) / (2.0 * qc);
    final a0 = 1.0 + al;
    switch (type) {
      case BiquadType.lowPass:
        _b1 = (1.0 - cs) / a0;
        _b0 = _b1 * 0.5;
        _b2 = _b0;
      case BiquadType.highPass:
        _b1 = -(1.0 + cs) / a0;
        _b0 = -_b1 * 0.5;
        _b2 = _b0;
      case BiquadType.bandPass:
        _b0 = al / a0;
        _b1 = 0.0;
        _b2 = -_b0;
    }
    _a1 = -2.0 * cs / a0;
    _a2 = (1.0 - al) / a0;
  }

  /// Clamped frequency in use.
  double get frequency => _freq;

  /// Clamped Q in use.
  double get q => _q;

  /// Number of coefficient recomputations so far.
  int get updateCount => _updates;

  /// Filters the first [frames] samples of both channels in place.
  void processStereo(Float32List left, Float32List right, int frames) {
    final b0 = _b0, b1 = _b1, b2 = _b2, a1 = _a1, a2 = _a2;
    var l1 = _l1, l2 = _l2, r1 = _r1, r2 = _r2;
    for (var i = 0; i < frames; i++) {
      final xl = left[i];
      final yl = b0 * xl + l1;
      l1 = b1 * xl - a1 * yl + l2;
      l2 = b2 * xl - a2 * yl;
      left[i] = yl;

      final xr = right[i];
      final yr = b0 * xr + r1;
      r1 = b1 * xr - a1 * yr + r2;
      r2 = b2 * xr - a2 * yr;
      right[i] = yr;
    }
    _l1 = flushDenormal(l1);
    _l2 = flushDenormal(l2);
    _r1 = flushDenormal(r1);
    _r2 = flushDenormal(r2);
  }

  /// Filters `buf[start..end)` in place with the left-channel state.
  void processMono(Float32List buf, int start, int end) {
    final b0 = _b0, b1 = _b1, b2 = _b2, a1 = _a1, a2 = _a2;
    var z1 = _l1, z2 = _l2;
    for (var i = start; i < end; i++) {
      final x = buf[i];
      final y = b0 * x + z1;
      z1 = b1 * x - a1 * y + z2;
      z2 = b2 * x - a2 * y;
      buf[i] = y;
    }
    _l1 = flushDenormal(z1);
    _l2 = flushDenormal(z2);
  }

  /// Zeroes the state of both channels.
  void reset() {
    _l1 = 0.0;
    _l2 = 0.0;
    _r1 = 0.0;
    _r2 = 0.0;
  }

  /// Whether all four state values are exactly 0.0.
  bool get isQuiet => _l1 == 0.0 && _l2 == 0.0 && _r1 == 0.0 && _r2 == 0.0;
}
