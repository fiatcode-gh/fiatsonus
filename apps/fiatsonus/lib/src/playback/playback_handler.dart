import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../engine/device_sink.dart';
import '../engine/engine_client.dart';
import '../engine/engine_log.dart';
import '../engine/engine_protocol.dart';
import '../engine/engine_stats.dart';
import 'audio_focus.dart';

/// Where playback is, as the media session sees it.
enum PlaybackPhase { idle, playing, interrupted, stopping }

/// The media session of one soundscape (PLAN 4.6, 4.7).
///
/// The user's intent is reconciled with the phase by one loop at a time;
/// engine and focus events move the phase in between. The handler only
/// talks to the engine through [EngineClient].
final class PlaybackHandler extends BaseAudioHandler {
  PlaybackHandler({
    required EngineClient engine,
    required AudioFocus focus,
    required this._requestNotificationPermission,
    required this._clearPlaybackNotification,
    required String soundscapeId,
    required String title,
    this._log = logLine,
  }) : _engine = engine,
       _focus = focus,
       _id = soundscapeId {
    mediaItem.add(MediaItem(id: soundscapeId, title: title));
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle),
    );
    engine.events.listen(_onEngineEvent);
    focus.changes.listen(_onFocusChange);
  }

  final EngineClient _engine;
  final AudioFocus _focus;
  final Future<void> Function() _requestNotificationPermission;
  final Future<void> Function() _clearPlaybackNotification;
  final String _id;
  final void Function(String line) _log;

  final ValueNotifier<PlaybackPhase> _phase = ValueNotifier(PlaybackPhase.idle);
  final ValueNotifier<EngineStats?> _stats = ValueNotifier(null);
  final ValueNotifier<String?> _lastError = ValueNotifier(null);

  /// The user's intent.
  bool _want = false;

  /// The engine's last reported state, or true once a start was sent.
  bool _engineRunning = false;
  bool _permissionAsked = false;
  bool _reconciling = false;

  /// A focus request is in flight; [_begin] owns its outcome.
  bool _focusPending = false;

  ValueListenable<PlaybackPhase> get phase => _phase;
  ValueListenable<EngineStats?> get stats => _stats;
  ValueListenable<String?> get lastError => _lastError;

  /// Flips the user's intent.
  void toggle() {
    _want = !_want;
    unawaited(_reconcile());
  }

  void setParam(String paramId, double value) =>
      _engine.setParam(_id, paramId, value);

  @override
  Future<void> play() {
    _want = true;
    return _reconcile();
  }

  /// Treated as [stop]: a pause from the system controls ends playback.
  @override
  Future<void> pause() => stop();

  @override
  Future<void> stop() {
    _want = false;
    return _reconcile();
  }

  Future<void> _reconcile() async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      while (true) {
        final phase = _phase.value;
        if (_want &&
            (phase == PlaybackPhase.idle || phase == PlaybackPhase.stopping)) {
          await _begin();
        } else if (!_want &&
            (phase == PlaybackPhase.playing ||
                phase == PlaybackPhase.interrupted)) {
          _end(phase);
        } else {
          return;
        }
      }
    } finally {
      _reconciling = false;
    }
  }

  Future<void> _begin() async {
    if (!_permissionAsked) {
      _permissionAsked = true;
      try {
        await _requestNotificationPermission();
      } on Object {
        // Playback does not depend on the permission.
      }
    }
    final bool ok;
    _focusPending = true;
    try {
      ok = await _focus.request();
    } finally {
      _focusPending = false;
    }
    if (_want && !ok) {
      _want = false;
      _lastError.value = 'Audio focus denied';
    }
    if (!_want) {
      if (_phase.value == PlaybackPhase.idle) await _focus.abandon();
      return;
    }
    _setPhase(PlaybackPhase.playing);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
        playing: true,
        controls: [MediaControl.stop],
      ),
    );
    _startEngine();
  }

  void _end(PlaybackPhase from) {
    _setPhase(PlaybackPhase.stopping);
    if (from == PlaybackPhase.interrupted && !_engineRunning) {
      _finish();
    } else {
      _engine.stop(_id, fade: kStopFade);
    }
  }

  /// Idle with `playing: false` makes audio_service leave the foreground and
  /// cancel its notification. Android strips the notification's
  /// foreground-service flag asynchronously and ignores an app's cancel
  /// while the flag is set, so audio_service's cancel can be lost;
  /// [_clearPlaybackNotification] cancels it again once the flag is gone.
  void _finish() {
    _setPhase(PlaybackPhase.idle);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    if (!_focusPending) unawaited(_focus.abandon());
    unawaited(_clearPlaybackNotification());
  }

  void _startEngine() {
    _engineRunning = true;
    _engine.start(_id, fade: kPlayFade);
  }

  void _setPhase(PlaybackPhase phase) {
    if (_phase.value == phase) return;
    _phase.value = phase;
    _log('FSTATE phase=${phase.name}');
  }

  void _onEngineEvent(EngineEvent event) {
    switch (event) {
      case EngineStateChanged(:final playing):
        _engineRunning = playing;
        if (!playing && _phase.value == PlaybackPhase.stopping) _finish();
      case EngineStatsEvent(:final stats):
        _stats.value = stats;
      case EngineError(:final message):
        _want = false;
        _lastError.value = message;
        _finish();
      case EngineReady():
        break;
    }
  }

  /// A transient loss keeps `playing` true: audio_service leaves the
  /// foreground whenever `playing` turns false, and the service must not be
  /// started again from the background. `playing` turns false only with
  /// `idle`, in [_finish].
  void _onFocusChange(FocusChange change) {
    final phase = _phase.value;
    switch (change) {
      case FocusChange.lossTransient when phase == PlaybackPhase.playing:
        _setPhase(PlaybackPhase.interrupted);
        _engine.stop(_id, fade: kInterruptFade);
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.buffering,
            controls: [MediaControl.stop],
          ),
        );
      case FocusChange.gain when phase == PlaybackPhase.interrupted && _want:
        _setPhase(PlaybackPhase.playing);
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.ready,
          ),
        );
        _startEngine();
      case FocusChange.lossPermanent
          when phase == PlaybackPhase.playing ||
              phase == PlaybackPhase.interrupted:
        _want = false;
        unawaited(_reconcile());
      case _:
        break;
    }
  }
}
