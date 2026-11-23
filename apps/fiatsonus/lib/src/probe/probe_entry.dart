import 'dart:isolate';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../engine/device_sink.dart';
import '../engine/engine_client.dart';
import '../engine/engine_host.dart';
import '../engine/engine_isolate.dart';
import '../engine/engine_protocol.dart';
import '../sink/soloud_pull_sink.dart';
import 'mp_clock_sink.dart';
import 'pcm_relay_sink.dart';

/// The probe's engine entry points by sink id.
const Map<String, EngineEntryPoint> probeEntryPoints = {
  'soloud': probeSoloudMain,
  'pcm': probePcmMain,
  'mp': probeMpMain,
};

@pragma('vm:entry-point')
void probeSoloudMain(List<Object> boot) {
  PathProviderPlatform.instance = _BootPathProvider(
    boot[kBootTempDir] as String,
  );
  _runProbeEngine(boot, SoloudPullSink.new);
}

@pragma('vm:entry-point')
void probePcmMain(List<Object> boot) => _runProbeEngine(boot, PcmRelaySink.new);

@pragma('vm:entry-point')
void probeMpMain(List<Object> boot) => _runProbeEngine(boot, MpClockSink.new);

/// [runEngineIsolate] with one extra command: `['param', 'probe',
/// 'stall_ms', v]` busy-waits `v` ms in the engine isolate before the
/// message is passed on.
void _runProbeEngine(List<Object> boot, DeviceSink Function() createSink) {
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
  commands.listen((message) {
    if (message case ['param', 'probe', 'stall_ms', final double ms]) {
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < ms) {}
    }
    host.handle(message);
  });
  events.send(EngineReady(sampleRate: sampleRate, sinkId: sink.id).encode());
}

final class _BootPathProvider extends PathProviderPlatform {
  _BootPathProvider(this._tempPath);

  final String _tempPath;

  @override
  Future<String?> getTemporaryPath() async => _tempPath;
}
