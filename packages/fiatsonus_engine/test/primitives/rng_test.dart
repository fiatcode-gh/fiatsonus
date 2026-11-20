import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

List<int> _first4(int seed) {
  final rng = Rng(seed);
  return [for (var i = 0; i < 4; i++) rng.nextU32()];
}

void main() {
  test('Rng(42) matches the known answers', () {
    expect(_first4(42), [983922534, 2916262695, 4062294755, 3079245895]);
  });

  test('Rng(0) matches the known answers', () {
    expect(_first4(0), [2441432831, 1186849926, 2868205254, 1349164908]);
  });

  test('mix matches the known answers', () {
    expect(Rng.mix(42, 1), 1805356521);
    expect(Rng.mix(42, 2), 3616202459);
    expect(Rng.mix(0, 0), 944216560);
    expect(Rng.mix(1 << 40, 7), 4054183050);
  });

  test('the same seed gives the same stream', () {
    final a = Rng(1234);
    final b = Rng(1234);
    for (var i = 0; i < 1000; i++) {
      expect(a.nextU32(), b.nextU32());
    }
  });

  test('seeds 1 and 2 differ in the first value', () {
    expect(Rng(1).nextU32(), isNot(Rng(2).nextU32()));
  });

  test('nextDouble stays in [0, 1) with mean 0.5', () {
    final rng = Rng(7);
    const n = 100000;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final x = rng.nextDouble();
      expect(x >= 0.0 && x < 1.0, isTrue, reason: 'draw $i = $x');
      sum += x;
    }
    expect(sum / n, closeTo(0.5, 0.01));
  });

  test('range stays inside its bounds', () {
    final rng = Rng(9);
    for (var i = 0; i < 10000; i++) {
      final x = rng.range(-3, 5);
      expect(x >= -3 && x < 5, isTrue, reason: 'draw $i = $x');
    }
  });

  test('negative and above-2^32 seeds produce 32-bit values', () {
    for (final seed in [-1, -987654321, (1 << 32) + 5, 1 << 50]) {
      final rng = Rng(seed);
      for (var i = 0; i < 100; i++) {
        final v = rng.nextU32();
        expect(v >= 0 && v <= 0xFFFFFFFF, isTrue, reason: 'seed $seed: $v');
      }
    }
  });
}
