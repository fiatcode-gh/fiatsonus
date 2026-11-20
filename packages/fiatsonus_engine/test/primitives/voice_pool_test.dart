import 'dart:typed_data';

import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/primitives/biquad.dart';
import 'package:fiatsonus_engine/src/primitives/noise_table.dart';
import 'package:fiatsonus_engine/src/primitives/voice_pool.dart';
import 'package:test/test.dart';

final _table = NoiseTable.fromChannels(
  Float32List(1000)..fillRange(0, 1000, 1.0),
  Float32List(1000)..fillRange(0, 1000, 1.0),
);

/// Spawns a grain on the all-ones table through an open low-pass, so the
/// output shows the envelope.
void _grain(
  VoicePool pool,
  int rate, {
  double attack = 0.002,
  double decay = 0.02,
  double level = 0.5,
  double pan = 0,
  int offset = 0,
}) => pool.spawn(
  _table,
  0,
  0,
  BiquadType.lowPass,
  0.45 * rate,
  0.7071,
  attack,
  decay,
  level,
  pan,
  offset,
);

/// Renders [blocks] blocks into fresh zeroed buffers and returns them joined.
(Float32List, Float32List) _render(VoicePool pool, int blocks) {
  final left = Float32List(blocks * kBlockFrames);
  final right = Float32List(blocks * kBlockFrames);
  final l = Float32List(kBlockFrames);
  final r = Float32List(kBlockFrames);
  for (var b = 0; b < blocks; b++) {
    l.fillRange(0, kBlockFrames, 0.0);
    r.fillRange(0, kBlockFrames, 0.0);
    pool.render(l, r, kBlockFrames);
    left.setAll(b * kBlockFrames, l);
    right.setAll(b * kBlockFrames, r);
  }
  return (left, right);
}

double _peak(Float32List buf) {
  var p = 0.0;
  for (final v in buf) {
    if (v.abs() > p) p = v.abs();
  }
  return p;
}

int _lastNonZero(Float32List buf) {
  for (var i = buf.length - 1; i >= 0; i--) {
    if (buf[i] != 0) return i;
  }
  return -1;
}

void main() {
  for (final rate in [44100, 48000]) {
    group('at $rate Hz', () {
      VoicePool pool({int capacity = kMaxVoices}) =>
          VoicePool(capacity: capacity)..prepare(rate);

      test('one grain: delayed, centred, ends on exact zeros', () {
        final p = pool();
        _grain(p, rate, offset: 10);
        expect(p.activeCount, 1);
        final (l, r) = _render(p, 10);
        expect(l.sublist(0, 10), everyElement(0.0));
        expect(r.sublist(0, 10), everyElement(0.0));
        expect(_peak(l), closeTo(0.5 * 0.70711, 0.02 * 0.5 * 0.70711));
        expect(_peak(r), closeTo(0.5 * 0.70711, 0.02 * 0.5 * 0.70711));
        final end = 10 + (0.002 * rate).round() + (0.02 * rate).round() - 1;
        expect(_lastNonZero(l), end);
        expect(_lastNonZero(r), end);
        expect(p.activeCount, 0);
        final (l2, r2) = _render(p, 4);
        expect(l2, everyElement(0.0));
        expect(r2, everyElement(0.0));
      });

      test('a grain longer than a block is continuous at block borders', () {
        final p = pool();
        _grain(p, rate, decay: 0.05);
        final (l, _) = _render(p, 6);
        for (var border = kBlockFrames; border < l.length; border += 256) {
          var inside = 0.0;
          for (var i = border - kBlockFrames + 1; i < border; i++) {
            final d = (l[i] - l[i - 1]).abs();
            if (d > inside) inside = d;
          }
          final across = (l[border] - l[border - 1]).abs();
          expect(across, lessThanOrEqualTo(inside), reason: 'border $border');
        }
      });
    });
  }

  VoicePool pool({int capacity = kMaxVoices}) =>
      VoicePool(capacity: capacity)..prepare(48000);

  test('pan -1 leaves the right silent, pan +1 the left', () {
    final hardLeft = pool();
    _grain(hardLeft, 48000, pan: -1);
    final (l1, r1) = _render(hardLeft, 6);
    expect(_peak(l1), greaterThan(0.4));
    expect(r1, everyElement(0.0));

    final hardRight = pool();
    _grain(hardRight, 48000, pan: 1);
    final (l2, r2) = _render(hardRight, 6);
    expect(l2, everyElement(0.0));
    expect(_peak(r2), greaterThan(0.4));
  });

  test('render adds into the buffers', () {
    final a = pool();
    final b = pool();
    _grain(a, 48000, offset: 3);
    _grain(b, 48000, offset: 3);
    final (gl, gr) = _render(a, 1);
    final l = Float32List(kBlockFrames)..fillRange(0, kBlockFrames, 1.0);
    final r = Float32List(kBlockFrames)..fillRange(0, kBlockFrames, 1.0);
    b.render(l, r, kBlockFrames);
    for (var i = 0; i < kBlockFrames; i++) {
      expect(l[i], closeTo(1.0 + gl[i], 1e-6));
      expect(r[i], closeTo(1.0 + gr[i], 1e-6));
    }
  });

  test('steal: the quietest voice fades out before the new grain', () {
    void spawn(VoicePool p, double level, int offset) =>
        _grain(p, 48000, decay: 1, level: level, offset: offset);
    final a = pool(capacity: 4);
    final b = pool(capacity: 4);
    for (final level in [0.2, 0.4, 0.6, 0.8]) {
      spawn(a, level, 0);
    }
    for (final level in [0.4, 0.6, 0.8]) {
      spawn(b, level, 0);
    }
    final (aBefore, _) = _render(a, 10);
    final (bBefore, _) = _render(b, 10);

    spawn(a, 1.0, 10);
    spawn(b, 1.0, 64);
    expect(a.stolenCount, 1);
    expect(a.activeCount, 4);
    final (aL, aR) = _render(a, 6);
    final (bL, bR) = _render(b, 6);
    expect(a.activeCount, 4);

    for (var i = 64; i < aL.length; i++) {
      expect(aL[i], closeTo(bL[i], 1e-6), reason: 'left $i');
      expect(aR[i], closeTo(bR[i], 1e-6), reason: 'right $i');
    }
    var previous = aBefore.last - bBefore.last;
    expect(previous, greaterThan(0.05));
    for (var i = 0; i < 64; i++) {
      final d = aL[i] - bL[i];
      expect((d - previous).abs(), lessThanOrEqualTo(0.01), reason: 'frame $i');
      expect(d, lessThanOrEqualTo(previous + 1e-6), reason: 'frame $i');
      previous = d;
    }
    expect(previous, closeTo(0, 1e-6));
  });

  test('no steal candidate: a grain beyond capacity in one block drops', () {
    final p = pool(capacity: 2);
    for (var i = 0; i < 3; i++) {
      _grain(p, 48000, offset: i);
    }
    expect(p.stolenCount, 0);
    expect(p.activeCount, 2);
    _render(p, 1);
    expect(p.activeCount, 2);
  });

  test('capacity is 1..kMaxVoices, default kMaxVoices', () {
    expect(() => VoicePool(capacity: 0), throwsArgumentError);
    expect(() => VoicePool(capacity: kMaxVoices + 1), throwsArgumentError);
    expect(VoicePool().capacity, 64);
    expect(VoicePool(capacity: 1).capacity, 1);
  });

  test('reset silences everything', () {
    final p = pool(capacity: 4);
    for (var i = 0; i < 6; i++) {
      _grain(p, 48000, decay: 1, level: 1, offset: 5);
      _render(p, 1);
    }
    p.reset();
    expect(p.activeCount, 0);
    final (l, r) = _render(p, 3);
    expect(l, everyElement(0.0));
    expect(r, everyElement(0.0));
  });

  test('out-of-range inputs do not throw and stay finite', () {
    final p = pool(capacity: 4);
    p.spawn(
      _table,
      7,
      -7,
      BiquadType.bandPass,
      double.nan,
      double.nan,
      double.nan,
      double.nan,
      100,
      double.nan,
      -3,
    );
    p.spawn(
      _table,
      -1,
      1 << 40,
      BiquadType.highPass,
      1e9,
      1e9,
      -1,
      1e9,
      double.nan,
      5,
      9999,
    );
    p.spawn(
      _table,
      0,
      0,
      BiquadType.lowPass,
      1000,
      1,
      0.001,
      0.1,
      100,
      double.nan,
      9999,
    );
    final (l, r) = _render(p, 20);
    for (var i = 0; i < l.length; i++) {
      expect(l[i].isFinite && r[i].isFinite, isTrue, reason: 'frame $i');
    }
    expect(_peak(l) + _peak(r), greaterThan(0));
  });
}
