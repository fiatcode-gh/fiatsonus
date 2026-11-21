import 'dart:typed_data';

import 'package:fiatsonus_engine/fiatsonus_engine.dart';

import 'device_sink.dart';

/// Wraps a [DeviceSink] and measures render time, frames and overlapping
/// writes (PLAN 4.5).
final class MeteredSink implements AudioSink {
  final DeviceSink _inner;
  final int Function() _now;
  int _channels = 2;
  int? _chunkStartedAt;
  int _pending = 0;
  int _renderMicros = 0;
  int _maxRenderMicros = 0;
  int _frames = 0;
  int _overlaps = 0;

  /// [nowMicros] defaults to a [Stopwatch].
  MeteredSink(DeviceSink inner, {int Function()? nowMicros})
    : _inner = inner,
      _now = nowMicros ?? _stopwatchClock();

  static int Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }

  /// Marks the start of a chunk's render: `SinkPump`'s `beforeChunk`.
  void chunkStart() {
    _chunkStartedAt = _now();
  }

  /// Total time from [chunkStart] to the entry of the following [write].
  int get renderMicros => _renderMicros;

  int get maxRenderMicros => _maxRenderMicros;

  /// Frames handed to the device sink.
  int get frames => _frames;

  /// Writes entered while another was pending.
  int get overlaps => _overlaps;

  @override
  Future<void> start({required int sampleRate, required int channels}) {
    _channels = channels;
    return _inner.start(sampleRate: sampleRate, channels: channels);
  }

  @override
  Future<void> write(Int16List interleaved) {
    final startedAt = _chunkStartedAt;
    if (startedAt != null) {
      final micros = _now() - startedAt;
      _renderMicros += micros;
      if (micros > _maxRenderMicros) _maxRenderMicros = micros;
      _chunkStartedAt = null;
    }
    _frames += interleaved.length ~/ _channels;
    if (_pending > 0) _overlaps++;
    _pending++;
    return _inner.write(interleaved).whenComplete(() => _pending--);
  }

  @override
  Future<void> stop() => _inner.stop();
}
