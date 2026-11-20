import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp_math.dart';

/// Four-line feedback delay network with Householder feedback and one-pole
/// damping per line. Mono in (the average of both inputs), decorrelated
/// stereo out. One instance per soundscape; nothing is shared.
final class Reverb {
  static const double _s0 = 0.0297;
  static const double _s1 = 0.0371;
  static const double _s2 = 0.0411;
  static const double _s3 = 0.0437;

  final double _rt60;
  final double _dampingHz;

  Float32List _line0 = Float32List(1);
  Float32List _line1 = Float32List(1);
  Float32List _line2 = Float32List(1);
  Float32List _line3 = Float32List(1);
  int _i0 = 0;
  int _i1 = 0;
  int _i2 = 0;
  int _i3 = 0;
  double _z0 = 0.0;
  double _z1 = 0.0;
  double _z2 = 0.0;
  double _z3 = 0.0;
  double _g0 = 0.0;
  double _g1 = 0.0;
  double _g2 = 0.0;
  double _g3 = 0.0;
  double _dc = 1.0;

  /// [rt60Seconds] is clamped to 0.1..10; `dampingHz` is clamped in
  /// [prepare] to 200 Hz..0.45 × rate.
  Reverb({double rt60Seconds = 1.6, this._dampingHz = 4000})
    : _rt60 = clampD(rt60Seconds, 0.1, 10.0);

  /// Allocates the delay lines for [sampleRate] and clears all state.
  void prepare(int sampleRate) {
    _line0 = Float32List((_s0 * sampleRate).round() | 1);
    _line1 = Float32List((_s1 * sampleRate).round() | 1);
    _line2 = Float32List((_s2 * sampleRate).round() | 1);
    _line3 = Float32List((_s3 * sampleRate).round() | 1);
    _g0 = powD(10.0, -3.0 * _s0 / _rt60);
    _g1 = powD(10.0, -3.0 * _s1 / _rt60);
    _g2 = powD(10.0, -3.0 * _s2 / _rt60);
    _g3 = powD(10.0, -3.0 * _s3 / _rt60);
    final damping = clampD(_dampingHz, 200.0, 0.45 * sampleRate);
    _dc = 1.0 - math.exp(-2.0 * math.pi * damping / sampleRate);
    _clearState();
  }

  /// Adds the wet signal of [inL]/[inR] into [outL]/[outR]. The send moves
  /// linearly from [send0] and reaches [send1] on the last frame.
  ///
  /// The input and output buffers must be different lists.
  void process(
    Float32List inL,
    Float32List inR,
    Float32List outL,
    Float32List outR,
    int frames,
    double send0,
    double send1,
    double wetGain,
  ) {
    final line0 = _line0;
    final line1 = _line1;
    final line2 = _line2;
    final line3 = _line3;
    final n0 = line0.length;
    final n1 = line1.length;
    final n2 = line2.length;
    final n3 = line3.length;
    var i0 = _i0;
    var i1 = _i1;
    var i2 = _i2;
    var i3 = _i3;
    var z0 = _z0;
    var z1 = _z1;
    var z2 = _z2;
    var z3 = _z3;
    final g0 = _g0;
    final g1 = _g1;
    final g2 = _g2;
    final g3 = _g3;
    final dc = _dc;
    final ds = (send1 - send0) / frames;
    var send = send0;
    for (var i = 0; i < frames; i++) {
      send += ds;
      final x = (inL[i] + inR[i]) * 0.5 * send;
      final o0 = line0[i0];
      final o1 = line1[i1];
      final o2 = line2[i2];
      final o3 = line3[i3];
      z0 += dc * (o0 - z0);
      z1 += dc * (o1 - z1);
      z2 += dc * (o2 - z2);
      z3 += dc * (o3 - z3);
      final f0 = z0 * g0;
      final f1 = z1 * g1;
      final f2 = z2 * g2;
      final f3 = z3 * g3;
      final h = (f0 + f1 + f2 + f3) * 0.5;
      line0[i0] = flushDenormal(x + f0 - h);
      line1[i1] = flushDenormal(x + f1 - h);
      line2[i2] = flushDenormal(x + f2 - h);
      line3[i3] = flushDenormal(x + f3 - h);
      if (++i0 == n0) i0 = 0;
      if (++i1 == n1) i1 = 0;
      if (++i2 == n2) i2 = 0;
      if (++i3 == n3) i3 = 0;
      outL[i] += (o0 - o2) * wetGain;
      outR[i] += (o1 - o3) * wetGain;
    }
    _i0 = i0;
    _i1 = i1;
    _i2 = i2;
    _i3 = i3;
    _z0 = flushDenormal(z0);
    _z1 = flushDenormal(z1);
    _z2 = flushDenormal(z2);
    _z3 = flushDenormal(z3);
  }

  /// Zeroes the delay lines, damping states and indices. No allocation.
  void reset() => _clearState();

  /// Whether every delay sample and damping state is exactly 0.0. Scans all
  /// lines; meant for tests.
  bool get isQuiet =>
      _z0 == 0.0 &&
      _z1 == 0.0 &&
      _z2 == 0.0 &&
      _z3 == 0.0 &&
      _allZero(_line0) &&
      _allZero(_line1) &&
      _allZero(_line2) &&
      _allZero(_line3);

  void _clearState() {
    _line0.fillRange(0, _line0.length, 0.0);
    _line1.fillRange(0, _line1.length, 0.0);
    _line2.fillRange(0, _line2.length, 0.0);
    _line3.fillRange(0, _line3.length, 0.0);
    _i0 = 0;
    _i1 = 0;
    _i2 = 0;
    _i3 = 0;
    _z0 = 0.0;
    _z1 = 0.0;
    _z2 = 0.0;
    _z3 = 0.0;
  }

  static bool _allZero(Float32List line) {
    for (var i = 0; i < line.length; i++) {
      if (line[i] != 0.0) return false;
    }
    return true;
  }
}
