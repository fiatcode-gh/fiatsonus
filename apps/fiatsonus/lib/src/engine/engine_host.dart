import 'dart:typed_data';

import 'package:fiatsonus_engine/fiatsonus_engine.dart';

import 'device_sink.dart';
import 'engine_log.dart';
import 'engine_protocol.dart';
import 'engine_stats.dart';
import 'metered_sink.dart';

/// The engine isolate's controller: owns [Master], [SinkPump] and the sink,
/// runs commands and keeps one pump loop at a time (PLAN 4.4, 4.5).
final class EngineHost {
  static const Duration _failureFade = Duration(milliseconds: 5);

  final int _rate;
  final DeviceSink _sink;
  final void Function(List<Object> event) _emit;
  final void Function(String line) _log;
  final int Function() _now;
  final Master _master;
  final MeteredSink _metered;
  late final SinkPump _pump = SinkPump(
    _master,
    _metered,
    chunkFrames: kChunkFrames,
  );

  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  bool _open = false;
  int _openedAt = 0;
  int _closedPlayMicros = 0;
  int _closedUnderruns = 0;
  int _closedStarvedMicros = 0;
  int _sessions = 0;
  int _statsFrames = 0;
  int _logFrames = 0;

  EngineHost({
    required int sampleRate,
    required int seed,
    required DeviceSink sink,
    required void Function(List<Object> event) emit,
    void Function(String line) log = logLine,
    int Function()? nowMicros,
  }) : this._(sampleRate, seed, sink, emit, log, nowMicros ?? _stopwatch());

  EngineHost._(
    this._rate,
    int seed,
    this._sink,
    this._emit,
    this._log,
    this._now,
  ) : _master = Master(sampleRate: _rate, seed: seed),
      _metered = MeteredSink(_sink, nowMicros: _now) {
    for (final id in soundscapeIds) {
      _master.add(createSoundscape(id)!);
    }
  }

  static int Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }

  /// Completes when no session is running or queued.
  Future<void> get settled async {
    Future<void> tail;
    do {
      tail = _tail;
      await tail;
    } while (!identical(tail, _tail));
  }

  /// Runs one protocol command. Malformed messages and unknown soundscape
  /// ids are ignored.
  void handle(Object? message) {
    switch (message) {
      case ['start', final String id, final int fadeMs]:
        if (!_master.start(id, fade: Duration(milliseconds: fadeMs))) return;
        final gen = ++_generation;
        _tail = _tail.then((_) => _session(gen));
      case ['stop', final String id, final int fadeMs]:
        _master.stop(id, fade: Duration(milliseconds: fadeMs));
      case ['param', final String id, final String paramId, final double v]:
        _master.setParam(id, paramId, v);
    }
  }

  Future<void> _session(int gen) async {
    if (gen != _generation) return;
    try {
      if (!_open) {
        await _metered.start(sampleRate: _rate, channels: 2);
        _open = true;
        _sessions++;
        _openedAt = _now();
        _statsFrames = _metered.frames;
        _logFrames = _metered.frames;
        _emit(const EngineStateChanged(playing: true).encode());
      }
      await _pump.run(beforeChunk: _beforeChunk);
      if (gen != _generation) return;
      await _pump.run(frames: _rate ~/ 2, beforeChunk: _beforeChunk);
      if (gen != _generation) return;
      await _metered.stop();
      _close();
      final stats = _stats();
      _emit(EngineStatsEvent(stats).encode());
      _log(stats.logLine(sinkId: _sink.id, sampleRate: _rate));
      _emit(const EngineStateChanged(playing: false).encode());
    } on Object catch (error) {
      await _fail(error);
    }
  }

  Future<void> _fail(Object error) async {
    for (final id in soundscapeIds) {
      _master.stop(id, fade: _failureFade);
    }
    final discard = Int16List(kChunkFrames * 2);
    while (!_master.isSilent) {
      _master.render(discard, kChunkFrames);
    }
    try {
      await _metered.stop();
    } on Object {
      // The sink already failed; closing it is best effort.
    }
    if (_open) _close();
    _emit(EngineError('$error').encode());
    _emit(const EngineStateChanged(playing: false).encode());
  }

  void _beforeChunk(int _) {
    final frames = _metered.frames;
    if (frames - _statsFrames + kChunkFrames > _rate) {
      _statsFrames = frames;
      _emit(EngineStatsEvent(_stats()).encode());
    }
    if (frames - _logFrames + kChunkFrames > 10 * _rate) {
      _logFrames = frames;
      _log(_stats().logLine(sinkId: _sink.id, sampleRate: _rate));
    }
    _metered.chunkStart();
  }

  void _close() {
    _open = false;
    _closedPlayMicros += _now() - _openedAt;
    _closedUnderruns += _sink.underruns;
    _closedStarvedMicros += _sink.starvedMicros;
  }

  EngineStats _stats() => EngineStats(
    playMicros: _closedPlayMicros + (_open ? _now() - _openedAt : 0),
    renderMicros: _metered.renderMicros,
    maxRenderMicros: _metered.maxRenderMicros,
    frames: _metered.frames,
    underruns: _closedUnderruns + (_open ? _sink.underruns : 0),
    starvedMicros: _closedStarvedMicros + (_open ? _sink.starvedMicros : 0),
    overlaps: _metered.overlaps,
    faults: _master.faultBlocks,
    sessions: _sessions,
  );
}
