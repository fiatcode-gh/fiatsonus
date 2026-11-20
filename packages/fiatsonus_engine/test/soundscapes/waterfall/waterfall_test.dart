import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/primitives/noise_table.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:fiatsonus_engine/src/soundscapes/waterfall/waterfall.dart';
import 'package:test/test.dart';

import '../../support/signals.dart';

const _rates = [44100, 48000];

final _seed = Rng.mix(1, 100);
final _banks = <int, NoiseBank>{};

NoiseBank _bank(int rate) =>
    _banks.putIfAbsent(rate, () => NoiseBank(rate, Rng.mix(1, 1)));

Waterfall _make(
  int rate, {
  Set<WaterfallLayer>? solo,
  int? seed,
  Map<String, double> params = const {},
}) {
  final w = Waterfall(solo: solo)..prepare(rate, seed ?? _seed, _bank(rate));
  params.forEach(w.setParam);
  return w;
}

/// Whole blocks covering [seconds] at [rate].
int _blocks(int rate, double seconds) => (seconds * rate / kBlockFrames).ceil();

/// Sample index of [seconds] at [rate].
int _at(int rate, double seconds) => (seconds * rate).round();

/// Renders [blocks] full blocks into fresh zeroed buffers and returns them
/// joined. [before] runs ahead of each block with its index.
(Float32List, Float32List) _render(
  Waterfall w,
  int blocks, {
  void Function(int block)? before,
}) {
  final left = Float32List(blocks * kBlockFrames);
  final right = Float32List(blocks * kBlockFrames);
  final bl = Float32List(kBlockFrames);
  final br = Float32List(kBlockFrames);
  for (var b = 0; b < blocks; b++) {
    before?.call(b);
    bl.fillRange(0, kBlockFrames, 0.0);
    br.fillRange(0, kBlockFrames, 0.0);
    w.render(bl, br, kBlockFrames);
    left.setAll(b * kBlockFrames, bl);
    right.setAll(b * kBlockFrames, br);
  }
  return (left, right);
}

double _rmsRange(Float32List buf, int from, int to) =>
    rms(Float32List.sublistView(buf, from, to));

double _rmsStereo(Float32List l, Float32List r, int from, int to) {
  final a = _rmsRange(l, from, to);
  final b = _rmsRange(r, from, to);
  return math.sqrt((a * a + b * b) / 2);
}

bool _allFinite(Float32List buf) {
  for (final x in buf) {
    if (!x.isFinite) return false;
  }
  return true;
}

bool _allZeroFrom(Float32List buf, int from) {
  for (var i = from; i < buf.length; i++) {
    if (buf[i] != 0.0) return false;
  }
  return true;
}

void _expectIdentical(
  (Float32List, Float32List) a,
  (Float32List, Float32List) b,
) {
  expect(a.$1, orderedEquals(b.$1));
  expect(a.$2, orderedEquals(b.$2));
}

/// The PLAN 4.6 smoothing proof for one param step. Returns the ratio of the
/// first 64 frames' maximum difference to the following second's.
double _stepRatio(
  int rate,
  String id,
  double value, {
  Set<WaterfallLayer>? solo,
}) {
  final pre = _blocks(rate, 2.0);
  final total = pre + _blocks(rate, 1.0) + 1;
  final a = _render(_make(rate, solo: solo), total);
  final bw = _make(rate, solo: solo);
  final b = _render(
    bw,
    total,
    before: (blk) {
      if (blk == pre) bw.setParam(id, value);
    },
  );
  final step = pre * kBlockFrames;
  double diff(int i) {
    final l = (b.$1[i] - a.$1[i]).abs();
    final r = (b.$2[i] - a.$2[i]).abs();
    return l > r ? l : r;
  }

  for (var i = 0; i < step; i++) {
    expect(diff(i), 0.0, reason: 'before the step at $i');
  }
  var early = 0.0;
  for (var i = step; i < step + 64; i++) {
    final d = diff(i);
    if (d > early) early = d;
  }
  var later = 0.0;
  for (var i = step + 64; i < step + 64 + rate; i++) {
    final d = diff(i);
    if (d > later) later = d;
  }
  expect(later, greaterThan(1e-3), reason: '$id -> $value moves the output');
  expect(early, lessThanOrEqualTo(0.1 * later), reason: '$id -> $value');
  return early / later;
}

void main() {
  for (final rate in _rates) {
    group('$rate Hz', () {
      test('defaults render finite audio at a sane level', () {
        final (l, r) = _render(_make(rate), _blocks(rate, 10));
        expect(_allFinite(l) && _allFinite(r), isTrue);
        final from = _at(rate, 5);
        final to = _at(rate, 10);
        for (final ch in [l, r]) {
          expect(_rmsRange(ch, from, to), inInclusiveRange(0.03, 0.15));
        }
      });

      test('render adds into the caller buffers', () {
        final blocks = _blocks(rate, 2);
        final plain = _render(_make(rate), blocks);
        final w = _make(rate);
        final bl = Float32List(kBlockFrames);
        final br = Float32List(kBlockFrames);
        for (var b = 0; b < blocks; b++) {
          bl.fillRange(0, kBlockFrames, 1.0);
          br.fillRange(0, kBlockFrames, 1.0);
          w.render(bl, br, kBlockFrames);
          for (var i = 0; i < kBlockFrames; i++) {
            final k = b * kBlockFrames + i;
            expect(bl[i], closeTo(1.0 + plain.$1[k], 1e-6));
            expect(br[i], closeTo(1.0 + plain.$2[k], 1e-6));
          }
        }
      });

      test('equal seeds render identical samples; another seed differs', () {
        final blocks = _blocks(rate, 10);
        final a = _render(_make(rate), blocks);
        _expectIdentical(a, _render(_make(rate), blocks));
        final c = _render(_make(rate, seed: Rng.mix(1, 101)), blocks);
        expect(c.$1, isNot(orderedEquals(a.$1)));
      });

      test('ignored setParam calls leave the output untouched', () {
        final blocks = _blocks(rate, 3);
        final base = _render(_make(rate), blocks);
        for (final (id, v) in [
          ('height', double.nan),
          ('nope', 0.9),
          ('height', 0.5),
        ]) {
          final w = _make(rate)..setParam(id, v);
          _expectIdentical(_render(w, blocks), base);
        }
      });

      test('setParam clamps to 0..1', () {
        final blocks = _blocks(rate, 3);
        _expectIdentical(
          _render(_make(rate, params: {'height': 7}), blocks),
          _render(_make(rate, params: {'height': 1}), blocks),
        );
      });

      test('param steps are smoothed', () {
        _stepRatio(rate, 'spray', 1);
        _stepRatio(rate, 'width', 0);
        _stepRatio(rate, 'distance', 1);
        _stepRatio(rate, 'distance', 0);
        _stepRatio(
          rate,
          'height',
          1,
          solo: {
            WaterfallLayer.roar,
            WaterfallLayer.body,
            WaterfallLayer.spray,
          },
        );
      });

      test('width 0 is exact mono', () {
        final (l, r) = _render(
          _make(rate, params: {'width': 0}),
          _blocks(rate, 10),
        );
        final from = _at(rate, 5);
        for (var i = from; i < l.length; i++) {
          expect(l[i], r[i], reason: 'frame $i');
        }
      });

      test('width 1 keeps the channels decorrelated', () {
        final (l, r) = _render(
          _make(rate, params: {'width': 1}),
          _blocks(rate, 12),
        );
        var lr = 0.0;
        var ll = 0.0;
        var rr = 0.0;
        for (var i = _at(rate, 2); i < _at(rate, 12); i++) {
          lr += l[i] * r[i];
          ll += l[i] * l[i];
          rr += r[i] * r[i];
        }
        expect((lr / math.sqrt(ll * rr)).abs(), lessThan(0.3));
      });

      test('distance 1 is 8 to 25 dB below distance 0', () {
        final blocks = _blocks(rate, 15);
        final near = _render(_make(rate, params: {'distance': 0}), blocks);
        final far = _render(_make(rate, params: {'distance': 1}), blocks);
        final from = _at(rate, 5);
        final to = _at(rate, 15);
        final db = ratioDb(
          _rmsStereo(near.$1, near.$2, from, to),
          _rmsStereo(far.$1, far.$2, from, to),
        );
        expect(db, inInclusiveRange(8, 25));
      });

      test('body at height 1 is 5 to 12 dB above height 0', () {
        final blocks = _blocks(rate, 10);
        const body = {WaterfallLayer.body};
        final low = _render(
          _make(rate, solo: body, params: {'height': 0}),
          blocks,
        );
        final high = _render(
          _make(rate, solo: body, params: {'height': 1}),
          blocks,
        );
        final from = _at(rate, 3);
        final to = _at(rate, 10);
        final db = ratioDb(
          _rmsStereo(high.$1, high.$2, from, to),
          _rmsStereo(low.$1, low.$2, from, to),
        );
        expect(db, inInclusiveRange(5, 12));
      });

      test('spray 0 silences the spray solo and stops processing it', () {
        final w = _make(
          rate,
          solo: {WaterfallLayer.spray},
          params: {'spray': 0},
        );
        final at3 = _blocks(rate, 3);
        _render(w, at3);
        final count = w.blocksRendered(WaterfallLayer.spray);
        final (l, r) = _render(w, _blocks(rate, 17));
        expect(w.blocksRendered(WaterfallLayer.spray), count);
        final from = _at(rate, 12);
        expect(_allZeroFrom(l, from), isTrue);
        expect(_allZeroFrom(r, from), isTrue);
      });

      test('spray 0.4 processes the spray layer every block', () {
        final w = _make(rate, solo: {WaterfallLayer.spray});
        final blocks = _blocks(rate, 3);
        _render(
          w,
          blocks,
          before: (b) => expect(w.blocksRendered(WaterfallLayer.spray), b),
        );
        expect(w.blocksRendered(WaterfallLayer.spray), blocks);
      });

      test('coefficients update only while height or distance moves', () {
        final w = _make(rate);
        _render(w, _blocks(rate, 3));
        final still = w.coefficientUpdates;
        _render(w, 500);
        expect(w.coefficientUpdates, still);

        w
          ..setParam('spray', 1)
          ..setParam('width', 0);
        _render(w, _blocks(rate, 1));
        expect(w.coefficientUpdates, still);

        w.setParam('height', 1);
        _render(w, 10);
        final afterHeight = w.coefficientUpdates;
        expect(afterHeight, greaterThan(still));

        _render(w, _blocks(rate, 4));
        final settled = w.coefficientUpdates;
        w.setParam('distance', 1);
        _render(w, 10);
        expect(w.coefficientUpdates, greaterThan(settled));
      });

      test('an empty solo is silent from the first block', () {
        final (l, r) = _render(_make(rate, solo: {}), _blocks(rate, 2));
        expect(_allZeroFrom(l, 0), isTrue);
        expect(_allZeroFrom(r, 0), isTrue);
      });

      test('every single-layer solo is audible at defaults', () {
        for (final layer in WaterfallLayer.values) {
          final (l, r) = _render(_make(rate, solo: {layer}), _blocks(rate, 3));
          expect(
            _rmsStereo(l, r, _at(rate, 1), _at(rate, 3)),
            greaterThan(1e-3),
            reason: layer.name,
          );
        }
      });

      test('voices stay within the pool at height 1', () {
        final w = _make(rate, params: {'height': 1});
        var most = 0;
        _render(
          w,
          _blocks(rate, 60),
          before: (_) {
            final n = w.activeVoices;
            expect(n, lessThanOrEqualTo(kMaxVoices));
            if (n > most) most = n;
          },
        );
        expect(most, greaterThan(0));
      });

      test('reset silences voices and audio resumes', () {
        final w = _make(rate);
        _render(w, _blocks(rate, 2));
        w.reset();
        expect(w.activeVoices, 0);
        final (l, r) = _render(w, _blocks(rate, 2));
        expect(_allFinite(l) && _allFinite(r), isTrue);
        expect(_rmsStereo(l, r, 0, l.length), greaterThan(1e-3));
      });

      test('a short block writes only its frames', () {
        final w = _make(rate);
        final l = Float32List(kBlockFrames);
        final r = Float32List(kBlockFrames);
        for (var b = 0; b < 20; b++) {
          l.fillRange(0, kBlockFrames, 2.0);
          r.fillRange(0, kBlockFrames, 2.0);
          w.render(l, r, 100);
          for (var i = 100; i < kBlockFrames; i++) {
            expect(l[i], 2.0);
            expect(r[i], 2.0);
          }
        }
        expect(l.sublist(0, 100).any((x) => x != 2.0), isTrue);
      });

      test('wild param values every block stay finite', () {
        const values = [-5.0, 0.0, 0.5, 1.0, 6.0, double.nan];
        const ids = ['height', 'spray', 'width', 'distance'];
        final w = _make(rate);
        final (l, r) = _render(
          w,
          _blocks(rate, 5),
          before: (b) {
            for (var k = 0; k < ids.length; k++) {
              w.setParam(ids[k], values[(b + k) % values.length]);
            }
          },
        );
        expect(_allFinite(l) && _allFinite(r), isTrue);
      });
    });
  }
}
