import 'package:fiatsonus_engine/src/primitives/dsp_math.dart';
import 'package:test/test.dart';

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
