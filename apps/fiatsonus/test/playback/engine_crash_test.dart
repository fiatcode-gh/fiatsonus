import 'package:audio_service/audio_service.dart';
import 'package:fiatsonus/src/engine/engine_client.dart';
import 'package:fiatsonus/src/playback/playback_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_audio_focus.dart';
import '../support/fake_engine_entry.dart';

/// Completes once [handler] is in [phase].
Future<void> _reaches(PlaybackHandler handler, PlaybackPhase phase) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (handler.phase.value != phase) {
    if (DateTime.now().isAfter(deadline)) {
      fail('phase is ${handler.phase.value.name}, not ${phase.name}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('play and stop still end idle after the engine isolate died', () async {
    final engine = await IsolateEngineClient.spawn(
      sampleRate: 48000,
      seed: 7,
      tempDirPath: '/tmp',
      entryPoint: crashingEngineMain,
    );
    addTearDown(engine.dispose);
    final focus = FakeAudioFocus();
    final handler = PlaybackHandler(
      engine: engine,
      focus: focus,
      requestNotificationPermission: () async {},
      clearPlaybackNotification: () async {},
      soundscapeId: 'waterfall',
      title: 'Waterfall',
      log: (_) {},
    );

    await handler.play();
    await _reaches(handler, PlaybackPhase.idle);
    expect(handler.lastError.value, contains('engine crashed'));

    await handler.play();
    await handler.stop();
    await _reaches(handler, PlaybackPhase.idle);

    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    expect(focus.ops.last, 'abandon');
  });
}
