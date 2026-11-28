import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/primitives/biquad.dart';
import 'package:fiatsonus_engine/src/primitives/noise_table.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

import '../support/signals.dart';

const _rates = [44100, 48000];

const _seconds = {
  NoiseColor.white: 4.37,
  NoiseColor.pink: 5.23,
  NoiseColor.brown: 5.81,
};

const _colourDb = {
  NoiseColor.white: 8.2,
  NoiseColor.pink: -0.25,
  NoiseColor.brown: -8.1,
};

NoiseTable _table(NoiseBank bank, NoiseColor color) => switch (color) {
  NoiseColor.white => bank.white,
  NoiseColor.pink => bank.pink,
  NoiseColor.brown => bank.brown,
};

double _mean(Float32List buf) {
  var sum = 0.0;
  for (var i = 0; i < buf.length; i++) {
    sum += buf[i];
  }
  return sum / buf.length;
}

double _correlation(Float32List a, Float32List b) {
  final ma = _mean(a), mb = _mean(b);
  var ab = 0.0, aa = 0.0, bb = 0.0;
  for (var i = 0; i < a.length; i++) {
    final da = a[i] - ma, db = b[i] - mb;
    ab += da * db;
    aa += da * da;
    bb += db * db;
  }
  return ab / math.sqrt(aa * bb);
}

/// RMS of the first difference `buf[i] - buf[i - 1]` over the table.
double _rmsDelta(Float32List buf) {
  var sum = 0.0;
  for (var i = 1; i < buf.length; i++) {
    final d = buf[i] - buf[i - 1];
    sum += d * d;
  }
  return math.sqrt(sum / (buf.length - 1));
}

/// Level of [buf] through a band-pass at [hz] (Q 1.414), skipping one second.
double _bandLevel(Float32List buf, int rate, double hz) {
  final out = Float32List.fromList(buf);
  (Biquad()
        ..prepare(rate)
        ..set(BiquadType.bandPass, hz, 1.414))
      .processMono(out, 0, out.length);
  return rms(out, rate);
}

Float32List _ramp(int length, double offset) =>
    Float32List.fromList([for (var i = 0; i < length; i++) offset + i]);

Float32List _filled(int size, Rng rng) => Float32List.fromList([
  for (var i = 0; i < size; i++) rng.nextU32() / 4294967296.0,
]);

Uint32List _bits(Float32List buf) => Uint32List.sublistView(buf);

/// The per-frame loop `NoiseTable.read` (add: false) and `mix` (add: true)
/// used before the split at the wrap point.
int _refRead(
  NoiseTable t,
  Float32List outL,
  Float32List outR,
  int pos,
  int frames,
  double gain, {
  required bool add,
}) {
  final l = t.left, r = t.right, n = l.length;
  for (var i = 0; i < frames; i++) {
    if (add) {
      outL[i] += l[pos] * gain;
      outR[i] += r[pos] * gain;
    } else {
      outL[i] = l[pos] * gain;
      outR[i] = r[pos] * gain;
    }
    if (++pos == n) pos = 0;
  }
  return pos;
}

/// The per-frame loop `NoiseTable.readMono` used before the split.
int _refReadMono(
  NoiseTable t,
  Float32List out,
  int channel,
  int pos,
  int start,
  int end,
) {
  final src = channel == 0 ? t.left : t.right;
  final n = src.length;
  for (var i = start; i < end; i++) {
    out[i] = src[pos];
    if (++pos == n) pos = 0;
  }
  return pos;
}

void main() {
  for (final rate in _rates) {
    group('at $rate Hz', () {
      final bank = NoiseBank(rate, 1);

      test('lengths follow the per-colour seconds', () {
        final lengths = <int>{};
        for (final color in NoiseColor.values) {
          final t = _table(bank, color);
          expect(t.length, (_seconds[color]! * rate).round(), reason: '$color');
          expect(t.left.length, t.length);
          expect(t.right.length, t.length);
          expect(t.length, greaterThan(4 * rate));
          expect(t.length, lessThan(6 * rate));
          lengths.add(t.length);
        }
        expect(lengths, hasLength(3));
      });

      test('every channel is normalised, centred, finite and bounded', () {
        for (final color in NoiseColor.values) {
          final t = _table(bank, color);
          for (final ch in [t.left, t.right]) {
            expect(rms(ch), closeTo(0.25, 0.001), reason: '$color rms');
            expect(_mean(ch).abs(), lessThan(1e-6), reason: '$color mean');
            var peak = 0.0;
            for (var i = 0; i < ch.length; i++) {
              expect(ch[i].isFinite, isTrue, reason: '$color[$i]');
              final a = ch[i].abs();
              if (a > peak) peak = a;
            }
            expect(peak, lessThan(1.5), reason: '$color peak');
          }
        }
      });

      test('left and right are decorrelated', () {
        for (final color in NoiseColor.values) {
          final t = _table(bank, color);
          expect(
            _correlation(t.left, t.right).abs(),
            lessThan(0.05),
            reason: '$color',
          );
        }
      });

      test('the loop seam is no larger than ordinary sample steps', () {
        for (final color in NoiseColor.values) {
          final t = _table(bank, color);
          for (final ch in [t.left, t.right]) {
            final seam = (ch[0] - ch[t.length - 1]).abs();
            final delta = _rmsDelta(ch);
            printOnFailure('$rate $color seam/rmsDelta ${seam / delta}');
            expect(seam, lessThanOrEqualTo(6 * delta), reason: '$color');
          }
        }
      });

      test('spectral tilt matches the colour', () {
        for (final color in NoiseColor.values) {
          final ch = _table(bank, color).left;
          final db = ratioDb(
            _bandLevel(ch, rate, 4000),
            _bandLevel(ch, rate, 500),
          );
          printOnFailure('$rate $color tilt $db dB');
          expect(db, closeTo(_colourDb[color]!, 1.5), reason: '$color');
        }
      });
    });
  }

  group('determinism', () {
    test('the same seed builds identical tables; another seed differs', () {
      final a = NoiseBank(48000, 1);
      final b = NoiseBank(48000, 1);
      final c = NoiseBank(48000, 2);
      for (final color in NoiseColor.values) {
        final ta = _table(a, color), tb = _table(b, color);
        final tc = _table(c, color);
        expect(tb.left, equals(ta.left), reason: '$color left');
        expect(tb.right, equals(ta.right), reason: '$color right');
        expect(tc.left, isNot(equals(ta.left)), reason: '$color left');
        expect(tc.right, isNot(equals(ta.right)), reason: '$color right');
      }
    });
  });

  group('reading', () {
    const length = 1000;
    final table = NoiseTable.fromChannels(
      _ramp(length, 0),
      _ramp(length, 10000),
    );

    test('read overwrites with gain and wraps across calls', () {
      const total = length + 10;
      final outL = Float32List(kBlockFrames);
      final outR = Float32List(kBlockFrames);
      var pos = length - 5;
      var done = 0;
      while (done < total) {
        final frames = total - done < kBlockFrames
            ? total - done
            : kBlockFrames;
        outL.fillRange(0, kBlockFrames, 99);
        outR.fillRange(0, kBlockFrames, 99);
        pos = table.read(outL, outR, pos, frames, 0.5);
        for (var i = 0; i < frames; i++) {
          final src = (length - 5 + done + i) % length;
          expect(outL[i], 0.5 * src, reason: 'left ${done + i}');
          expect(outR[i], 0.5 * (10000 + src), reason: 'right ${done + i}');
        }
        for (var i = frames; i < kBlockFrames; i++) {
          expect(outL[i], 99, reason: 'untouched left $i');
        }
        done += frames;
      }
      expect(pos, (length - 5 + total) % length);
    });

    test('mix adds on top of existing content', () {
      final outL = Float32List(8)..fillRange(0, 8, 1);
      final outR = Float32List(8)..fillRange(0, 8, 2);
      final next = table.mix(outL, outR, length - 2, 4, 2.0);
      expect(next, 2);
      expect(outL.sublist(0, 4), [
        1 + 2.0 * (length - 2),
        1 + 2.0 * (length - 1),
        1.0,
        3.0,
      ]);
      expect(outR.sublist(0, 4), [
        2 + 2.0 * (10000 + length - 2),
        2 + 2.0 * (10000 + length - 1),
        2 + 2.0 * 10000,
        2 + 2.0 * 10001,
      ]);
      expect(outL.sublist(4), [1, 1, 1, 1]);
      expect(outR.sublist(4), [2, 2, 2, 2]);
    });

    test('readMono writes only out[start..end) from the chosen channel', () {
      final out = Float32List(10)..fillRange(0, 10, -1);
      final next = table.readMono(out, 1, length - 1, 3, 6);
      expect(next, 2);
      expect(out, [
        -1,
        -1,
        -1,
        10000.0 + length - 1,
        10000,
        10001,
        -1,
        -1,
        -1,
        -1,
      ]);
      final left = Float32List(4);
      expect(table.readMono(left, 0, 7, 0, 4), 11);
      expect(left, [7, 8, 9, 10]);
    });

    test(
      'read, mix and readMono equal the per-frame wrap loop bit for bit',
      () {
        final rng = Rng(5);
        for (final n in [1, 2, 7, 300]) {
          final left = Float32List(n), right = Float32List(n);
          for (var k = 0; k < n; k++) {
            left[k] = rng.nextU32() / 4294967296.0 - 0.5;
            right[k] = rng.nextU32() / 4294967296.0 - 0.5;
          }
          final t = NoiseTable.fromChannels(left, right);
          const size = 1000;
          for (final pos in {
            0,
            1,
            n ~/ 2,
            n - 2,
            n - 1,
          }.where((p) => p >= 0 && p < n)) {
            for (final frames in {0, 1, 2, n - pos, n - pos + 1, 3 * n + 2}) {
              final reason = 'n=$n pos=$pos frames=$frames';
              final gotL = _filled(size, rng), gotR = _filled(size, rng);
              final refL = Float32List.fromList(gotL);
              final refR = Float32List.fromList(gotR);

              var next = t.read(gotL, gotR, pos, frames, 0.37);
              var refNext = _refRead(
                t,
                refL,
                refR,
                pos,
                frames,
                0.37,
                add: false,
              );
              expect(next, refNext, reason: 'read $reason');
              expect(_bits(gotL), _bits(refL), reason: 'read L $reason');
              expect(_bits(gotR), _bits(refR), reason: 'read R $reason');

              next = t.mix(gotL, gotR, pos, frames, -1.7);
              refNext = _refRead(t, refL, refR, pos, frames, -1.7, add: true);
              expect(next, refNext, reason: 'mix $reason');
              expect(_bits(gotL), _bits(refL), reason: 'mix L $reason');
              expect(_bits(gotR), _bits(refR), reason: 'mix R $reason');

              for (final channel in [0, 1]) {
                const start = 5;
                next = t.readMono(gotL, channel, pos, start, start + frames);
                refNext = _refReadMono(
                  t,
                  refL,
                  channel,
                  pos,
                  start,
                  start + frames,
                );
                expect(next, refNext, reason: 'readMono $channel $reason');
                expect(_bits(gotL), _bits(refL), reason: 'readMono $reason');
              }
            }
          }
        }
      },
    );

    test('a position outside the table is a RangeError when frames > 0', () {
      final outL = Float32List(4), outR = Float32List(4);
      for (final pos in [-1, length, length + 3]) {
        expect(() => table.read(outL, outR, pos, 1, 1.0), throwsRangeError);
        expect(() => table.mix(outL, outR, pos, 1, 1.0), throwsRangeError);
        expect(() => table.readMono(outL, 0, pos, 0, 1), throwsRangeError);
        expect(table.read(outL, outR, pos, 0, 1.0), pos);
        expect(table.mix(outL, outR, pos, 0, 1.0), pos);
        expect(table.readMono(outL, 0, pos, 2, 2), pos);
      }
    });

    test('an output shorter than the frames is a RangeError', () {
      final short = Float32List(3), long = Float32List(8);
      expect(() => table.read(short, long, 0, 4, 1.0), throwsRangeError);
      expect(() => table.read(long, short, 0, 4, 1.0), throwsRangeError);
      expect(() => table.mix(short, long, 0, 4, 1.0), throwsRangeError);
      expect(() => table.mix(long, short, 0, 4, 1.0), throwsRangeError);
      expect(() => table.readMono(short, 1, 0, 1, 4), throwsRangeError);
      expect(() => table.readMono(long, 1, 0, -1, 4), throwsRangeError);
    });
  });

  group('fromChannels', () {
    test('rejects unequal lengths', () {
      expect(
        () => NoiseTable.fromChannels(Float32List(3), Float32List(4)),
        throwsArgumentError,
      );
    });

    test('rejects empty channels', () {
      expect(
        () => NoiseTable.fromChannels(Float32List(0), Float32List(0)),
        throwsArgumentError,
      );
    });

    test('keeps the given lists', () {
      final l = Float32List(4), r = Float32List(4);
      final t = NoiseTable.fromChannels(l, r);
      expect(identical(t.left, l), isTrue);
      expect(identical(t.right, r), isTrue);
    });
  });
}
