import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/primitives/noise_table.dart';
import 'package:fiatsonus_engine/src/primitives/reverb.dart';
import 'package:test/test.dart';

const _rates = [44100, 48000];

/// Runs [reverb] over [inL]/[inR] in engine-sized blocks with a fixed send and
/// wet gain, and returns the wet output.
(Float32List, Float32List) _run(
  Reverb reverb,
  Float32List inL,
  Float32List inR, {
  double send = 1.0,
  double wet = 1.0,
}) {
  final n = inL.length;
  final outL = Float32List(n);
  final outR = Float32List(n);
  final bl = Float32List(kBlockFrames);
  final br = Float32List(kBlockFrames);
  final ol = Float32List(kBlockFrames);
  final or = Float32List(kBlockFrames);
  for (var start = 0; start < n; start += kBlockFrames) {
    final frames = start + kBlockFrames <= n ? kBlockFrames : n - start;
    bl.setRange(0, frames, inL, start);
    br.setRange(0, frames, inR, start);
    ol.fillRange(0, kBlockFrames, 0.0);
    or.fillRange(0, kBlockFrames, 0.0);
    reverb.process(bl, br, ol, or, frames, send, send, wet);
    outL.setRange(start, start + frames, ol);
    outR.setRange(start, start + frames, or);
  }
  return (outL, outR);
}

/// [seconds] of the white table of a fresh bank at [rate].
(Float32List, Float32List) _noise(int rate, double seconds) {
  final n = (seconds * rate).round();
  final l = Float32List(n);
  final r = Float32List(n);
  NoiseBank(rate, 7).white.read(l, r, 0, n, 1.0);
  return (l, r);
}

/// Schroeder decay time to −60 dB of the backward-integrated L² + R² energy.
double _t60(int rate) {
  final n = 6 * rate;
  final inL = Float32List(n)..[0] = 1.0;
  final inR = Float32List(n)..[0] = 1.0;
  final (l, r) = _run(Reverb()..prepare(rate), inL, inR);
  final tail = List<double>.filled(n + 1, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    tail[i] = tail[i + 1] + l[i] * l[i] + r[i] * r[i];
  }
  final limit = tail[0] * 1e-6;
  var i = 0;
  while (tail[i] > limit) {
    i++;
  }
  return i / rate;
}

double _power(Float32List buf, int start, [int? end]) {
  final e = end ?? buf.length;
  var sum = 0.0;
  for (var i = start; i < e; i++) {
    sum += buf[i] * buf[i];
  }
  return sum / (e - start);
}

void main() {
  test('impulse decay time is 1.0..1.8 s and agrees across rates', () {
    final t44 = _t60(44100);
    final t48 = _t60(48000);
    printOnFailure('T60 44100: $t44, 48000: $t48');
    expect(t44, inInclusiveRange(1.0, 1.8));
    expect(t48, inInclusiveRange(1.0, 1.8));
    expect((t44 - t48).abs() / t48, lessThan(0.1));
  });

  for (final rate in _rates) {
    group('at $rate Hz', () {
      test('steady white noise: wet +4 ±2 dB over mono input, '
          'L/R correlation below 0.2', () {
        final (inL, inR) = _noise(rate, 10);
        final (l, r) = _run(Reverb()..prepare(rate), inL, inR);
        final from = 5 * rate;
        final mono = Float32List(inL.length);
        for (var i = 0; i < mono.length; i++) {
          mono[i] = (inL[i] + inR[i]) * 0.5;
        }
        final wetPower = (_power(l, from) + _power(r, from)) * 0.5;
        final gainDb = 10 * math.log(wetPower / _power(mono, from)) / math.ln10;
        var lr = 0.0;
        for (var i = from; i < l.length; i++) {
          lr += l[i] * r[i];
        }
        final n = l.length - from;
        final corr = lr / (n * math.sqrt(_power(l, from) * _power(r, from)));
        printOnFailure('noise gain $gainDb dB, correlation $corr');
        expect(gainDb, closeTo(4.0, 2.0));
        expect(corr.abs(), lessThan(0.2));
      });

      test('wetGain is linear', () {
        final (inL, inR) = _noise(rate, 1);
        final (l1, r1) = _run(Reverb()..prepare(rate), inL, inR);
        final (lh, rh) = _run(Reverb()..prepare(rate), inL, inR, wet: 0.5);
        for (var i = 0; i < l1.length; i++) {
          expect(lh[i], closeTo(l1[i] * 0.5, 1e-6));
          expect(rh[i], closeTo(r1[i] * 0.5, 1e-6));
        }
      });

      test('send ramps per frame from send0 to send1', () {
        final (warmL, warmR) = _noise(rate, 0.5);
        final a = Reverb()..prepare(rate);
        final b = Reverb()..prepare(rate);
        _run(a, warmL, warmR);
        _run(b, warmL, warmR);

        const frames = kBlockFrames;
        final inL = Float32List.fromList(warmL.sublist(0, frames));
        final inR = Float32List.fromList(warmR.sublist(frames, 2 * frames));
        final preL = Float32List(frames);
        final preR = Float32List(frames);
        for (var i = 0; i < frames; i++) {
          final s = (i + 1) / frames;
          preL[i] = inL[i] * s;
          preR[i] = inR[i] * s;
        }
        final al = Float32List(frames);
        final ar = Float32List(frames);
        final bl = Float32List(frames);
        final br = Float32List(frames);
        a.process(inL, inR, al, ar, frames, 0.0, 1.0, 1.0);
        b.process(preL, preR, bl, br, frames, 1.0, 1.0, 1.0);
        for (var i = 0; i < frames; i++) {
          expect(al[i], closeTo(bl[i], 1e-6));
          expect(ar[i], closeTo(br[i], 1e-6));
        }
      });

      test('process adds into the outputs', () {
        final (inL, inR) = _noise(rate, 0.5);
        final a = Reverb()..prepare(rate);
        final b = Reverb()..prepare(rate);
        final al = Float32List(kBlockFrames);
        final ar = Float32List(kBlockFrames);
        final bl = Float32List(kBlockFrames);
        final br = Float32List(kBlockFrames);
        for (
          var start = 0;
          start + kBlockFrames <= inL.length;
          start += kBlockFrames
        ) {
          final l = Float32List.sublistView(inL, start, start + kBlockFrames);
          final r = Float32List.sublistView(inR, start, start + kBlockFrames);
          al.fillRange(0, kBlockFrames, 1.0);
          ar.fillRange(0, kBlockFrames, 1.0);
          bl.fillRange(0, kBlockFrames, 0.0);
          br.fillRange(0, kBlockFrames, 0.0);
          a.process(l, r, al, ar, kBlockFrames, 1.0, 1.0, 1.0);
          b.process(l, r, bl, br, kBlockFrames, 1.0, 1.0, 1.0);
          for (var i = 0; i < kBlockFrames; i++) {
            expect(al[i], closeTo(1.0 + bl[i], 1e-6));
            expect(ar[i], closeTo(1.0 + br[i], 1e-6));
          }
        }
      });

      test('S9: 15 s of silence after noise ends at exact zero', () {
        final reverb = Reverb()..prepare(rate);
        final (inL, inR) = _noise(rate, 2);
        _run(reverb, inL, inR);
        final silence = Float32List(15 * rate);
        final (l, r) = _run(reverb, silence, silence);
        expect(l.sublist(l.length - kBlockFrames), everyElement(0.0));
        expect(r.sublist(r.length - kBlockFrames), everyElement(0.0));
        expect(reverb.isQuiet, isTrue);
      });

      test('reset clears all memory at once', () {
        final reverb = Reverb()..prepare(rate);
        final (inL, inR) = _noise(rate, 1);
        _run(reverb, inL, inR);
        expect(reverb.isQuiet, isFalse);
        reverb.reset();
        expect(reverb.isQuiet, isTrue);
        final silence = Float32List(kBlockFrames);
        final (l, r) = _run(reverb, silence, silence);
        expect(l, everyElement(0.0));
        expect(r, everyElement(0.0));
      });

      for (final (rt60, damping) in [
        (0.0, 1.0),
        (0.0, 1e9),
        (1000.0, 1.0),
        (1000.0, 1e9),
      ]) {
        test('rt60 $rt60, damping $damping: finite and decaying', () {
          final reverb = Reverb(rt60Seconds: rt60, dampingHz: damping)
            ..prepare(rate);
          final (noiseL, noiseR) = _noise(rate, 0.5);
          final inL = Float32List(8 * rate)..setAll(0, noiseL);
          final inR = Float32List(8 * rate)..setAll(0, noiseR);
          final (l, r) = _run(reverb, inL, inR);
          var finite = true;
          for (var i = 0; i < l.length; i++) {
            finite = finite && l[i].isFinite && r[i].isFinite;
          }
          expect(finite, isTrue);
          final half = rate ~/ 2;
          final early = _power(l, half, rate) + _power(r, half, rate);
          final late = _power(l, 7 * rate) + _power(r, 7 * rate);
          expect(early, greaterThan(0.0));
          expect(late, lessThan(early));
        });
      }
    });
  }
}
