// Generic automatic checks (PLAN 4.6) shared by every soundscape. A
// soundscape's `<id>_checks_test.dart` calls [defineSoundscapeChecks] with
// its loudness bands and adds its own checks.
import 'dart:typed_data';

import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:fiatsonus_engine/offline.dart';
import 'package:fiatsonus_engine/src/primitives/rng.dart';
import 'package:test/test.dart';

/// Largest legal output magnitude: `floor(32767 * 10^(-1/20))`.
const int maxLegalPeak = 29203;

/// Largest allowed per-channel DC offset.
const double maxDc = 0.001;

/// Largest allowed click metric (`maxJumpZ`).
const double maxJump = 12.0;

/// Sample rates every check runs at.
const List<int> checkRates = [44100, 48000];

/// Frames per `Master.render` call unless a check says otherwise.
const int chunkFrames = 1024;

/// Per-soundscape thresholds of the generic checks.
final class SoundscapeCheckConfig {
  const SoundscapeCheckConfig({
    required this.id,
    required this.lufsMin,
    required this.lufsMax,
    required this.edgeLufsMin,
    required this.edgeLufsMax,
  });

  /// Soundscape id as known to `createSoundscape`.
  final String id;

  /// Loudness band at default params.
  final double lufsMin, lufsMax;

  /// Loudness band for every edge and corner render.
  final double edgeLufsMin, edgeLufsMax;
}

/// One master with one soundscape, started, whose output is captured into a
/// single buffer.
final class MasterRun {
  /// Builds the master, adds [scape] with [gain], applies [params] and
  /// starts it. [seconds] sizes the capture buffer.
  MasterRun(
    this.scape, {
    required this.rate,
    required double seconds,
    int seed = 1,
    double gain = 1.0,
    Map<String, double> params = const {},
  }) : master = Master(sampleRate: rate, seed: seed),
       out = Int16List((seconds * rate).round() * 2) {
    master.add(scape, gain: gain);
    params.forEach((k, v) => master.setParam(scape.id, k, v));
    master.start(scape.id);
  }

  final Soundscape scape;
  final int rate;
  final Master master;

  /// Interleaved stereo capture; [frames] of it are written.
  final Int16List out;
  int frames = 0;

  /// Largest `activeVoices` sampled after every chunk.
  int maxVoices = 0;

  /// Renders [n] more frames in [chunk]-frame calls, calling [beforeChunk]
  /// with the capture position before every call.
  void render(
    int n, {
    int chunk = chunkFrames,
    void Function(int frame)? beforeChunk,
  }) {
    final end = frames + n;
    while (frames < end) {
      final k = end - frames < chunk ? end - frames : chunk;
      beforeChunk?.call(frames);
      master.render(
        Int16List.sublistView(out, frames * 2, (frames + k) * 2),
        k,
      );
      frames += k;
      final v = scape.activeVoices;
      if (v > maxVoices) maxVoices = v;
    }
  }

  /// Renders up to the end of the capture buffer.
  void renderToEnd({
    int chunk = chunkFrames,
    void Function(int frame)? beforeChunk,
  }) =>
      render(out.length ~/ 2 - frames, chunk: chunk, beforeChunk: beforeChunk);

  /// Frame index of [seconds].
  int at(double seconds) => (seconds * rate).round();

  /// Loudness over [from]..[to] seconds of the capture.
  double lufs(double from, double to) => lufsOf(out, rate, at(from), at(to));
}

/// Renders a whole capture of [seconds] with [scape] in one call.
MasterRun renderMaster(
  Soundscape scape, {
  required int rate,
  required double seconds,
  int seed = 1,
  double gain = 1.0,
  Map<String, double> params = const {},
  int chunk = chunkFrames,
  void Function(MasterRun run, int frame)? beforeChunk,
}) {
  final run = MasterRun(
    scape,
    rate: rate,
    seconds: seconds,
    seed: seed,
    gain: gain,
    params: params,
  );
  run.renderToEnd(
    chunk: chunk,
    beforeChunk: beforeChunk == null ? null : (f) => beforeChunk(run, f),
  );
  return run;
}

/// Loudness of frames [from]..[to] of [out].
double lufsOf(Int16List out, int rate, int from, int to) => (LoudnessMeter(
  rate,
)..add(Int16List.sublistView(out, from * 2, to * 2), to - from)).lufs;

/// Every combination of [specs] at 0 or 1.
List<Map<String, double>> paramCorners(List<ParamSpec> specs) => [
  for (var bits = 0; bits < 1 << specs.length; bits++)
    {
      for (var i = 0; i < specs.length; i++)
        specs[i].id: (bits >> i & 1).toDouble(),
    },
];

/// The common acceptance of a whole render: no fault, legal peak, no click.
void expectCleanRender(MasterRun run, String reason) {
  expect(run.master.faultBlocks, 0, reason: '$reason: faultBlocks');
  expect(
    peakAbs(run.out, run.frames),
    lessThanOrEqualTo(maxLegalPeak),
    reason: '$reason: peak',
  );
  expect(
    maxJumpZ(run.out, run.frames),
    lessThanOrEqualTo(maxJump),
    reason: '$reason: maxJumpZ',
  );
}

/// Defines the generic checks for [config] at every rate in [checkRates].
void defineSoundscapeChecks(SoundscapeCheckConfig config) {
  Soundscape make() => createSoundscape(config.id)!;
  final specs = make().params;
  // The 600 s default render of each rate, shared by checks 1b, 2, 3, 4, 10.
  final long = <int, MasterRun>{};

  setUpAll(() {
    for (final rate in checkRates) {
      long[rate] = renderMaster(make(), rate: rate, seconds: 600);
    }
  });
  tearDownAll(long.clear);

  group('no NaN or infinity (10 min)', () {
    for (final rate in checkRates) {
      test('$rate Hz: soundscape alone, every float sample finite', () {
        final scape = make()
          ..prepare(rate, Rng.mix(1, 100), NoiseBank(rate, Rng.mix(1, 1)));
        final l = Float32List(kBlockFrames);
        final r = Float32List(kBlockFrames);
        final blocks = 600 * rate ~/ kBlockFrames;
        var bad = 0;
        for (var b = 0; b < blocks; b++) {
          l.fillRange(0, kBlockFrames, 0.0);
          r.fillRange(0, kBlockFrames, 0.0);
          scape.render(l, r, kBlockFrames);
          for (var i = 0; i < kBlockFrames; i++) {
            if (!l[i].isFinite || !r[i].isFinite) bad++;
          }
        }
        expect(bad, 0);
      });

      test('$rate Hz: master render has no fault blocks', () {
        expect(long[rate]!.master.faultBlocks, 0);
      });
    }
  });

  group('no clipping', () {
    for (final rate in checkRates) {
      test('$rate Hz: 600 s default render', () {
        final run = long[rate]!;
        expect(peakAbs(run.out, run.frames), lessThanOrEqualTo(maxLegalPeak));
      });

      test('$rate Hz: every all-params corner at slot gain 4.0', () {
        for (final corner in paramCorners(specs)) {
          final run = renderMaster(
            make(),
            rate: rate,
            seconds: 10,
            gain: 4.0,
            params: corner,
          );
          expect(
            peakAbs(run.out, run.frames),
            lessThanOrEqualTo(maxLegalPeak),
            reason: '$corner',
          );
        }
      });
    }
  });

  group('level', () {
    for (final rate in checkRates) {
      final inBand = inInclusiveRange(config.lufsMin, config.lufsMax);

      test('$rate Hz: seed 1, 10 s..600 s', () {
        expect(long[rate]!.lufs(10, 600), inBand);
      });

      for (final seed in [2, 3]) {
        test('$rate Hz: seed $seed, 10 s..60 s', () {
          final run = renderMaster(make(), rate: rate, seconds: 60, seed: seed);
          expect(run.lufs(10, 60), inBand);
        });
      }
    }
  });

  group('no DC offset', () {
    for (final rate in checkRates) {
      test('$rate Hz: both channels of the 600 s render', () {
        final run = long[rate]!;
        for (final channel in [0, 1]) {
          expect(
            dcOffset(run.out, run.frames, channel).abs(),
            lessThan(maxDc),
            reason: 'channel $channel',
          );
        }
      });
    }
  });

  group('no clicks on param sweeps', () {
    for (final rate in checkRates) {
      for (final spec in specs) {
        test('$rate Hz: ${spec.id} 0 -> 1 -> 0', () {
          double value(double t) => t < 3
              ? 0.0
              : t < 18
              ? (t - 3) / 15
              : t < 33
              ? (33 - t) / 15
              : 0.0;
          final run = renderMaster(
            make(),
            rate: rate,
            seconds: 36,
            params: {spec.id: 0.0},
            beforeChunk: (run, f) =>
                run.master.setParam(config.id, spec.id, value(f / rate)),
          );
          expectCleanRender(run, spec.id);
        });
      }

      test('$rate Hz: all params toggling 0/1 every 0.5 s', () {
        final run = renderMaster(
          make(),
          rate: rate,
          seconds: 30,
          beforeChunk: (run, f) {
            final counter = f * 2 ~/ rate;
            for (var i = 0; i < specs.length; i++) {
              run.master.setParam(
                config.id,
                specs[i].id,
                (counter >> i & 1).toDouble(),
              );
            }
          },
        );
        expectCleanRender(run, 'toggle');
      });
    }
  });

  group('edge values', () {
    final edges = [
      for (final spec in specs) ...[
        {spec.id: 0.0},
        {spec.id: 1.0},
      ],
      ...paramCorners(specs),
    ];
    for (final rate in checkRates) {
      test('$rate Hz: each param alone at 0 and 1, every corner', () {
        for (final params in edges) {
          final run = renderMaster(
            make(),
            rate: rate,
            seconds: 20,
            params: params,
          );
          expectCleanRender(run, '$params');
          expect(
            run.lufs(5, 20),
            inInclusiveRange(config.edgeLufsMin, config.edgeLufsMax),
            reason: '$params: LUFS',
          );
          for (final channel in [0, 1]) {
            expect(
              dcOffset(run.out, run.frames, channel).abs(),
              lessThan(maxDc),
              reason: '$params: DC channel $channel',
            );
          }
        }
      });
    }
  });

  group('determinism', () {
    for (final rate in checkRates) {
      test('$rate Hz: same seed identical, chunking irrelevant, '
          'seed 2 differs', () {
        Int16List render({int seed = 1, int chunk = chunkFrames}) =>
            renderMaster(
              make(),
              rate: rate,
              seconds: 30,
              seed: seed,
              chunk: chunk,
            ).out;
        expect(render(), render());
        expect(render(chunk: 4096), render(chunk: 333));
        expect(render(seed: 2), isNot(render()));
      });
    }
  });

  group('pause/play: 100 fast cycles obey the fade law', () {
    for (final rate in checkRates) {
      test('$rate Hz', () {
        final a = renderMaster(make(), rate: rate, seconds: 55, gain: 0.5);
        expect(peakAbs(a.out, a.frames), lessThan(16000), reason: 'limiter');

        final b = MasterRun(make(), rate: rate, seconds: 55, gain: 0.5);
        // Start on a block boundary so every stop/start below takes effect
        // at the frame it is issued, as the u model assumes.
        final from =
            (5 * rate + kBlockFrames - 1) ~/ kBlockFrames * kBlockFrames;
        b.render(from);
        final r = Rng(7);
        final changes = <int, double>{};
        final down = -1.0 / (3.0 * rate);
        final up = 1.0 / (2.0 * rate);
        for (var c = 0; c < 100; c++) {
          b.master.stop(config.id);
          changes[b.frames] = down;
          b.render(kBlockFrames * (1 + r.nextU32() % 40));
          b.master.start(config.id);
          changes[b.frames] = up;
          b.render(kBlockFrames * (1 + r.nextU32() % 40));
        }
        b.renderToEnd();

        var u = 1.0;
        var du = 0.0;
        var minU = 1.0;
        var worst = 0.0;
        for (var f = from; f < b.frames; f++) {
          du = changes[f] ?? du;
          u += du;
          u = u > 1.0 ? 1.0 : (u < 0.0 ? 0.0 : u);
          if (u < minU) minU = u;
          final k = u * u;
          for (var ch = 0; ch < 2; ch++) {
            final d = (b.out[2 * f + ch] - a.out[2 * f + ch] * k).abs();
            if (d > worst) worst = d;
          }
        }
        expect(minU, greaterThanOrEqualTo(0.05), reason: 'slot kept running');
        expect(worst, lessThanOrEqualTo(1.01));
      });
    }
  });

  group('pause/play: 20 full stop/start cycles', () {
    for (final rate in checkRates) {
      test('$rate Hz', () {
        final run = MasterRun(make(), rate: rate, seconds: 5 + 20 * 6.0 + 15);
        run.render(run.at(5));
        final quiet = run.at(0.25);
        for (var c = 0; c < 20; c++) {
          run.master.stop(config.id);
          run.render(run.at(3.5));
          final tail = Int16List.sublistView(
            run.out,
            (run.frames - quiet) * 2,
            run.frames * 2,
          );
          expect(tail.every((s) => s == 0), isTrue, reason: 'cycle $c tail');
          expect(run.master.isSilent, isTrue, reason: 'cycle $c isSilent');
          run.master.start(config.id);
          run.render(run.at(2.5));
        }
        run.render(run.at(15));

        expect(maxJumpZ(run.out, run.frames), lessThanOrEqualTo(maxJump));
        expect(run.maxVoices, lessThanOrEqualTo(64));
        expect(run.master.faultBlocks, 0);
        final baseline = renderMaster(
          make(),
          rate: rate,
          seconds: 20,
        ).lufs(10, 20);
        final last = lufsOf(run.out, rate, run.frames - run.at(10), run.frames);
        expect(last, closeTo(baseline, 0.5));
      });
    }
  });

  group('voices bounded', () {
    for (final rate in checkRates) {
      test('$rate Hz: every chunk of the 600 s render', () {
        expect(long[rate]!.maxVoices, lessThanOrEqualTo(kMaxVoices));
      });
    }
  });
}
