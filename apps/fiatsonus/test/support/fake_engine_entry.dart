import 'dart:typed_data';

import 'package:fiatsonus/src/engine/device_sink.dart';
import 'package:fiatsonus/src/engine/engine_isolate.dart';

/// Engine isolate entry point on a [_StrictFakeSink].
void fakeEngineMain(List<Object> boot) {
  runEngineIsolate(boot, _StrictFakeSink.new);
}

/// Engine isolate entry point on a sink whose `start` always throws.
void failingEngineMain(List<Object> boot) {
  runEngineIsolate(boot, _FailingSink.new);
}

/// A [DeviceSink] that paces writes on the event queue and throws on any
/// misuse: a write before start, a second start, or overlapping writes.
final class _StrictFakeSink implements DeviceSink {
  bool _started = false;
  bool _pending = false;

  @override
  String get id => 'fake';

  @override
  int get underruns => 0;

  @override
  int get starvedMicros => 0;

  @override
  Future<void> start({required int sampleRate, required int channels}) {
    if (_started) throw StateError('second start');
    _started = true;
    return Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> write(Int16List interleaved) {
    if (!_started) throw StateError('write before start');
    if (_pending) throw StateError('write while one is pending');
    _pending = true;
    return Future<void>.delayed(Duration.zero, () => _pending = false);
  }

  @override
  Future<void> stop() {
    _started = false;
    return Future<void>.delayed(Duration.zero);
  }
}

/// A [DeviceSink] whose `start` fails.
final class _FailingSink implements DeviceSink {
  @override
  String get id => 'failing';

  @override
  int get underruns => 0;

  @override
  int get starvedMicros => 0;

  @override
  Future<void> start({required int sampleRate, required int channels}) =>
      throw StateError('sink start failed');

  @override
  Future<void> write(Int16List interleaved) =>
      throw StateError('write on a failed sink');

  @override
  Future<void> stop() => Future<void>.delayed(Duration.zero);
}
