import 'dart:typed_data';

import 'package:fiatsonus_engine/src/master/master.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

import '../support/fake_soundscape.dart';

const _rate = 48000;

/// 576 blocks: past the 2 s fade-in and a whole number of blocks, so the next
/// control call takes effect on the next rendered frame.
const _full = 576 * 256;

/// Renders [frames] frames in calls of at most [chunk] frames.
Int16List _take(Master m, int frames, [int chunk = 4096]) {
  final out = Int16List(frames * 2);
  var done = 0;
  while (done < frames) {
    final n = frames - done < chunk ? frames - done : chunk;
    final buf = Int16List(n * 2);
    m.render(buf, n);
    out.setAll(done * 2, buf);
    done += n;
  }
  return out;
}

/// Left-channel sample of frame [n].
int _l(Int16List out, int n) => out[n * 2];

int _fadeIn(double level, int n, int fadeFrames) {
  final u = (n + 1) / fadeFrames < 1.0 ? (n + 1) / fadeFrames : 1.0;
  return (level * u * u * 32767).round();
}

int _maxNeighbourJump(Int16List out) {
  var worst = 0;
  for (var i = 2; i < out.length; i++) {
    final d = (out[i] - out[i - 2]).abs();
    if (d > worst) worst = d;
  }
  return worst;
}

(Master, FakeSoundscape) _setup({
  int rate = _rate,
  double level = 0.25,
  double gain = 1.0,
}) {
  final m = Master(sampleRate: rate, seed: 1);
  final f = FakeSoundscape(left: level, right: level);
  m.add(f, gain: gain);
  return (m, f);
}

void main() {
  test('is silent before start and never renders the soundscape', () {
    final (m, f) = _setup();
    final out = _take(m, _rate);
    expect(out.every((s) => s == 0), isTrue);
    expect(m.isSilent, isTrue);
    expect(f.renderCount, 0);
  });

  test('fades in by the squared-linear law over 2 s', () {
    final (m, _) = _setup();
    expect(m.start('fake'), isTrue);
    expect(m.isSilent, isFalse);
    final out = _take(m, 3 * _rate);
    for (var n = 0; n < 3 * _rate; n++) {
      final expected = _fadeIn(0.25, n, 2 * _rate);
      expect((_l(out, n) - expected).abs(), lessThanOrEqualTo(1), reason: '$n');
      expect(out[n * 2 + 1], _l(out, n));
      if (n > 0) expect(_l(out, n), greaterThanOrEqualTo(_l(out, n - 1)));
      if (n >= 2 * _rate) expect(_l(out, n), 8192);
    }
  });

  test('fades out to exactly zero in 3 s and stops rendering', () {
    final (m, f) = _setup();
    m.start('fake');
    _take(m, _full);
    expect(m.stop('fake'), isTrue);
    expect(m.isSilent, isFalse);
    final out = _take(m, 4 * _rate);
    for (var n = 1; n < 4 * _rate; n++) {
      expect(_l(out, n), lessThanOrEqualTo(_l(out, n - 1)), reason: '$n');
    }
    for (var n = 3 * _rate - 1; n < 4 * _rate; n++) {
      expect(_l(out, n), 0, reason: '$n');
    }
    expect(m.isSilent, isTrue);
    final rendered = f.renderCount;
    _take(m, _rate);
    expect(f.renderCount, rendered);
    expect(m.stop('fake'), isTrue);
    expect(m.isSilent, isTrue);
  });

  test('a reversed fade continues from the current level', () {
    final (m, _) = _setup();
    m.start('fake');
    final a = _take(m, 3 * _rate);
    m.stop('fake');
    final b = _take(m, _rate ~/ 10);
    m.start('fake');
    final c = _take(m, 3 * _rate);
    final all = Int16List.fromList([...a, ...b, ...c]);
    expect(_maxNeighbourJump(all), lessThanOrEqualTo(2));

    final last = _l(b, b.length ~/ 2 - 1);
    expect(last, lessThan(8192));
    var minAt = 0;
    for (var n = 1; n < c.length ~/ 2; n++) {
      if (_l(c, n) < _l(c, minAt)) minAt = n;
    }
    expect(minAt, lessThan(256));
    expect(_l(c, minAt), greaterThan(7000));
    for (var n = minAt + 1; n < c.length ~/ 2; n++) {
      expect(_l(c, n), greaterThanOrEqualTo(_l(c, n - 1)));
    }
    expect(_l(c, c.length ~/ 2 - 1), 8192);
  });

  test('a zero fade acts as 5 ms', () {
    final (a, _) = _setup();
    final (b, _) = _setup();
    a.start('fake', fade: Duration.zero);
    b.start('fake', fade: const Duration(milliseconds: 5));
    final outA = _take(a, 1000);
    expect(outA, _take(b, 1000));
    expect(_l(outA, 238), lessThan(8192));
    expect(_l(outA, 239), 8192);
  });

  test('a 500 ms fade-out ends in 0.5 s', () {
    final (m, _) = _setup();
    m.start('fake');
    _take(m, _full);
    m.stop('fake', fade: const Duration(milliseconds: 500));
    final out = _take(m, _rate);
    expect(_l(out, _rate ~/ 2 - 2000), greaterThan(0));
    for (var n = _rate ~/ 2 - 1; n < _rate; n++) {
      expect(_l(out, n), 0, reason: '$n');
    }
    expect(m.isSilent, isTrue);
  });

  group('gain', () {
    test('initial gain scales the full level', () {
      final (m, _) = _setup(gain: 0.5);
      m.start('fake');
      final out = _take(m, _full);
      expect(_l(out, _full - 1), 4096);
    });

    test('setGain moves smoothly and monotonically to the new level', () {
      final (m, _) = _setup(gain: 0.5);
      m.start('fake');
      final a = _take(m, _full);
      expect(m.setGain('fake', 1.0), isTrue);
      final b = _take(m, 2 * _rate);
      for (var n = 1; n < b.length ~/ 2; n++) {
        expect(_l(b, n), greaterThanOrEqualTo(_l(b, n - 1)));
      }
      expect(_l(b, 0), lessThan(4100));
      expect(_l(b, b.length ~/ 2 - 1), 8192);
      expect(
        _maxNeighbourJump(Int16List.fromList([...a, ...b])),
        lessThanOrEqualTo(2),
      );
    });

    test('gain is clamped to 4', () {
      final (m, _) = _setup(level: 0.05, gain: 100);
      final (twin, _) = _setup(level: 0.05, gain: 4);
      m.start('fake');
      twin.start('fake');
      final out = _take(m, _full);
      expect(out, _take(twin, _full));
      expect(_l(out, _full - 1), (0.2 * 32767).round());

      m.setGain('fake', 100);
      twin.setGain('fake', 4);
      expect(_take(m, _rate), _take(twin, _rate));
    });

    test('NaN gain is ignored', () {
      final (m, _) = _setup();
      m.start('fake');
      _take(m, _full);
      expect(m.setGain('fake', double.nan), isTrue);
      final out = _take(m, _rate);
      expect(out.every((s) => s == 8192), isTrue);
    });
  });

  test('two soundscapes sum; stopping one leaves the other', () {
    final m = Master(sampleRate: _rate, seed: 1);
    final a = FakeSoundscape(id: 'a', left: 0.1, right: 0.1);
    final b = FakeSoundscape(id: 'b', left: 0.2, right: 0.2);
    m
      ..add(a)
      ..add(b)
      ..start('a')
      ..start('b');
    final out = _take(m, _full);
    expect(
      (_l(out, _full - 1) - (0.3 * 32767).round()).abs(),
      lessThanOrEqualTo(1),
    );
    m.stop('a');
    final after = _take(m, 4 * _rate);
    final aRendered = a.renderCount;
    final bRendered = b.renderCount;
    _take(m, _rate);
    expect(a.renderCount, aRendered);
    expect(b.renderCount, greaterThan(bRendered));
    expect(
      (_l(after, 4 * _rate - 1) - (0.2 * 32767).round()).abs(),
      lessThanOrEqualTo(1),
    );
    expect(m.isSilent, isFalse);
  });

  test('each soundscape is prepared with the rate, its seed and the bank', () {
    final m = Master(sampleRate: _rate, seed: 42);
    final a = FakeSoundscape(id: 'a');
    final b = FakeSoundscape(id: 'b');
    m
      ..add(a)
      ..add(b);
    expect(m.sampleRate, _rate);
    expect(a.preparedRate, _rate);
    expect(b.preparedRate, _rate);
    expect(a.preparedSeed, Rng.mix(42, 100));
    expect(b.preparedSeed, Rng.mix(42, 101));
    expect(identical(a.preparedNoise, m.noise), isTrue);
    expect(identical(b.preparedNoise, m.noise), isTrue);
  });

  test('a duplicate id throws StateError', () {
    final (m, _) = _setup();
    expect(() => m.add(FakeSoundscape()), throwsStateError);
  });

  test('rates outside 8000..192000 throw ArgumentError', () {
    expect(() => Master(sampleRate: 7999, seed: 1), throwsArgumentError);
    expect(() => Master(sampleRate: 192001, seed: 1), throwsArgumentError);
  });

  test('setParam forwards unchanged; unknown ids return false', () {
    final (m, f) = _setup();
    expect(m.setParam('fake', 'level', 0.7), isTrue);
    expect(f.paramCalls, [('level', 0.7)]);
    expect(m.setParam('nope', 'level', 0.7), isFalse);
    expect(m.start('nope'), isFalse);
    expect(m.stop('nope'), isFalse);
    expect(m.setGain('nope', 1), isFalse);
    expect(f.paramCalls, hasLength(1));
  });

  test('converts 0.5 and -0.5 to 16384 and -16384', () {
    final m = Master(sampleRate: _rate, seed: 1);
    m
      ..add(FakeSoundscape(left: 0.5, right: -0.5))
      ..start('fake');
    final out = _take(m, _full);
    expect(_l(out, _full - 1), 16384);
    expect(out[_full * 2 - 1], -16384);
  });

  test('the limiter caps loud input and leaves 0.25 alone', () {
    final (loud, _) = _setup(level: 3.0);
    loud.start('fake');
    final out = _take(loud, 3 * _rate);
    expect(out.every((s) => s.abs() <= 29203), isTrue);
    expect(_l(out, 3 * _rate - 1), greaterThan(27000));

    final (quiet, _) = _setup();
    quiet.start('fake');
    expect(_l(_take(quiet, _full), _full - 1), 8192);
  });

  group('S8 fault', () {
    void expectRecovery(FakeSoundscape Function() make) {
      final m = Master(sampleRate: _rate, seed: 1);
      final f = make();
      m
        ..add(f)
        ..start('fake');
      final out = _take(m, 800 * 256);
      const bad = 400 * 256;
      expect(_l(out, bad - 1), 8192);
      for (var i = bad * 2; i < (bad + 256) * 2; i++) {
        expect(out[i], 0, reason: '$i');
      }
      expect(m.faultBlocks, 1);
      expect(f.resetCount, 1);
      for (var k = 0; k < 399 * 256; k++) {
        final expected = _fadeIn(0.25, k, 2 * _rate);
        expect(
          (_l(out, bad + 256 + k) - expected).abs(),
          lessThanOrEqualTo(1),
          reason: '$k',
        );
        expect(out[(bad + 256 + k) * 2 + 1], _l(out, bad + 256 + k));
      }
      expect(_l(out, 800 * 256 - 1), 8192);
    }

    test('NaN mutes the block and re-fades', () {
      expectRecovery(() => FakeSoundscape()..faultAtBlock = 400);
    });

    test('infinity mutes the block and re-fades', () {
      expectRecovery(
        () => FakeSoundscape()
          ..faultAtBlock = 400
          ..faultWithInfinity = true,
      );
    });

    test('a throwing soundscape mutes the block and re-fades', () {
      expectRecovery(() => FakeSoundscape()..throwAtBlock = 400);
    });

    test('a throw skips the remaining soundscapes of that block', () {
      final m = Master(sampleRate: _rate, seed: 1);
      final a = FakeSoundscape(id: 'a')..throwAtBlock = 3;
      final b = FakeSoundscape(id: 'b');
      m
        ..add(a)
        ..add(b)
        ..start('a')
        ..start('b');
      _take(m, 4 * 256);
      expect(a.renderCount, 4);
      expect(b.renderCount, 3);
      expect(b.resetCount, 1);
      expect(m.faultBlocks, 1);
    });

    test('a slot fading out at the fault stays stopped', () {
      final (m, f) = _setup();
      m.start('fake');
      _take(m, _full);
      m.stop('fake');
      f.faultAtBlock = f.renderCount + 10;
      final out = _take(m, _rate);
      expect(m.faultBlocks, 1);
      expect(m.isSilent, isTrue);
      expect(f.renderCount, f.faultAtBlock! + 1);
      for (var n = 10 * 256; n < _rate; n++) {
        expect(_l(out, n), 0);
      }
    });
  });

  test('output does not depend on caller chunking', () {
    Int16List play(List<int> chunks) {
      final m = Master(sampleRate: _rate, seed: 7);
      m
        ..add(
          FakeSoundscape(id: 'a', left: 0.1, right: -0.2, rampPerBlock: 1e-3),
        )
        ..add(FakeSoundscape(id: 'b', left: 0.05, right: 0.1))
        ..start('a', fade: const Duration(milliseconds: 100))
        ..start('b');
      final events = <int, void Function()>{
        5000: () => m.stop('a', fade: const Duration(milliseconds: 50)),
        12345: () => m.start('a', fade: const Duration(milliseconds: 20)),
        30000: () => m.setGain('b', 3.0),
      };
      const total = 60000;
      final out = Int16List(total * 2);
      var done = 0;
      var c = 0;
      while (done < total) {
        var n = chunks[c++ % chunks.length];
        if (done + n > total) n = total - done;
        for (final at in events.keys) {
          if (done < at && done + n > at) n = at - done;
        }
        final buf = Int16List(n * 2);
        m.render(buf, n);
        out.setAll(done * 2, buf);
        done += n;
        events[done]?.call();
      }
      return out;
    }

    final big = play([4096]);
    expect(big.any((s) => s != 0), isTrue);
    expect(play([333, 1, 1000, 255]), big);
  });

  test('fade-in law holds at 44100', () {
    final (m, _) = _setup(rate: 44100);
    m.start('fake');
    final out = _take(m, 3 * 44100);
    for (var n = 0; n < 3 * 44100; n++) {
      final expected = _fadeIn(0.25, n, 2 * 44100);
      expect((_l(out, n) - expected).abs(), lessThanOrEqualTo(1), reason: '$n');
    }
  });

  test('isSilent turns true only after the last non-zero frame is read', () {
    final (m, _) = _setup();
    m.start('fake');
    _take(m, _rate * 2 + 1234);
    m.stop('fake', fade: const Duration(milliseconds: 300));
    var silentAt = -1;
    var lastNonZero = -1;
    for (var call = 0; call < 200; call++) {
      final silentBefore = m.isSilent;
      if (silentBefore && silentAt < 0) silentAt = call;
      final buf = Int16List(200);
      m.render(buf, 100);
      final nonZero = buf.any((s) => s != 0);
      if (nonZero) lastNonZero = call;
      if (silentBefore) expect(nonZero, isFalse, reason: 'call $call');
    }
    expect(lastNonZero, greaterThan(0));
    expect(silentAt, greaterThan(lastNonZero));
    expect(silentAt, lessThan(lastNonZero + 20));
  });

  test('render(frames: 0) does nothing', () {
    final (m, f) = _setup();
    m.start('fake');
    m.render(Int16List(0), 0);
    expect(f.renderCount, 0);
  });
}
