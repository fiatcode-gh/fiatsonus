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

  /// Delivers [change] to listeners on a later microtask.
  void push(FocusChange change) => _changes.add(change);

  @override
  Future<bool> request() {
    requests++;
    final result = grant;
    return asyncRequest ? Future(() => result) : Future.value(result);
  }

  @override
  Future<void> abandon() async {
    abandons++;
  }

  @override
  Stream<FocusChange> get changes => _changes.stream;
}
