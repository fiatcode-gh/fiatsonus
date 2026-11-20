import 'dart:math' as math;

import 'package:fiatsonus_engine/src/core/engine_constants.dart';
import 'package:fiatsonus_engine/src/primitives/grain_cloud.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

/// Absolute frame positions of every grain over [blocks] blocks.
List<int> _starts(GrainCloud cloud, int blocks) {
  final out = <int>[];
  for (var b = 0; b < blocks; b++) {
    var previous = 0;
    for (var at = cloud.nextStart(kBlockFrames); at != -1;) {
      expect(at, inInclusiveRange(0, kBlockFrames - 1));
      expect(at, greaterThanOrEqualTo(previous));
      previous = at;
      out.add(b * kBlockFrames + at);
      at = cloud.nextStart(kBlockFrames);
    }
  }
  return out;
}

/// Absolute frame of the first grain, rendering whole blocks after the
/// [skipped] blocks already consumed.
int _first(GrainCloud cloud, {int skipped = 0}) {
  for (var b = skipped; b < 100000; b++) {
    final at = cloud.nextStart(kBlockFrames);
    if (at != -1) return b * kBlockFrames + at;
  }
  fail('no grain');
}

void main() {
  for (final rate in [44100, 48000]) {
    group('at $rate Hz', () {
      for (final grains in [100.0, 400.0]) {
        test('$grains grains/s over 60 s: count and Poisson gaps', () {
          final cloud = GrainCloud(Rng(5))
            ..prepare(rate)
            ..rate = grains;
          final starts = _starts(cloud, 60 * rate ~/ kBlockFrames);
          final expected = grains * 60;
          final error = (starts.length - expected) / expected;
          final gaps = [
            for (var i = 1; i < starts.length; i++) starts[i] - starts[i - 1],
          ];
          final mean = gaps.reduce((a, b) => a + b) / gaps.length;
          var sq = 0.0;
          for (final g in gaps) {
            sq += (g - mean) * (g - mean);
          }
          final cv = math.sqrt(sq / gaps.length) / mean;
          printOnFailure('count ${starts.length}, error $error, gap CV $cv');
          expect(error.abs(), lessThan(0.05));
          expect(cv, inInclusiveRange(0.9, 1.1));
        });
      }

      for (final tiny in [1e-5, double.minPositive]) {
        test('a near-zero rate ($tiny) does not stall later grains', () {
          final cloud = GrainCloud(Rng(5))..prepare(rate);
          cloud.rate = tiny;
          expect(cloud.nextStart(kBlockFrames), -1);
          cloud.rate = 400;
          final count = _starts(cloud, 60 * rate ~/ kBlockFrames).length;
          printOnFailure('count $count');
          expect((count - 24000).abs() / 24000, lessThan(0.05));
        });
      }
    });
  }

  test('a rate change rescales the pending gap', () {
    final b = GrainCloud(Rng(5))
      ..prepare(48000)
      ..rate = 2;
    final bFirst = _first(b);
    expect(bFirst, greaterThan(256));

    final a = GrainCloud(Rng(5))
      ..prepare(48000)
      ..rate = 1;
    expect(a.nextStart(kBlockFrames), -1);
    a.rate = 2;
    expect(_first(a, skipped: 1), closeTo(bFirst + 128, 1));
  });

  test('rate 0 returns -1 forever; raising it starts grains', () {
    final cloud = GrainCloud(Rng(1))..prepare(48000);
    expect(cloud.rate, 0);
    for (var i = 0; i < 1000; i++) {
      expect(cloud.nextStart(kBlockFrames), -1);
    }
    cloud.rate = 200;
    expect(_starts(cloud, 200), isNotEmpty);
  });

  test('rate is clamped to 0..4000 and NaN acts as 0', () {
    final cloud = GrainCloud(Rng(1))..prepare(48000);
    cloud.rate = 1e9;
    expect(cloud.rate, 4000);
    cloud.rate = -5;
    expect(cloud.rate, 0);
    cloud.rate = 300;
    cloud.rate = double.nan;
    expect(cloud.rate, 0);
    for (var i = 0; i < 100; i++) {
      expect(cloud.nextStart(kBlockFrames), -1);
    }
  });

  test('a rate above 4000 acts as 4000', () {
    final a = GrainCloud(Rng(8))
      ..prepare(48000)
      ..rate = 1e6;
    final b = GrainCloud(Rng(8))
      ..prepare(48000)
      ..rate = 4000;
    expect(_starts(a, 100), _starts(b, 100));
  });

  test('equal seeds give equal offsets', () {
    GrainCloud cloud() => GrainCloud(Rng(3))
      ..prepare(48000)
      ..rate = 250;
    expect(_starts(cloud(), 500), _starts(cloud(), 500));
  });

  test('at 4000 grains/s several grains land in one block', () {
    final cloud = GrainCloud(Rng(2))
      ..prepare(48000)
      ..rate = 4000;
    var most = 0;
    for (var b = 0; b < 100; b++) {
      var count = 0;
      while (cloud.nextStart(kBlockFrames) != -1) {
        count++;
      }
      if (count > most) most = count;
    }
    expect(most, greaterThan(5));
  });
}
