import 'dart:math' as math;

import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/primitives/modulator.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

const _minHz = 0.05;
const _maxHz = 2.0;

Modulator _mod(int seed, int rate) =>
    Modulator(Rng(seed), minHz: _minHz, maxHz: _maxHz)..prepare(rate);

void main() {
  for (final rate in [44100, 48000]) {
    group('at $rate Hz over 2000 s', () {
      test('stays in [-1, 1], moves smoothly and varies', () {
        final m = _mod(1, rate);
        final blocks = 2000 * rate ~/ kBlockFrames;
        final incMax = kBlockFrames * 2 * _maxHz / rate;
        var previous = m.value;
        var sum = 0.0;
        var sumSq = 0.0;
        var worstStep = 0.0;
        for (var i = 0; i < blocks; i++) {
          final v = m.next();
          expect(v, inInclusiveRange(-1.0, 1.0));
          expect(m.value, v);
          final step = (v - previous).abs();
          if (step > worstStep) worstStep = step;
          previous = v;
          sum += v;
          sumSq += v * v;
        }
        expect(worstStep, lessThanOrEqualTo(3 * incMax));
        final mean = sum / blocks;
        final sd = math.sqrt(sumSq / blocks - mean * mean);
        expect(sd, greaterThan(0.2));
      });
    });
  }

  test('equal seeds agree', () {
    final a = _mod(7, 48000);
    final b = _mod(7, 48000);
    for (var i = 0; i < 10000; i++) {
      expect(a.next(), b.next());
    }
  });

  test('reversed bounds are swapped and clamped', () {
    final a = Modulator(Rng(3), minHz: 2.0, maxHz: 0.05)..prepare(48000);
    final b = _mod(3, 48000);
    for (var i = 0; i < 10000; i++) {
      expect(a.next(), b.next());
    }
    final c = Modulator(Rng(3), minHz: double.nan, maxHz: 1e9)..prepare(48000);
    for (var i = 0; i < 10000; i++) {
      expect(c.next(), inInclusiveRange(-1.0, 1.0));
    }
  });

  group('modulate (S3)', () {
    test('a zero base stays zero', () {
      final m = _mod(2, 48000);
      for (var i = 0; i < 1000; i++) {
        m.next();
        expect(m.modulate(0, 0.5), 0);
      }
    });

    test('depth is a fraction of the base', () {
      final m = _mod(2, 48000);
      for (var i = 0; i < 100000; i++) {
        m.next();
        expect(m.modulate(2, 0.04), inInclusiveRange(2 * 0.96, 2 * 1.04));
      }
    });

    test('a depth above 1 acts as 1', () {
      final m = _mod(4, 48000);
      for (var i = 0; i < 1000; i++) {
        m.next();
        expect(m.modulate(2, 5), m.modulate(2, 1));
      }
    });
  });
}
