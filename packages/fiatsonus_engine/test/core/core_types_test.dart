import 'dart:typed_data';

import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:test/test.dart';

void main() {
  test('kBlockFrames is 256 and kMaxVoices is 64', () {
    expect(kBlockFrames, 256);
    expect(kMaxVoices, 64);
  });

  test('ParamSpec keeps its fields and defaults smoothing to 200 ms', () {
    final spec = ParamSpec('flow', 'Flow', 0.6);
    expect(spec.id, 'flow');
    expect(spec.label, 'Flow');
    expect(spec.defaultValue, 0.6);
    expect(spec.smoothing, const Duration(milliseconds: 200));

    const custom = ParamSpec(
      'distance',
      'Distance',
      0.4,
      smoothing: Duration(milliseconds: 500),
    );
    expect(custom.smoothing, const Duration(milliseconds: 500));
    expect(custom.defaultValue, 0.4);
  });

  test('AudioSink can be implemented', () async {
    final sink = _RecordingSink();
    await sink.start(sampleRate: 48000, channels: 2);
    await sink.write(Int16List(4));
    await sink.stop();
    expect(sink.events, ['start 48000 2', 'write 4', 'stop']);
  });
}

final class _RecordingSink implements AudioSink {
  final List<String> events = [];

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    events.add('start $sampleRate $channels');
  }

  @override
  Future<void> write(Int16List interleaved) async {
    events.add('write ${interleaved.length}');
  }

  @override
  Future<void> stop() async {
    events.add('stop');
  }
}
