import 'dart:math' as math;
import 'dart:typed_data';

import '../core/audio_sink.dart';
import '../master/master.dart';
import '../master/sink_pump.dart';
import '../soundscapes/registry.dart';
import 'analysis.dart';

/// One offline render: a soundscape, its seed and fixed params, and an
/// optional param swept 0 → 1 → 0.
final class RenderJob {
  const RenderJob({
    required this.scapeId,
    this.sampleRate = 48000,
    this.seed = 1,
    this.seconds = 60,
    this.params = const {},
    this.sweepParam,
  });

  final String scapeId;
  final int sampleRate;
  final int seed;

  /// Total length, fade-in and fade-out included; at least 6.
  final double seconds;
  final Map<String, double> params;
  final String? sweepParam;
}

/// What [renderOffline] measured.
final class RenderSummary {
  const RenderSummary({
    required this.frames,
    required this.peak,
    required this.lufs,
    required this.faultBlocks,
    required this.endedSilent,
    required this.elapsed,
    this.sampleRate = 48000,
  });

  /// Frames written to the sink.
  final int frames;

  /// Largest absolute sample of the whole render.
  final int peak;

  /// Loudness from `min(5 s, stop / 2)` up to the start of the fade-out.
  final double lufs;
  final int faultBlocks;
  final bool endedSilent;

  /// Wall time of the render.
  final Duration elapsed;

  /// Rate of the render, used by [realtimeFactor].
  final int sampleRate;

  /// Simulated seconds per wall second.
  double get realtimeFactor =>
      (frames / sampleRate) / (elapsed.inMicroseconds / 1e6);
}

const int _chunkFrames = 1024;

/// Renders [job] into [sink]: the soundscape fades in over 2 s, plays, and
/// fades out over 3 s ending at least 1024 frames before the end. Throws
/// [ArgumentError] for an unknown soundscape or param, a NaN param value, or
/// fewer than 6 seconds, before touching [sink].
Future<RenderSummary> renderOffline(RenderJob job, AudioSink sink) async {
  final scape = createSoundscape(job.scapeId);
  if (scape == null) {
    throw ArgumentError.value(job.scapeId, 'scapeId', 'unknown soundscape');
  }
  final ids = {for (final p in scape.params) p.id};
  for (final MapEntry(:key, :value) in job.params.entries) {
    if (!ids.contains(key)) {
      throw ArgumentError.value(key, 'params', 'unknown param');
    }
    if (value.isNaN) {
      throw ArgumentError.value(value, 'params[$key]', 'must not be NaN');
    }
  }
  final sweep = job.sweepParam;
  if (sweep != null && !ids.contains(sweep)) {
    throw ArgumentError.value(sweep, 'sweepParam', 'unknown param');
  }
  if (!(job.seconds >= 6)) {
    throw ArgumentError.value(job.seconds, 'seconds', 'must be at least 6');
  }

  final rate = job.sampleRate;
  final master = Master(sampleRate: rate, seed: job.seed)..add(scape);
  final id = scape.id;
  final total = (job.seconds * rate).round();
  final stopFrame =
      (total - 3 * rate - _chunkFrames) ~/ _chunkFrames * _chunkFrames;
  for (final MapEntry(:key, :value) in job.params.entries) {
    master.setParam(id, key, value);
  }
  if (sweep != null) master.setParam(id, sweep, 0.0);

  const a = 3.0;
  final b = stopFrame / rate - 1.0;
  final half = (b - a) / 2;
  double sweepValue(double t) {
    if (t < a) return 0.0;
    if (t < a + half) return (t - a) / half;
    if (t < b) return (b - t) / half;
    return 0.0;
  }

  final measured = _MeasuringSink(
    sink,
    LoudnessMeter(rate),
    math.min(5 * rate, stopFrame ~/ 2),
    stopFrame,
  );
  final clock = Stopwatch()..start();
  await sink.start(sampleRate: rate, channels: 2);
  master.start(id);
  var stopped = false;
  final frames = await SinkPump(master, measured).run(
    frames: total,
    beforeChunk: (written) {
      if (written >= stopFrame && !stopped) {
        master.stop(id);
        stopped = true;
      }
      if (sweep != null) master.setParam(id, sweep, sweepValue(written / rate));
    },
  );
  await sink.stop();
  clock.stop();

  return RenderSummary(
    frames: frames,
    peak: measured.peak,
    lufs: measured.meter.lufs,
    faultBlocks: master.faultBlocks,
    endedSilent: master.isSilent,
    elapsed: clock.elapsed,
    sampleRate: rate,
  );
}

/// Forwards writes to a sink while measuring peak and loudness.
final class _MeasuringSink implements AudioSink {
  final AudioSink _inner;
  final LoudnessMeter meter;
  final int _from;
  final int _to;
  int _written = 0;
  int peak = 0;

  _MeasuringSink(this._inner, this.meter, this._from, this._to);

  @override
  Future<void> start({required int sampleRate, required int channels}) =>
      _inner.start(sampleRate: sampleRate, channels: channels);

  @override
  Future<void> write(Int16List interleaved) {
    final n = interleaved.length ~/ 2;
    final p = peakAbs(interleaved, n);
    if (p > peak) peak = p;
    final lo = math.max(_from, _written);
    final hi = math.min(_to, _written + n);
    if (lo < hi) {
      meter.add(
        Int16List.sublistView(
          interleaved,
          (lo - _written) * 2,
          (hi - _written) * 2,
        ),
        hi - lo,
      );
    }
    _written += n;
    return _inner.write(interleaved);
  }

  @override
  Future<void> stop() => _inner.stop();
}
