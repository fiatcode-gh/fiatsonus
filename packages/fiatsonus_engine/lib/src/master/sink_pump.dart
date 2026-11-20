import 'dart:typed_data';

import '../core/audio_sink.dart';
import 'master.dart';

/// The engine's only asynchronous loop (S6): renders [Master] output in
/// chunks and writes each chunk to an [AudioSink], one write at a time.
///
/// Starting a new [run] or calling [cancel] supersedes the running loop,
/// which returns after its current write without rendering again. The pump
/// never starts or stops the sink or the master's soundscapes.
final class SinkPump {
  final Master _master;
  final AudioSink _sink;
  final int _chunkFrames;
  final Int16List _buffer;
  Future<void>? _inFlight;
  int _session = 0;

  SinkPump(Master master, AudioSink sink, {int chunkFrames = 1024})
    : _master = master,
      _sink = sink,
      _chunkFrames = chunkFrames,
      _buffer = Int16List(chunkFrames * 2);

  /// Number of runs started or cancelled so far.
  int get session => _session;

  /// Pumps [frames] frames, or until the master is silent when [frames] is
  /// null, calling [beforeChunk] with the frames written so far before each
  /// chunk. Returns the frames written by this run. Errors from the sink's
  /// `write` complete the returned future.
  Future<int> run({
    int? frames,
    void Function(int written)? beforeChunk,
  }) async {
    final my = ++_session;
    final previous = _inFlight;
    if (previous != null) {
      try {
        await previous;
      } on Object {
        // The run that issued this write receives its error.
      }
    }
    var written = 0;
    while (true) {
      if (my != _session) break;
      if (frames != null && written >= frames) break;
      if (frames == null && _master.isSilent) break;
      beforeChunk?.call(written);
      final n = frames == null || frames - written >= _chunkFrames
          ? _chunkFrames
          : frames - written;
      _master.render(_buffer, n);
      final write = _sink.write(
        n == _chunkFrames ? _buffer : Int16List.sublistView(_buffer, 0, n * 2),
      );
      _inFlight = write;
      await write;
      written += n;
    }
    return written;
  }

  /// Supersedes the running loop.
  void cancel() {
    _session++;
  }
}
