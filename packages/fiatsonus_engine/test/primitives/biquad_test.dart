import 'dart:typed_data';

import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/primitives/biquad.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

import '../support/signals.dart';

const _rates = [44100, 48000];

/// Gain in dB of [type] at [freq]/[q] for a sine of [hz], measured over the
/// second half of one second, processed in engine-sized blocks.
double _gainDb(BiquadType type, double freq, double q, double hz, int rate) {
  final input = sine(hz, rate, rate);
  final output = Float32List.fromList(input);
  final f = Biquad()
    ..prepare(rate)
    ..set(type, freq, q);
  for (var start = 0; start < rate; start += kBlockFrames) {
    final end = start + kBlockFrames < rate ? start + kBlockFrames : rate;
    f.processMono(output, start, end);
  }
  return ratioDb(rms(output, rate ~/ 2), rms(input, rate ~/ 2));
}

Float32List _noise(int seed, int frames) {
  final rng = Rng(seed);
  return Float32List(frames)
    ..setAll(0, [for (var i = 0; i < frames; i++) rng.range(-0.25, 0.25)]);
}

void main() {
  for (final rate in _rates) {
    group('at $rate Hz', () {
      group('low-pass 1000 Hz Q 0.7071', () {
        double g(double hz) =>
            _gainDb(BiquadType.lowPass, 1000, 0.7071, hz, rate);
        test('100 Hz passes', () => expect(g(100), closeTo(0, 0.1)));
        test('1000 Hz is -3 dB', () => expect(g(1000), closeTo(-3.01, 0.2)));
        test('10 kHz is cut', () => expect(g(10000), lessThanOrEqualTo(-38)));
      });

      group('high-pass 1000 Hz Q 0.7071', () {
        double g(double hz) =>
            _gainDb(BiquadType.highPass, 1000, 0.7071, hz, rate);
        test('10 kHz passes', () => expect(g(10000), closeTo(0, 0.2)));
        test('1000 Hz is -3 dB', () => expect(g(1000), closeTo(-3.01, 0.2)));
        test('100 Hz is -40 dB', () => expect(g(100), closeTo(-40, 1.5)));
      });

      group('band-pass 1000 Hz Q 1', () {
        double g(double hz) => _gainDb(BiquadType.bandPass, 1000, 1, hz, rate);
        test('1000 Hz peaks at 0 dB', () => expect(g(1000), closeTo(0, 0.1)));
        test('250 Hz is -11.9 dB', () => expect(g(250), closeTo(-11.9, 1.0)));
        test('4000 Hz is -11.9 dB', () => expect(g(4000), closeTo(-11.9, 1.0)));
      });

      test('set clamps frequency and Q', () {
        final f = Biquad()..prepare(rate);
        f.set(BiquadType.lowPass, 5, 0.01);
        expect(f.frequency, 20);
        expect(f.q, 0.1);
        f.set(BiquadType.lowPass, 1e9, 1e9);
        expect(f.frequency, 0.45 * rate);
        expect(f.q, 50);
        f.set(BiquadType.lowPass, double.nan, 1);
        expect(f.frequency, 20);
      });

      test('stays finite and bounded at Q 50 on both frequency extremes', () {
        for (final freq in [20.0, 0.45 * rate]) {
          final f = Biquad()
            ..prepare(rate)
            ..set(BiquadType.lowPass, freq, 50);
          final noise = _noise(5, 5 * rate);
          for (var start = 0; start < noise.length; start += kBlockFrames) {
            final end = start + kBlockFrames < noise.length
                ? start + kBlockFrames
                : noise.length;
            f.processMono(noise, start, end);
          }
          for (var i = 0; i < noise.length; i++) {
            final y = noise[i];
            expect(y.isFinite && y.abs() < 1000, isTrue, reason: '$freq: $y');
          }
        }
      });

      test('S9: an impulse decays to exact zeros', () {
        final f = Biquad()
          ..prepare(rate)
          ..set(BiquadType.lowPass, 200, 0.7071);
        final l = Float32List(kBlockFrames);
        final r = Float32List(kBlockFrames);
        l[0] = 1.0;
        r[0] = 1.0;
        f.processStereo(l, r, kBlockFrames);
        var quietBlock = -1;
        final limit = 2 * rate ~/ kBlockFrames;
        for (var block = 1; block <= limit; block++) {
          l.fillRange(0, kBlockFrames, 0.0);
          r.fillRange(0, kBlockFrames, 0.0);
          f.processStereo(l, r, kBlockFrames);
          if (f.isQuiet) {
            quietBlock = block;
            break;
          }
        }
        expect(quietBlock, isNot(-1), reason: 'not quiet within 2 s');
        for (var block = 0; block < 100; block++) {
          l.fillRange(0, kBlockFrames, 0.0);
          r.fillRange(0, kBlockFrames, 0.0);
          f.processStereo(l, r, kBlockFrames);
          expect(l, everyElement(0.0));
          expect(r, everyElement(0.0));
          expect(f.isQuiet, isTrue);
        }
      });
    });
  }

  test('updateCount rises only when type, frequency or Q changes', () {
    final f = Biquad()..prepare(48000);
    expect(f.updateCount, 0);
    f.set(BiquadType.lowPass, 1000, 1);
    expect(f.updateCount, 1);
    for (var i = 0; i < 100; i++) {
      f.set(BiquadType.lowPass, 1000, 1);
    }
    expect(f.updateCount, 1);
    f.set(BiquadType.highPass, 1000, 1);
    expect(f.updateCount, 2);
    f.set(BiquadType.highPass, 1100, 1);
    expect(f.updateCount, 3);
    f.set(BiquadType.highPass, 1100, 2);
    expect(f.updateCount, 4);
    // Both clamp to 20 Hz, so the stored values do not change.
    f.set(BiquadType.highPass, 1, 2);
    f.set(BiquadType.highPass, 5, 2);
    expect(f.updateCount, 5);
  });

  test('is a passthrough before the first set', () {
    final input = _noise(3, 512);
    final buf = Float32List.fromList(input);
    Biquad().processMono(buf, 0, 512);
    expect(buf, input);

    final l = Float32List.fromList(input);
    final r = Float32List.fromList(input);
    (Biquad()..prepare(48000)).processStereo(l, r, 512);
    expect(l, input);
    expect(r, input);
  });

  test('prepare restores passthrough after a set', () {
    final f = Biquad()
      ..prepare(48000)
      ..set(BiquadType.lowPass, 200, 1);
    final warm = _noise(4, 256);
    f.processMono(warm, 0, 256);
    f.prepare(48000);
    expect(f.isQuiet, isTrue);
    final input = _noise(3, 256);
    final buf = Float32List.fromList(input);
    f.processMono(buf, 0, 256);
    expect(buf, input);
  });

  test('stereo processing equals two independent mono filters', () {
    final a = _noise(10, 1024);
    final b = sine(440, 48000, 1024);
    final stereo = Biquad()
      ..prepare(48000)
      ..set(BiquadType.bandPass, 800, 2);
    final monoL = Biquad()
      ..prepare(48000)
      ..set(BiquadType.bandPass, 800, 2);
    final monoR = Biquad()
      ..prepare(48000)
      ..set(BiquadType.bandPass, 800, 2);
    final l = Float32List.fromList(a);
    final r = Float32List.fromList(b);
    stereo.processStereo(l, r, 1024);
    final ml = Float32List.fromList(a);
    final mr = Float32List.fromList(b);
    monoL.processMono(ml, 0, 1024);
    monoR.processMono(mr, 0, 1024);
    expect(l, ml);
    expect(r, mr);
  });

  test('one 1024-frame call equals four 256-frame calls', () {
    final a = _noise(11, 1024);
    final b = _noise(12, 1024);
    final whole = Biquad()
      ..prepare(44100)
      ..set(BiquadType.highPass, 300, 0.9);
    final chunked = Biquad()
      ..prepare(44100)
      ..set(BiquadType.highPass, 300, 0.9);
    final wl = Float32List.fromList(a);
    final wr = Float32List.fromList(b);
    whole.processStereo(wl, wr, 1024);

    final cl = Float32List.fromList(a);
    final cr = Float32List.fromList(b);
    for (var start = 0; start < 1024; start += 256) {
      final l = Float32List.sublistView(cl, start, start + 256);
      final r = Float32List.sublistView(cr, start, start + 256);
      chunked.processStereo(l, r, 256);
    }
    expect(cl, wl);
    expect(cr, wr);

    final mono = Biquad()
      ..prepare(44100)
      ..set(BiquadType.highPass, 300, 0.9);
    final m = Float32List.fromList(a);
    for (var start = 0; start < 1024; start += 256) {
      mono.processMono(m, start, start + 256);
    }
    expect(m, wl);
  });

  test('reset makes the filter quiet', () {
    final f = Biquad()
      ..prepare(48000)
      ..set(BiquadType.lowPass, 500, 1);
    final l = _noise(1, 256);
    final r = _noise(2, 256);
    f.processStereo(l, r, 256);
    expect(f.isQuiet, isFalse);
    f.reset();
    expect(f.isQuiet, isTrue);
  });
}
