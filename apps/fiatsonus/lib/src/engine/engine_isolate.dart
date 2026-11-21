import 'dart:isolate';

import 'device_sink.dart';
import 'engine_host.dart';
import 'engine_protocol.dart';

/// Boot list indices: 0 events SendPort, 1 sampleRate, 2 seed, 3 tempDirPath.
const int kBootEvents = 0, kBootSampleRate = 1, kBootSeed = 2, kBootTempDir = 3;

/// Runs the engine in the current isolate until it is killed.
///
/// Answers `['port', SendPort]`, builds the sink with [createSink] and the
/// [EngineHost], sends `ready`, then hands every received message to the
/// host. A failure while building is sent as an `error` event.
void runEngineIsolate(List<Object> boot, DeviceSink Function() createSink) {
  final events = boot[kBootEvents] as SendPort;
  final commands = ReceivePort();
  events.send(['port', commands.sendPort]);
  final EngineHost host;
  final DeviceSink sink;
  final int sampleRate;
  try {
    sampleRate = boot[kBootSampleRate] as int;
    sink = createSink();
    host = EngineHost(
      sampleRate: sampleRate,
      seed: boot[kBootSeed] as int,
      sink: sink,
      emit: events.send,
    );
  } on Object catch (error) {
    commands.close();
    events.send(EngineError('$error').encode());
    return;
  }
  commands.listen(host.handle);
  events.send(EngineReady(sampleRate: sampleRate, sinkId: sink.id).encode());
}
