import 'dart:typed_data';

import 'package:fiatsonus_engine/src/primitives/dsp_math.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

/// The former body of `flushDenormal`, which the current one must equal.
double _flushReference(double x) => x.abs() < kDenormalFloor ? 0.0 : x;

final _bits = ByteData(8);

int _bitsOf(double x) {
  _bits.setFloat64(0, x);
  return _bits.getInt64(0);
}

double _fromBits(int b) {
  _bits.setInt64(0, b);
  return _bits.getFloat64(0);
}

/// The two doubles beside [x] (for 0.0 and −0.0, the smallest subnormals).
List<double> _beside(double x) {
  final b = _bitsOf(x);
  if (x == 0.0) return [double.minPositive, -double.minPositive];
  return [_fromBits(b + 1), _fromBits(b - 1)];
}

void _expectSameFlush(double x) {
  final expected = _flushReference(x);
  final actual = flushDenormal(x);
  final same = expected.isNaN
      ? actual.isNaN && _bitsOf(actual) == _bitsOf(expected)
      : _bitsOf(actual) == _bitsOf(expected);
  if (!same) fail('flushDenormal($x) = $actual, expected $expected');
}

void main() {
  test('kDenormalFloor is 1e-20', () {
    expect(kDenormalFloor, 1e-20);
  });

  group('clampD', () {
    test('clamps both sides and passes values inside', () {
      expect(clampD(-2.0, -1.0, 1.0), -1.0);
      expect(clampD(2.0, -1.0, 1.0), 1.0);
      expect(clampD(0.25, -1.0, 1.0), 0.25);
    });

    test('maps NaN to lo', () {
      expect(clampD(double.nan, 3.0, 5.0), 3.0);
    });

    test('maps infinities to the bounds', () {
      expect(clampD(double.infinity, 3.0, 5.0), 5.0);
      expect(clampD(double.negativeInfinity, 3.0, 5.0), 3.0);
    });
  });

  test('flushDenormal zeroes values below the floor only', () {
    expect(flushDenormal(1e-21), 0.0);
    expect(flushDenormal(-1e-21), 0.0);
    expect(flushDenormal(1e-19), 1e-19);
    expect(flushDenormal(-0.5), -0.5);
  });

  group('flushDenormal equals the abs() form bit for bit', () {
    test('at the floor, zeros, subnormals and the doubles beside them', () {
      for (final x in [
        kDenormalFloor,
        -kDenormalFloor,
        0.0,
        -0.0,
        double.minPositive,
        -double.minPositive,
        2.2250738585072014e-308,
        -2.2250738585072014e-308,
      ]) {
        _expectSameFlush(x);
        for (final y in _beside(x)) {
          _expectSameFlush(y);
          for (final z in _beside(y)) {
            _expectSameFlush(z);
          }
        }
      }
    });

    test('at NaN, the infinities and the largest doubles', () {
      for (final x in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        double.maxFinite,
        -double.maxFinite,
        1e300,
        -1e300,
        1e154,
        -1e154,
      ]) {
        _expectSameFlush(x);
      }
    });

    test('across every exponent with mantissas from Rng', () {
      final rng = Rng(20261123);
      for (var exponent = 0; exponent <= 2046; exponent++) {
        for (var i = 0; i < 40; i++) {
          final mantissa =
              ((rng.nextU32() << 20) ^ rng.nextU32()) & 0xFFFFFFFFFFFFF;
          final x = _fromBits((exponent << 52) | mantissa);
          _expectSameFlush(x);
          _expectSameFlush(-x);
        }
      }
    });

    test('at 100 000 values from Rng near the floor', () {
      final rng = Rng(42);
      for (var i = 0; i < 100000; i++) {
        _expectSameFlush(rng.range(-3e-20, 3e-20));
      }
    });
  });

  group('powD', () {
    test('clamps a negative base to zero instead of returning NaN', () {
      expect(powD(-0.5, 1.5), 0.0);
    });

    test('computes ordinary powers', () {
      expect(powD(2.0, 3.0), 8.0);
    });
  });

  group('dbToGain', () {
    test('-6.0206 dB is half', () {
      expect(dbToGain(-6.0206), closeTo(0.5, 1e-4));
    });

    test('0 dB is unity', () {
      expect(dbToGain(0), 1.0);
    });
  });
}
