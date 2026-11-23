import 'dart:typed_data';

import '../core/engine_constants.dart';
import '../master/limiter.dart';
import '../master/master.dart';
import '../primitives/block_ops.dart';
import '../primitives/noise_table.dart';
import '../primitives/reverb.dart';
import '../primitives/rng.dart';
import '../soundscapes/registry.dart';
import '../soundscapes/waterfall/waterfall.dart';
import '../soundscapes/waterfall/waterfall_recipe.dart';

/// The parts of the engine path [runStage] times on their own (PLAN 5.2).
enum BenchStage {
  full,
  scape,
  bus,
  roar,
  body,
  spray,
  texture,
  reverb,
  limiter,
}

/// One timed run of a [BenchStage].
final class StageRun {
  const StageRun({
    required this.stage,
    required this.sampleRate,
    required this.seconds,
    required this.run,
    required this.micros,
  });

  final BenchStage stage;
  final int sampleRate;

  /// Measured audio seconds.
  final int seconds;

  /// 1-based.
  final int run;

  /// Wall time of the measured part.
  final int micros;

  double get microsPerSecond => micros / seconds;

  /// Realtime factor.
  double get factor => seconds * 1e6 / micros;

  static const String _tag = 'FBENCH v=1 stage=';
  static final RegExp _pattern = RegExp(
    r'^FBENCH v=1 stage=(\w+) rate=(\d+) secs=(\d+) run=(\d+) '
    r'us_per_s=(\d+) factor=\d+\.\d$',
  );

  /// The `FBENCH v=1 stage=…` log line of PLAN 5.3.
  String get line =>
      '$_tag${stage.name} rate=$sampleRate secs=$seconds run=$run '
      'us_per_s=${microsPerSecond.round()} factor=${factor.toStringAsFixed(1)}';

  /// Parses a [line] found anywhere in [text], so logcat prefixes are
  /// allowed. [micros] becomes `us_per_s × secs`. Returns null when [text]
  /// holds no valid stage line.
  static StageRun? parse(String text) {
    final at = text.indexOf(_tag);
    if (at < 0) return null;
    final m = _pattern.firstMatch(text.substring(at).trimRight());
    if (m == null) return null;
    final stage = BenchStage.values.asNameMap()[m.group(1)!];
    final seconds = int.parse(m.group(3)!);
    if (stage == null || seconds < 1) return null;
    return StageRun(
      stage: stage,
      sampleRate: int.parse(m.group(2)!),
      seconds: seconds,
      run: int.parse(m.group(4)!),
      micros: int.parse(m.group(5)!) * seconds,
    );
  }
}

const int _fullFrames = 2048;
const String _scapeId = 'waterfall';

/// Builds [stage]'s objects, renders [leadSeconds] unmeasured, then times
/// [seconds] of audio with one [Stopwatch] (PLAN 5.2).
StageRun runStage(
  BenchStage stage, {
  required int run,
  int sampleRate = 48000,
  int seed = 1,
  int seconds = 60,
  int leadSeconds = 5,
}) {
  final micros = stage == BenchStage.full
      ? _timeFull(sampleRate, seed, seconds, leadSeconds)
      : _timeBlocks(
          _blockStep(stage, sampleRate, seed),
          leadSeconds * sampleRate ~/ kBlockFrames,
          seconds * sampleRate ~/ kBlockFrames,
        );
  return StageRun(
    stage: stage,
    sampleRate: sampleRate,
    seconds: seconds,
    run: run,
    micros: micros,
  );
}

int _timeFull(int rate, int seed, int seconds, int leadSeconds) {
  final master = Master(sampleRate: rate, seed: seed)
    ..add(createSoundscape(_scapeId)!)
    ..start(_scapeId);
  final buffer = Int16List(_fullFrames * 2);
  final lead = leadSeconds * rate ~/ _fullFrames;
  for (var i = 0; i < lead; i++) {
    master.render(buffer, _fullFrames);
  }
  final calls = seconds * rate ~/ _fullFrames;
  final clock = Stopwatch()..start();
  for (var i = 0; i < calls; i++) {
    master.render(buffer, _fullFrames);
  }
  clock.stop();
  return clock.elapsedMicroseconds;
}

int _timeBlocks(void Function() step, int lead, int blocks) {
  for (var i = 0; i < lead; i++) {
    step();
  }
  final clock = Stopwatch()..start();
  for (var i = 0; i < blocks; i++) {
    step();
  }
  clock.stop();
  return clock.elapsedMicroseconds;
}

/// One 256-frame block of a stage other than [BenchStage.full].
void Function() _blockStep(BenchStage stage, int rate, int seed) {
  final bank = NoiseBank(rate, Rng.mix(seed, 1));
  final outL = Float32List(kBlockFrames);
  final outR = Float32List(kBlockFrames);

  Set<WaterfallLayer>? solo;
  switch (stage) {
    case BenchStage.full:
      throw ArgumentError.value(stage, 'stage', 'not a block stage');
    case BenchStage.scape:
      solo = null;
    case BenchStage.bus:
      solo = {};
    case BenchStage.roar:
      solo = {WaterfallLayer.roar};
    case BenchStage.body:
      solo = {WaterfallLayer.body};
    case BenchStage.spray:
      solo = {WaterfallLayer.spray};
    case BenchStage.texture:
      solo = {WaterfallLayer.texture};
    case BenchStage.reverb:
      final reverb = Reverb()..prepare(rate);
      final (srcL, srcR) = _source(bank);
      return () {
        clearBlock(outL, kBlockFrames);
        clearBlock(outR, kBlockFrames);
        reverb.process(
          srcL,
          srcR,
          outL,
          outR,
          kBlockFrames,
          0.3,
          0.3,
          WaterfallRecipe.wetGain,
        );
      };
    case BenchStage.limiter:
      final limiter = Limiter()..prepare(rate);
      final (srcL, srcR) = _source(bank);
      return () {
        outL.setRange(0, kBlockFrames, srcL);
        outR.setRange(0, kBlockFrames, srcR);
        limiter.process(outL, outR, kBlockFrames);
      };
  }
  final scape = Waterfall(solo: solo)..prepare(rate, Rng.mix(seed, 100), bank);
  return () {
    clearBlock(outL, kBlockFrames);
    clearBlock(outR, kBlockFrames);
    scape.render(outL, outR, kBlockFrames);
  };
}

/// The first block of the bank's white table × 0.4.
(Float32List, Float32List) _source(NoiseBank bank) {
  final l = Float32List(kBlockFrames);
  final r = Float32List(kBlockFrames);
  for (var i = 0; i < kBlockFrames; i++) {
    l[i] = bank.white.left[i] * 0.4;
    r[i] = bank.white.right[i] * 0.4;
  }
  return (l, r);
}

/// Splits per-stage `us_per_s` into shares (PLAN 5.2). Keys in order: roar,
/// body, spray, texture, reverb, bus_other, master, unexplained, full. The
/// first eight sum to `full`. Throws [ArgumentError] when a stage is missing.
Map<String, double> stageShares(Map<BenchStage, double> microsPerSecond) {
  double v(BenchStage s) =>
      microsPerSecond[s] ??
      (throw ArgumentError.value(microsPerSecond, 'microsPerSecond', 'no $s'));
  final bus = v(BenchStage.bus);
  final scape = v(BenchStage.scape);
  final full = v(BenchStage.full);
  final reverb = v(BenchStage.reverb);
  final roar = v(BenchStage.roar) - bus;
  final body = v(BenchStage.body) - bus;
  final spray = v(BenchStage.spray) - bus;
  final texture = v(BenchStage.texture) - bus;
  return {
    'roar': roar,
    'body': body,
    'spray': spray,
    'texture': texture,
    'reverb': reverb,
    'bus_other': bus - reverb,
    'master': full - scape,
    'unexplained': scape - bus - (roar + body + spray + texture),
    'full': full,
  };
}
