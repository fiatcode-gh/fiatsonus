import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/master/limiter.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

const _rate = 48000;

Limiter _limiter() => Limiter()..prepare(_rate);

/// Processes [left]/[right] in place in engine-sized blocks.
void _process(Limiter limiter, Float32List left, Float32List right) {
  for (var start = 0; start < left.length; start += kBlockFrames) {
    final end = start + kBlockFrames <= left.length
        ? start + kBlockFrames
        : left.length;
    limiter.process(
      Float32List.sublistView(left, start, end),
      Float32List.sublistView(right, start, end),
      end - start,
    );
  }
}

Float32List _constant(double v, [int frames = _rate]) =>
    Float32List(frames)..fillRange(0, frames, v);

Float32List _noise(int seed, double amplitude, [int frames = _rate]) {
  final rng = Rng(seed);
  final out = Float32List(frames);
  for (var i = 0; i < frames; i++) {
    out[i] = rng.range(-amplitude, amplitude);
  }
  return out;
}

double _peak(Float32List buf) {
  var p = 0.0;
  for (var i = 0; i < buf.length; i++) {
    final a = buf[i].abs();
    if (a > p) p = a;
  }
  return p;
}

/// Steady-state output level for a constant input [p] on both channels.
double _static(double p) {
  final l = _constant(p);
  final r = _constant(p);
  _process(_limiter(), l, r);
  return l[l.length - 1];
}

void main() {
  test('below the knee the signal is bit-identical', () {
    final left = _noise(1, 0.49);
    final right = _noise(2, 0.49);
    final l = Float32List.fromList(left);
    final r = Float32List.fromList(right);
    final limiter = _limiter();
    _process(limiter, l, r);
    expect(l, orderedEquals(left));
    expect(r, orderedEquals(right));
    expect(limiter.gain, 1.0);
  });

  group('every output stays below the ceiling for', () {
    final cases = <String, (Float32List, Float32List)>{
      'constant 3.0': (_constant(3.0), _constant(3.0)),
      '1 kHz sine of amplitude 4.0': (
        Float32List.fromList([
          for (var i = 0; i < _rate; i++)
            4.0 * math.sin(2 * math.pi * 1000 * i / _rate),
        ]),
        Float32List.fromList([
          for (var i = 0; i < _rate; i++)
            4.0 * math.sin(2 * math.pi * 1000 * i / _rate),
        ]),
      ),
      'noise in ±8': (_noise(3, 8.0), _noise(4, 8.0)),
    };
    cases.forEach((name, signal) {
      test(name, () {
        final (l, r) = signal;
        _process(_limiter(), l, r);
        expect(_peak(l), lessThan(Limiter.ceiling));
        expect(_peak(r), lessThan(Limiter.ceiling));
      });
    });
  });

  test('static curve follows the M6 law and increases strictly', () {
    expect(_static(0.5), 0.5);
    expect(_static(0.7), closeTo(0.6323, 0.001));
    expect(_static(2.0), closeTo(0.8103, 0.001));
    var previous = _static(0.5);
    for (var k = 6; k <= 40; k++) {
      final out = _static(k / 10);
      expect(out, greaterThan(previous), reason: 'p = ${k / 10}');
      previous = out;
    }
  });

  test('channels are linked through one gain', () {
    final l = _constant(2.0);
    final r = _constant(0.1);
    final limiter = _limiter();
    _process(limiter, l, r);
    final g = limiter.gain;
    expect(g, lessThan(1.0));
    expect(l.last, closeTo(2.0 * g, 1e-6));
    expect(r.last, closeTo(0.1 * g, 1e-6));
  });

  test('release recovers to exactly unity, then passes bit-identical', () {
    final limiter = _limiter();
    _process(limiter, _constant(2.0, _rate ~/ 2), _constant(2.0, _rate ~/ 2));
    final one = Float32List(1);
    final two = Float32List(1);
    var previous = limiter.gain;
    var reachedUnityAt = -1;
    for (var i = 0; i < 4 * _rate; i++) {
      one[0] = 0.1;
      two[0] = 0.1;
      limiter.process(one, two, 1);
      final g = limiter.gain;
      expect(g, greaterThanOrEqualTo(previous));
      if (i == (0.75 * _rate).round() - 1) expect(g, greaterThan(0.99));
      if (g == 1.0 && reachedUnityAt < 0) reachedUnityAt = i;
      previous = g;
    }
    expect(reachedUnityAt, greaterThanOrEqualTo(0));
    final left = _noise(5, 0.49);
    final right = _noise(6, 0.49);
    final l = Float32List.fromList(left);
    final r = Float32List.fromList(right);
    _process(limiter, l, r);
    expect(l, orderedEquals(left));
    expect(r, orderedEquals(right));
  });

  test('attack is instant', () {
    final l = Float32List.fromList([0.1, 0.2, 5.0, 5.0]);
    final r = Float32List.fromList([0.1, 0.2, 0.0, 0.0]);
    _limiter().process(l, r, 4);
    expect(l[2].abs(), lessThan(Limiter.ceiling));
  });

  test('reset restores unity gain', () {
    final limiter = _limiter();
    _process(limiter, _constant(3.0), _constant(3.0));
    expect(limiter.gain, lessThan(1.0));
    limiter.reset();
    expect(limiter.gain, 1.0);
  });
}
