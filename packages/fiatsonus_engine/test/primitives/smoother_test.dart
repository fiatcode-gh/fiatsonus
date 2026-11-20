import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/primitives/smoother.dart';
import 'package:test/test.dart';

int _blocks(double seconds, int rate) =>
    (seconds * rate / kBlockFrames).round();

void main() {
  test('starts at the initial value and is not moving', () {
    final s = Smoother(0.3);
    expect(s.value, 0.3);
    expect(s.target, 0.3);
    expect(s.isMoving, isFalse);
  });

  test('jumps to the target before prepare', () {
    final s = Smoother(0)..target = 0.7;
    expect(s.next(), 0.7);
    expect(s.isMoving, isFalse);
  });

  for (final rate in [44100, 48000]) {
    group('at $rate Hz', () {
      test(
        'a 200 ms step reaches 63 % after 200 ms, monotonic, no overshoot',
        () {
          final s = Smoother(0)
            ..prepare(rate, const Duration(milliseconds: 200))
            ..target = 1;
          expect(s.isMoving, isTrue);
          var previous = s.value;
          for (var i = 0; i < _blocks(0.2, rate); i++) {
            final v = s.next();
            expect(v, greaterThan(previous));
            expect(v, lessThanOrEqualTo(1.0));
            previous = v;
          }
          expect(s.value, closeTo(0.632, 0.03));
        },
      );

      test('snaps exactly to the target within 3 s', () {
        final s = Smoother(0)
          ..prepare(rate, const Duration(milliseconds: 200))
          ..target = 1;
        var previous = s.value;
        for (var i = 0; i < _blocks(3, rate); i++) {
          final v = s.next();
          expect(v, greaterThanOrEqualTo(previous));
          expect(v, lessThanOrEqualTo(1.0));
          previous = v;
        }
        expect(s.value, 1.0);
        expect(s.isMoving, isFalse);
      });

      test('a time constant below 1 ms behaves as 1 ms', () {
        final tiny = Smoother(0)
          ..prepare(rate, Duration.zero)
          ..target = 1;
        final oneMs = Smoother(0)
          ..prepare(rate, const Duration(milliseconds: 1))
          ..target = 1;
        final shortest = Smoother(0)
          ..prepare(rate, const Duration(microseconds: 10))
          ..target = 1;
        final a = tiny.next();
        expect(a, oneMs.next());
        expect(shortest.next(), a);
      });
    });
  }

  test('a NaN target is ignored', () {
    final s = Smoother(0.4)..prepare(48000, const Duration(milliseconds: 200));
    s.target = double.nan;
    expect(s.target, 0.4);
    expect(s.isMoving, isFalse);
    expect(s.next(), 0.4);
  });

  test('snap jumps to the target', () {
    final s = Smoother(0)
      ..prepare(48000, const Duration(seconds: 10))
      ..target = 0.9;
    s.next();
    expect(s.value, lessThan(0.9));
    s.snap();
    expect(s.value, 0.9);
    expect(s.isMoving, isFalse);
  });
}
