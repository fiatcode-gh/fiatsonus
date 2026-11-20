import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp_math.dart';

/// Up to [maxSegments] linear or exponential segments, applied by
/// multiplication. After the last frame of the last segment the value is 0
/// and the envelope is done (S7). Chunking [process] calls never changes the
/// result.
final class Envelope {
  static const int maxSegments = 4;
  static const double floor = 0.0001;

  int _rate = 48000;
  final Int32List _frames = Int32List(maxSegments);
  final Uint8List _isExp = Uint8List(maxSegments);

  /// Per-frame increment (linear) or ratio (exponential).
  final Float64List _step = Float64List(maxSegments);

  /// Start value of an exponential segment.
  final Float64List _from = Float64List(maxSegments);

  int _count = 0;
  int _segment = 0;
  int _position = 0;
  double _value = 0.0;
  double _lastTarget = 0.0;

  void prepare(int sampleRate) {
    _rate = sampleRate;
    reset();
  }

  /// Starts at [start] (clamped 0..4) with no segments.
  void begin(double start) {
    _value = clampD(start, 0.0, 4.0);
    _lastTarget = _value;
    _count = 0;
    _segment = 0;
    _position = 0;
  }

  int _length(double seconds) {
    final n = (clampD(seconds, 0.0, 60.0) * _rate).round();
    return n > 1 ? n : 1;
  }

  /// Appends a linear segment to [target] over [seconds].
  void lineTo(double target, double seconds) {
    if (_count == maxSegments) return;
    final t = clampD(target, 0.0, 4.0);
    final n = _length(seconds);
    final s = _count++;
    _frames[s] = n;
    _isExp[s] = 0;
    _step[s] = (t - _lastTarget) / n;
    _lastTarget = t;
  }

  /// Appends an exponential segment to [target] over [seconds]. Both ends are
  /// held at or above [floor].
  void expTo(double target, double seconds) {
    if (_count == maxSegments) return;
    final t = clampD(target, 0.0, 4.0);
    final n = _length(seconds);
    final from = _lastTarget > floor ? _lastTarget : floor;
    final to = t > floor ? t : floor;
    final s = _count++;
    _frames[s] = n;
    _isExp[s] = 1;
    _from[s] = from;
    _step[s] = math.exp(math.log(to / from) / n);
    _lastTarget = t;
  }

  double get value => _value;

  bool get isDone => _segment >= _count;

  int get remainingFrames {
    if (_segment >= _count) return 0;
    var n = _frames[_segment] - _position;
    for (var s = _segment + 1; s < _count; s++) {
      n += _frames[s];
    }
    return n;
  }

  /// Multiplies `buf[start..end)` in place.
  void process(Float32List buf, int start, int end) {
    var i = start;
    var v = _value;
    while (i < end && _segment < _count) {
      final s = _segment;
      final length = _frames[s];
      final left = length - _position;
      final n = end - i < left ? end - i : left;
      final stop = i + n;
      final step = _step[s];
      if (_isExp[s] == 1) {
        if (_position == 0) v = _from[s];
        for (; i < stop; i++) {
          v *= step;
          buf[i] *= v;
        }
      } else {
        for (; i < stop; i++) {
          v += step;
          buf[i] *= v;
        }
      }
      _position += n;
      if (_position == length) {
        _segment++;
        _position = 0;
      }
    }
    if (_segment >= _count) {
      v = 0.0;
      if (i < end) buf.fillRange(i, end, 0.0);
    }
    _value = v;
  }

  /// Done, value 0.
  void reset() {
    _count = 0;
    _segment = 0;
    _position = 0;
    _value = 0.0;
    _lastTarget = 0.0;
  }
}
