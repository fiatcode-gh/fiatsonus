import 'dart:typed_data';

import 'package:fiatsonus_engine/src/primitives/block_ops.dart';
import 'package:test/test.dart';

void main() {
  test('clearBlock zeroes only the first frames samples', () {
    final buf = Float32List(8)..fillRange(0, 8, 1.0);
    clearBlock(buf, 5);
    expect(buf.sublist(0, 5), everyElement(0.0));
    expect(buf.sublist(5), everyElement(1.0));
  });

  group('addRamp', () {
    test('adds into dst and reaches g1 on the last frame', () {
      const frames = 256;
      final src = Float32List(frames)..fillRange(0, frames, 1.0);
      final dst = Float32List(frames)..fillRange(0, frames, 0.5);
      addRamp(src, dst, frames, 0.0, 1.0);
      expect(dst[frames - 1] - 0.5, closeTo(1.0, 1e-6));
      expect(dst[0] - 0.5, closeTo(1.0 / frames, 1e-6));
      for (var i = 1; i < frames; i++) {
        expect(dst[i], greaterThan(dst[i - 1]));
      }
    });

    test('with g0 == g1 scales by a constant', () {
      final src = Float32List.fromList([1.0, -2.0, 0.5, 4.0]);
      final dst = Float32List(4);
      addRamp(src, dst, 4, 0.25, 0.25);
      expect(dst, [0.25, -0.5, 0.125, 1.0]);
    });

    test('touches only the first frames samples', () {
      final src = Float32List(4)..fillRange(0, 4, 1.0);
      final dst = Float32List(4);
      addRamp(src, dst, 2, 1.0, 1.0);
      expect(dst, [1.0, 1.0, 0.0, 0.0]);
    });
  });
}
