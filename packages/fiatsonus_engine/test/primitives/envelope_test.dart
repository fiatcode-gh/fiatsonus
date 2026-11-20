import 'dart:typed_data';

import 'package:fiatsonus_engine/src/primitives/envelope.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

Float32List _ones(int frames) => Float32List(frames)..fillRange(0, frames, 1.0);

/// Multiplies a buffer of ones of [frames] frames by [env] in one call.
Float32List _run(Envelope env, int frames) {
  final buf = _ones(frames);
  env.process(buf, 0, frames);
  return buf;
}

void main() {
  for (final rate in [44100, 48000]) {
    group('at $rate Hz', () {
      Envelope env() => Envelope()..prepare(rate);

      test('a linear segment ramps evenly, then zeros and done', () {
        final n = (0.002 * rate).round();
        final e = env()
          ..begin(0)
          ..lineTo(1, 0.002);
        expect(e.remainingFrames, n);
        final out = _run(e, n + 50);
        for (var i = 0; i < n; i++) {
          expect(out[i], closeTo((i + 1) / n, 1e-6), reason: 'frame $i');
        }
        expect(out.sublist(n), everyElement(0.0));
        expect(e.isDone, isTrue);
        expect(e.value, 0);
      });

      test('an exponential segment has a constant ratio', () {
        final n = (0.01 * rate).round();
        final e = env()
          ..begin(1)
          ..expTo(0.0001, 0.01);
        expect(e.remainingFrames, n);
        // One frame at a time, so the ratio is read from the double value
        // rather than the Float32 buffer.
        final values = <double>[];
        final one = Float32List(1);
        for (var i = 0; i < n - 1; i++) {
          one[0] = 1.0;
          e.process(one, 0, 1);
          values.add(e.value);
        }
        final ratio = values[1] / values[0];
        for (var i = 1; i < values.length; i++) {
          expect(values[i] / values[i - 1], closeTo(ratio, 1e-9 * ratio));
        }
        final tail = _run(e, 20);
        expect(tail[0], closeTo(1e-4, 1e-6));
        expect(tail.sublist(1), everyElement(0.0));
        expect(e.isDone, isTrue);
      });

      test('attack then decay peaks at the level and ends on time', () {
        final a = (0.002 * rate).round();
        final d = (0.02 * rate).round();
        final e = env()
          ..begin(0)
          ..lineTo(0.8, 0.002)
          ..expTo(0.8 * 0.0001, 0.02);
        final out = _run(e, a + d + 100);
        var peak = 0;
        for (var i = 1; i < out.length; i++) {
          if (out[i] > out[peak]) peak = i;
        }
        expect(peak, a - 1);
        expect(out[peak], closeTo(0.8, 1e-6));
        expect(out[a + d - 1], greaterThan(0));
        expect(out.sublist(a + d), everyElement(0.0));
      });

      test('expTo after a zero start begins at the floor', () {
        final n = (0.01 * rate).round();
        final e = env()
          ..begin(0)
          ..expTo(0.5, 0.01);
        final values = <double>[];
        final one = Float32List(1);
        for (var i = 0; i < n; i++) {
          one[0] = 1.0;
          e.process(one, 0, 1);
          expect(one[0].isFinite, isTrue);
          expect(one[0], greaterThan(0));
          values.add(one[0]);
        }
        expect(values.first, greaterThan(Envelope.floor));
        expect(values.first, lessThan(Envelope.floor * 1.1));
        expect(values.last, closeTo(0.5, 1e-5));
        expect(e.isDone, isTrue);
      });

      test('seconds == 0 gives a 1-frame segment', () {
        final e = env()
          ..begin(0)
          ..lineTo(0.5, 0);
        expect(e.remainingFrames, 1);
        final out = _run(e, 3);
        expect(out, [0.5, 0.0, 0.0]);
      });
    });
  }

  Envelope env() => Envelope()..prepare(48000);

  test('chunked processing equals one call exactly', () {
    void shape(Envelope e) => e
      ..begin(0.1)
      ..lineTo(1, 0.003)
      ..expTo(0.2, 0.01)
      ..lineTo(0.6, 0.004)
      ..expTo(0.00001, 0.02);
    final whole = env();
    shape(whole);
    final total = whole.remainingFrames + 40;
    final expected = _run(whole, total);

    final chunked = env();
    shape(chunked);
    final buf = _ones(total);
    for (var start = 0; start < total; start += 7) {
      final end = start + 7 < total ? start + 7 : total;
      chunked.process(buf, start, end);
    }
    expect(buf, expected);
  });

  test('remainingFrames counts down to 0', () {
    final e = env()
      ..begin(0)
      ..lineTo(1, 0.001)
      ..expTo(0.001, 0.002);
    var left = e.remainingFrames;
    expect(left, 48 + 96);
    final buf = _ones(10);
    while (!e.isDone) {
      e.process(buf, 0, 10);
      final now = e.remainingFrames;
      expect(now, left - 10 < 0 ? 0 : left - 10);
      left = now;
    }
    expect(e.remainingFrames, 0);
  });

  test('no segments is done immediately and zeros the buffer', () {
    final fresh = env();
    expect(fresh.isDone, isTrue);
    expect(_run(fresh, 8), everyElement(0.0));

    final begun = env()..begin(0.7);
    expect(begun.isDone, isTrue);
    expect(begun.remainingFrames, 0);
    expect(_run(begun, 8), everyElement(0.0));
  });

  test('a fifth segment is ignored', () {
    final e = env()..begin(0);
    for (var i = 0; i < 5; i++) {
      e.lineTo(i.isEven ? 1 : 0, 0.001);
    }
    expect(e.remainingFrames, 4 * 48);
    e.expTo(0.5, 0.001);
    expect(e.remainingFrames, 4 * 48);
  });

  test('targets and times are clamped', () {
    final e = env()
      ..begin(9)
      ..lineTo(double.nan, double.nan)
      ..expTo(100, -3);
    expect(e.value, 4);
    expect(e.remainingFrames, 2);
    final out = _run(e, 2);
    expect(out[0], 0);
    expect(out[1], closeTo(4, 1e-6));
  });

  test('reset ends the envelope', () {
    final e = env()
      ..begin(0)
      ..lineTo(1, 0.1);
    _run(e, 100);
    e.reset();
    expect(e.isDone, isTrue);
    expect(e.value, 0);
    expect(e.remainingFrames, 0);
    expect(_run(e, 8), everyElement(0.0));
  });

  test('S7: random envelopes always end on zeros', () {
    final rng = Rng(9);
    for (var n = 0; n < 100; n++) {
      final e = env()..begin(rng.nextDouble());
      final segments = 1 + rng.nextU32() % 4;
      for (var s = 0; s < segments; s++) {
        final target = rng.range(0, 1.5);
        final seconds = rng.range(0, 0.05);
        if (rng.nextU32().isEven) {
          e.lineTo(target, seconds);
        } else {
          e.expTo(target, seconds);
        }
      }
      final frames = e.remainingFrames;
      final buf = _ones(frames + 300);
      for (var start = 0; start < buf.length; start += 256) {
        final end = start + 256 < buf.length ? start + 256 : buf.length;
        e.process(buf, start, end);
      }
      expect(e.isDone, isTrue, reason: 'envelope $n');
      expect(e.value, 0, reason: 'envelope $n');
      for (final v in buf) {
        expect(v.isFinite, isTrue, reason: 'envelope $n');
      }
      var lastNonZero = -1;
      for (var i = 0; i < buf.length; i++) {
        if (buf[i] != 0) lastNonZero = i;
      }
      expect(lastNonZero, lessThan(frames), reason: 'envelope $n');
      expect(buf.sublist(frames), everyElement(0.0), reason: 'envelope $n');
    }
  });
}
