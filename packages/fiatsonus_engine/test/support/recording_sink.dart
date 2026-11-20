import 'dart:async';
import 'dart:typed_data';

import 'package:fiatsonus_engine/src/core/audio_sink.dart';

/// Sink test double that copies every write and records start/stop calls.
final class RecordingSink implements AudioSink {
  RecordingSink({this.deferWrites = false, this.writeError});

  /// When true, each write completes on a later microtask.
  final bool deferWrites;

  /// When set, every write completes with this error.
  final Object? writeError;

  /// While set, a write completes only when this completes.
  Completer<void>? gate;

  final List<Int16List> writes = [];
  int startCalls = 0;
  int stopCalls = 0;

  /// All written samples, concatenated.
  Int16List get data {
    var length = 0;
    for (final w in writes) {
      length += w.length;
    }
    final out = Int16List(length);
    var at = 0;
    for (final w in writes) {
      out.setAll(at, w);
      at += w.length;
    }
    return out;
  }

  /// Number of written stereo frames.
  int get frames => data.length ~/ 2;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    startCalls++;
  }

  @override
  Future<void> write(Int16List interleaved) {
    writes.add(Int16List.fromList(interleaved));
    final error = writeError;
    if (error != null) return Future<void>.error(error);
    final g = gate;
    if (g != null) return g.future;
    if (deferWrites) return Future<void>.microtask(() {});
    return Future<void>.value();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}
