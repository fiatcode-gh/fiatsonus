import 'dart:math' as math;
import 'dart:typed_data';

/// Stereo-linked peak limiter with a soft knee, instant attack and an
/// exponential release (PLAN M6). Keeps every output magnitude below
/// [ceiling] for any finite input and leaves the signal bit-identical while
/// it stays at or below [knee] and the gain is at unity.
final class Limiter {
  static const double ceiling = 0.8912;
  static const double knee = 0.5;
  static const double releaseSeconds = 0.15;

  double _g = 1.0;
  double _rel = 0.0;

  /// Computes the release coefficient for [sampleRate] and resets the gain.
  void prepare(int sampleRate) {
    _rel = 1.0 - math.exp(-1.0 / (releaseSeconds * sampleRate));
    _g = 1.0;
  }

  /// Limits [left]/[right] in place with one gain shared by both channels.
  void process(Float32List left, Float32List right, int frames) {
    const range = ceiling - knee;
    final rel = _rel;
    var g = _g;
    for (var i = 0; i < frames; i++) {
      final l = left[i];
      final r = right[i];
      final al = l.abs();
      final ar = r.abs();
      final p = al > ar ? al : ar;
      if (p > knee) {
        final d = (p - knee) / range;
        final t = (knee + range * d / (1.0 + d)) / p;
        if (t < g) {
          g = t;
        } else {
          g += (t - g) * rel;
        }
      } else if (g < 1.0) {
        g += (1.0 - g) * rel;
        if (1.0 - g < 1e-9) g = 1.0;
      }
      if (g < 1.0) {
        left[i] = l * g;
        right[i] = r * g;
      }
    }
    _g = g;
  }

  /// Current linked gain; 1.0 when idle.
  double get gain => _g;

  /// Returns the gain to unity.
  void reset() {
    _g = 1.0;
  }
}
