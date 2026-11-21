import 'dart:async';
import 'dart:typed_data';

import 'package:fiatsonus/src/engine/device_sink.dart';

/// A [DeviceSink] for host tests: records every write, counts start/stop,
/// and completes each call on a later event-queue turn, like a real device.
final class FakeDeviceSink implements DeviceSink {
  FakeDeviceSink({this.id = 'fake'});

  @override
  final String id;

  @override
  int underruns = 0;

  @override
  int starvedMicros = 0;

  int startCount = 0;
  int stopCount = 0;
  int? sampleRate;
  int? channels;

  /// A copy of every chunk handed to [write], failed writes included.
  final List<Int16List> writes = [];

  /// `start`, `write` and `stop`, in call order.
  final List<String> calls = [];

  /// Called on entry of each [write], after the chunk is recorded.
  void Function(int chunkIndex)? onWrite;

  /// When set, every write stays pending until it completes.
  Completer<void>? gate;

  /// Index of the write that fails, if any.
  int? failAtWrite;

  int get framesWritten {
    var n = 0;
    for (final w in writes) {
      n += w.length ~/ 2;
    }
    return n;
  }

  @override
  Future<void> start({required int sampleRate, required int channels}) {
    calls.add('start');
    startCount++;
    this.sampleRate = sampleRate;
    this.channels = channels;
    underruns = 0;
    starvedMicros = 0;
    return Future<void>(() {});
  }

  @override
  Future<void> write(Int16List interleaved) {
    calls.add('write');
    final index = writes.length;
    writes.add(Int16List.fromList(interleaved));
    onWrite?.call(index);
    if (index == failAtWrite) {
      return Future<void>(() => throw StateError('write $index failed'));
    }
    final g = gate;
    return Future<void>(() => g?.future);
  }

  @override
  Future<void> stop() {
    calls.add('stop');
    stopCount++;
    return Future<void>(() {});
  }
}
