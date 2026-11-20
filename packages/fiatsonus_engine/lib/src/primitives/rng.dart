const int _m = 0xFFFFFFFF;

/// Deterministic xoshiro128** generator using 32-bit operations only.
///
/// `dart:math` `Random` is never used in the engine (N9).
final class Rng {
  int _a = 0;
  int _b = 0;
  int _c = 0;
  int _d = 0;

  /// Seeds the four state words from [seed]; any int, including negative
  /// values and values above 2^32, is accepted.
  Rng(int seed) {
    var x = (seed ^ (seed >>> 32) ^ 0x9E3779B9) & _m;
    if (x == 0) x = 0x6C078965;
    x = _scramble(x);
    _a = x;
    x = _scramble(x);
    _b = x;
    x = _scramble(x);
    _c = x;
    x = _scramble(x);
    _d = x;
    for (var i = 0; i < 8; i++) {
      nextU32();
    }
  }

  static int _scramble(int x) {
    x ^= (x << 13) & _m;
    x ^= x >>> 17;
    x ^= (x << 5) & _m;
    return x;
  }

  /// Derives a 32-bit seed from [seed] and [salt] (`0 <= salt < 1 << 20`).
  static int mix(int seed, int salt) {
    final x = (((seed ^ (seed >>> 32)) & _m) + salt * 0x85EBCA6B) & _m;
    return _scramble(x == 0 ? 0x6C078965 : x);
  }

  /// Next value in `0..0xFFFFFFFF`.
  int nextU32() {
    final r0 = (_b * 5) & _m;
    final r1 = ((r0 << 7) | (r0 >>> 25)) & _m;
    final result = (r1 * 9) & _m;
    final t = (_b << 9) & _m;
    _c ^= _a;
    _d ^= _b;
    _b ^= _c;
    _a ^= _d;
    _c ^= t;
    _d = ((_d << 11) | (_d >>> 21)) & _m;
    return result;
  }

  /// Next value in `[0, 1)`.
  double nextDouble() => nextU32() * (1.0 / 4294967296.0);

  /// Next value in `[lo, hi)`.
  double range(double lo, double hi) => lo + (hi - lo) * nextDouble();
}
