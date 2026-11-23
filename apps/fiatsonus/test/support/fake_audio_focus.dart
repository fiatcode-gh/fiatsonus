import 'dart:async';

import 'package:fiatsonus/src/playback/audio_focus.dart';

/// An [AudioFocus] for host tests: scripts `request` results and lets the
/// test push focus changes.
final class FakeAudioFocus implements AudioFocus {
  /// When [asyncRequest] is set, `request` completes on a later
  /// event-queue turn instead of a microtask.
  FakeAudioFocus({this.asyncRequest = false});

  final bool asyncRequest;
  final StreamController<FocusChange> _changes =
      StreamController<FocusChange>.broadcast();

  /// Result of every later `request`.
  bool grant = true;

  int requests = 0;
  int abandons = 0;

  /// Every call in order: `request` or `abandon`.
  final List<String> ops = [];

  /// While set, a `request` completes only after this completes.
  Completer<void>? gate;

  /// Delivers [change] to listeners on a later microtask.
  void push(FocusChange change) => _changes.add(change);

  @override
  Future<bool> request() {
    requests++;
    ops.add('request');
    final result = grant;
    final gate = this.gate;
    if (gate != null) return gate.future.then((_) => result);
    return asyncRequest ? Future(() => result) : Future.value(result);
  }

  @override
  Future<void> abandon() async {
    abandons++;
    ops.add('abandon');
  }

  @override
  Stream<FocusChange> get changes => _changes.stream;
}
