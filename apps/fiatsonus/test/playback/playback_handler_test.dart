import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:fiatsonus/src/engine/device_sink.dart';
import 'package:fiatsonus/src/engine/engine_protocol.dart';
import 'package:fiatsonus/src/engine/engine_stats.dart';
import 'package:fiatsonus/src/playback/audio_focus.dart';
import 'package:fiatsonus/src/playback/playback_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_audio_focus.dart';
import '../support/fake_engine_client.dart';

const _scape = 'waterfall';

/// A [PlaybackHandler] wired to fakes, with everything it does recorded.
final class _Rig {
  _Rig({
    bool echoState = false,
    bool asyncFocus = false,
    Future<void> Function()? permission,
  }) : engine = FakeEngineClient(echoState: echoState),
       focus = FakeAudioFocus(asyncRequest: asyncFocus) {
    handler = PlaybackHandler(
      engine: engine,
      focus: focus,
      requestNotificationPermission:
          permission ??
          () async {
            permissionRequests++;
          },
      soundscapeId: _scape,
      title: 'Waterfall',
      log: log.add,
    );
  }

  final FakeEngineClient engine;
  final FakeAudioFocus focus;
  final List<String> log = [];
  int permissionRequests = 0;
  late final PlaybackHandler handler;

  PlaybackPhase get phase => handler.phase.value;
  PlaybackState get state => handler.playbackState.value;

  Future<void> engineState(bool playing) async {
    engine.push(EngineStateChanged(playing: playing));
    await pumpEventQueue();
  }

  Future<void> focusChange(FocusChange change) async {
    focus.push(change);
    await pumpEventQueue();
  }

  /// Plays, then lets the engine report that it opened the sink.
  Future<void> playing() async {
    await handler.play();
    await engineState(true);
  }
}

void main() {
  test('construction publishes the media item and an idle state', () {
    final rig = _Rig();

    expect(rig.handler.mediaItem.value?.id, _scape);
    expect(rig.handler.mediaItem.value?.title, 'Waterfall');
    expect(rig.state.processingState, AudioProcessingState.idle);
    expect(rig.state.playing, isFalse);
    expect(rig.phase, PlaybackPhase.idle);
  });

  test('play asks permission, takes focus and starts the engine', () async {
    final rig = _Rig();

    await rig.handler.play();

    expect(rig.permissionRequests, 1);
    expect(rig.focus.requests, 1);
    expect(rig.engine.calls, [
      (op: 'start', soundscapeId: _scape, fade: kPlayFade),
    ]);
    expect(kPlayFade, const Duration(seconds: 2));
    expect(rig.phase, PlaybackPhase.playing);
    expect(rig.state.playing, isTrue);
    expect(rig.state.processingState, AudioProcessingState.ready);
    expect(rig.state.controls, [MediaControl.stop]);
  });

  for (final (name, end) in [
    ('stop', (PlaybackHandler h) => h.stop()),
    ('pause', (PlaybackHandler h) => h.pause()),
  ]) {
    test('$name fades out, then goes idle once the engine stops', () async {
      final rig = _Rig();
      await rig.playing();

      await end(rig.handler);

      expect(rig.engine.calls.last, (
        op: 'stop',
        soundscapeId: _scape,
        fade: const Duration(seconds: 3),
      ));
      expect(rig.phase, PlaybackPhase.stopping);
      expect(rig.state.playing, isTrue);
      expect(rig.focus.abandons, 0);

      await rig.engineState(false);

      expect(rig.phase, PlaybackPhase.idle);
      expect(rig.state.processingState, AudioProcessingState.idle);
      expect(rig.state.playing, isFalse);
      expect(rig.focus.abandons, 1);
    });
  }

  test('a transient loss interrupts and a gain resumes', () async {
    final rig = _Rig();
    await rig.playing();

    await rig.focusChange(FocusChange.lossTransient);

    expect(rig.engine.calls.last, (
      op: 'stop',
      soundscapeId: _scape,
      fade: const Duration(milliseconds: 200),
    ));
    expect(rig.phase, PlaybackPhase.interrupted);
    expect(rig.state.playing, isFalse);
    expect(rig.state.processingState, AudioProcessingState.ready);
    expect(rig.state.controls, [MediaControl.stop]);

    await rig.engineState(false);
    expect(rig.phase, PlaybackPhase.interrupted);
    expect(rig.focus.abandons, 0);

    await rig.focusChange(FocusChange.gain);

    expect(rig.engine.calls.last, (
      op: 'start',
      soundscapeId: _scape,
      fade: kPlayFade,
    ));
    expect(rig.phase, PlaybackPhase.playing);
    expect(rig.state.playing, isTrue);
  });

  test('a gain without an interruption does nothing', () async {
    final rig = _Rig();
    await rig.playing();

    await rig.focusChange(FocusChange.gain);

    expect(rig.engine.ops, ['start']);
    expect(rig.phase, PlaybackPhase.playing);
  });

  test('a transient loss while idle does nothing', () async {
    final rig = _Rig();

    await rig.focusChange(FocusChange.lossTransient);
    await rig.focusChange(FocusChange.gain);

    expect(rig.engine.calls, isEmpty);
    expect(rig.phase, PlaybackPhase.idle);
    expect(rig.state.processingState, AudioProcessingState.idle);
  });

  test('a permanent loss while playing ends playback', () async {
    final rig = _Rig();
    await rig.playing();

    await rig.focusChange(FocusChange.lossPermanent);

    expect(rig.engine.calls.last.op, 'stop');
    expect(rig.engine.calls.last.fade, kStopFade);
    expect(rig.phase, PlaybackPhase.stopping);

    await rig.engineState(false);

    expect(rig.phase, PlaybackPhase.idle);
    expect(rig.state.processingState, AudioProcessingState.idle);
    expect(rig.focus.abandons, 1);
  });

  test('a permanent loss while interrupted and stopped ends at once', () async {
    final rig = _Rig();
    await rig.playing();
    await rig.focusChange(FocusChange.lossTransient);
    await rig.engineState(false);

    await rig.focusChange(FocusChange.lossPermanent);

    expect(rig.engine.ops, ['start', 'stop']);
    expect(rig.phase, PlaybackPhase.idle);
    expect(rig.state.processingState, AudioProcessingState.idle);
    expect(rig.focus.abandons, 1);
  });

  test('a permanent loss while interrupted and still fading waits for the '
      'engine', () async {
    final rig = _Rig();
    await rig.playing();
    await rig.focusChange(FocusChange.lossTransient);

    await rig.focusChange(FocusChange.lossPermanent);

    expect(rig.engine.ops, ['start', 'stop', 'stop']);
    expect(rig.phase, PlaybackPhase.stopping);

    await rig.engineState(false);
    expect(rig.phase, PlaybackPhase.idle);
  });

  test('denied focus stays idle and reports the error', () async {
    final rig = _Rig();
    rig.focus.grant = false;

    await rig.handler.play();

    expect(rig.phase, PlaybackPhase.idle);
    expect(rig.handler.lastError.value, 'Audio focus denied');
    expect(rig.engine.calls, isEmpty);
    expect(rig.state.playing, isFalse);
  });

  test('play while stopping resumes and ignores the late stop', () async {
    final rig = _Rig();
    await rig.playing();
    await rig.handler.stop();

    await rig.handler.play();

    expect(rig.engine.ops, ['start', 'stop', 'start']);
    expect(rig.phase, PlaybackPhase.playing);

    await rig.engineState(false);

    expect(rig.phase, PlaybackPhase.playing);
    expect(rig.state.playing, isTrue);
    expect(rig.focus.abandons, 0);
  });

  test('an engine error while playing goes idle', () async {
    final rig = _Rig();
    await rig.playing();

    rig.engine.push(const EngineError('sink failed'));
    await pumpEventQueue();

    expect(rig.phase, PlaybackPhase.idle);
    expect(rig.state.processingState, AudioProcessingState.idle);
    expect(rig.handler.lastError.value, 'sink failed');
    expect(rig.focus.abandons, 1);
  });

  test('stats events reach the stats listenable', () async {
    final rig = _Rig();
    const stats = EngineStats(
      playMicros: 1,
      renderMicros: 2,
      maxRenderMicros: 3,
      frames: 4,
      underruns: 5,
      starvedMicros: 6,
      overlaps: 7,
      faults: 8,
      sessions: 9,
    );

    rig.engine.push(const EngineStatsEvent(stats));
    await pumpEventQueue();

    expect(rig.handler.stats.value, stats);
  });

  test('setParam forwards to the engine for the soundscape', () {
    final rig = _Rig();

    rig.handler.setParam('flow', 0.25);

    expect(rig.engine.params, [(_scape, 'flow', 0.25)]);
  });

  for (final count in [100, 101]) {
    test('$count fast toggles settle on the final intent', () async {
      final rig = _Rig(echoState: true, asyncFocus: true);
      final random = Random(count);

      for (var i = 0; i < count; i++) {
        rig.handler.toggle();
        await pumpEventQueue(times: random.nextInt(4));
      }
      await pumpEventQueue();

      final want = count.isOdd;
      expect(rig.phase, want ? PlaybackPhase.playing : PlaybackPhase.idle);
      expect(rig.state.playing, want);
      final ops = rig.engine.ops;
      expect(ops.length, greaterThan(10), reason: 'toggles must interleave');
      expect(ops.first, 'start');
      for (var i = 1; i < ops.length; i++) {
        expect(ops[i], isNot(ops[i - 1]), reason: 'engine call $i');
      }
      expect(ops.last, want ? 'start' : 'stop');
    });
  }

  test('permission is asked once across three plays', () async {
    final rig = _Rig();

    for (var i = 0; i < 3; i++) {
      await rig.playing();
      await rig.handler.stop();
      await rig.engineState(false);
    }

    expect(rig.permissionRequests, 1);
    expect(rig.engine.ops, ['start', 'stop', 'start', 'stop', 'start', 'stop']);
  });

  test('a failing permission request does not block playback', () async {
    final rig = _Rig(permission: () async => throw StateError('no channel'));

    await rig.handler.play();

    expect(rig.phase, PlaybackPhase.playing);
    expect(rig.engine.ops, ['start']);
  });

  test('each phase change logs one FSTATE line', () async {
    final rig = _Rig();

    await rig.playing();
    await rig.focusChange(FocusChange.lossTransient);
    await rig.focusChange(FocusChange.gain);
    await rig.handler.stop();
    await rig.engineState(false);

    expect(rig.log, [
      'FSTATE phase=playing',
      'FSTATE phase=interrupted',
      'FSTATE phase=playing',
      'FSTATE phase=stopping',
      'FSTATE phase=idle',
    ]);
  });
}
