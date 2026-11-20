import 'package:fiatsonus_engine/src/primitives/panner.dart';
import 'package:test/test.dart';

void main() {
  test('hard left', () {
    expect(Panner.left(-1), 1);
    expect(Panner.right(-1), closeTo(0, 1e-12));
  });

  test('hard right', () {
    expect(Panner.left(1), closeTo(0, 1e-12));
    expect(Panner.right(1), closeTo(1, 1e-12));
  });

  test('centre is -3 dB on both sides', () {
    expect(Panner.left(0), closeTo(0.70711, 1e-5));
    expect(Panner.right(0), closeTo(0.70711, 1e-5));
  });

  test('constant power across 21 pans', () {
    for (var i = 0; i <= 20; i++) {
      final pan = -1 + i / 10;
      final l = Panner.left(pan);
      final r = Panner.right(pan);
      expect(l * l + r * r, closeTo(1, 1e-12), reason: 'pan $pan');
    }
  });

  test('pans beyond ±1 act as ±1 and NaN acts as -1', () {
    expect(Panner.left(-7), Panner.left(-1));
    expect(Panner.right(-7), Panner.right(-1));
    expect(Panner.left(7), Panner.left(1));
    expect(Panner.right(7), Panner.right(1));
    expect(Panner.left(double.nan), Panner.left(-1));
    expect(Panner.right(double.nan), Panner.right(-1));
  });
}
