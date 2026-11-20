import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fiatsonus_engine/offline.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

/// A 1 kHz stereo sine (same on both channels) with [peak] full scale.
Int16List _sine(int rate, double seconds, double peak) {
  final frames = (rate * seconds).round();
  final out = Int16List(frames * 2);
  final w = 2 * math.pi * 1000 / rate;
  for (var i = 0; i < frames; i++) {
    final s = (peak * 32767 * math.sin(w * i)).round();
    out[2 * i] = s;
    out[2 * i + 1] = s;
  }
  return out;
}

double _lufs(int rate, Int16List data) =>
    (LoudnessMeter(rate)..add(data, data.length ~/ 2)).lufs;

/// Stereo uniform noise in ±[amplitude], [frames] long.
Int16List _noise(int frames, int amplitude, {int seed = 7}) {
  final rng = Rng(seed);
  final out = Int16List(frames * 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = rng.range(-amplitude.toDouble(), amplitude.toDouble()).round();
  }
  return out;
}

void main() {
  final refPeak = math.pow(10, -23 / 20).toDouble();

  group('LoudnessMeter', () {
    for (final rate in [44100, 48000]) {
      test('1 kHz sine at -23 dBFS peak reads -23 LUFS at $rate', () {
        expect(_lufs(rate, _sine(rate, 20, refPeak)), closeTo(-23.0, 0.1));
      });

      test('6 dB lower sine reads 6 LU less at $rate', () {
        final a = _lufs(rate, _sine(rate, 20, refPeak));
        final b = _lufs(rate, _sine(rate, 20, refPeak / 2));
        expect(a - b, closeTo(6.0, 0.05));
      });
    }

    test('silence and no frames read -infinity', () {
      expect(LoudnessMeter(48000).lufs, double.negativeInfinity);
      expect(_lufs(48000, Int16List(48000 * 2)), double.negativeInfinity);
    });

    test('reset forgets earlier input', () {
      final m = LoudnessMeter(48000);
      final data = _sine(48000, 2, refPeak);
      m.add(data, data.length ~/ 2);
      m.reset();
      expect(m.lufs, double.negativeInfinity);
      final quiet = _sine(48000, 2, refPeak / 2);
      m.add(quiet, quiet.length ~/ 2);
      expect(m.lufs, closeTo(_lufs(48000, quiet), 1e-9));
    });

    test('two add calls equal one call on the concatenation', () {
      final data = _noise(48000, 5000);
      final whole = _lufs(48000, data);
      final split = LoudnessMeter(48000)
        ..add(Int16List.sublistView(data, 0, 30000), 15000)
        ..add(Int16List.sublistView(data, 30000), 33000);
      expect(split.lufs, closeTo(whole, 1e-9));
    });
  });

  group('peakAbs', () {
    test('a single -32768 reads 32768', () {
      final data = Int16List(8)..[5] = -32768;
      expect(peakAbs(data, 4), 32768);
    });

    test('respects frames', () {
      final data = Int16List(8)
        ..[1] = 100
        ..[6] = -2000;
      expect(peakAbs(data, 3), 100);
      expect(peakAbs(data, 4), 2000);
    });
  });

  group('dcOffset', () {
    test('constant 328 reads 0.01', () {
      final data = Int16List(2000)..fillRange(0, 2000, 328);
      expect(dcOffset(data, 1000, 0), closeTo(0.01, 1e-4));
    });

    test('reads the right channel', () {
      final data = Int16List(2000);
      for (var i = 1; i < 2000; i += 2) {
        data[i] = 328;
      }
      expect(dcOffset(data, 1000, 0), 0.0);
      expect(dcOffset(data, 1000, 1), closeTo(0.01, 1e-4));
    });
  });

  group('maxJumpZ', () {
    const frames = 5 * 48000;

    test('uniform noise scores below 4', () {
      expect(maxJumpZ(_noise(frames, 1000), frames), lessThan(4.0));
    });

    test('an added impulse scores above 12', () {
      final data = _noise(frames, 1000);
      data[2 * 100000] += 20000;
      expect(maxJumpZ(data, frames), greaterThan(12.0));
    });

    test('silence scores 0', () {
      expect(maxJumpZ(Int16List(frames * 2), frames), 0.0);
    });

    test('input shorter than the window scores 0', () {
      final data = _noise(1000, 1000);
      data[2 * 900] += 20000;
      expect(maxJumpZ(data, 1000), 0.0);
    });

    test('noise of ±1 LSB stays at or below the floor ratio', () {
      expect(maxJumpZ(_noise(frames, 1), frames), lessThanOrEqualTo(0.25));
    });

    test('an impulse in the right channel only is found', () {
      final data = Int16List(frames * 2);
      data[2 * 100000 + 1] = 20000;
      expect(maxJumpZ(data, frames), greaterThan(12.0));
    });
  });
}
