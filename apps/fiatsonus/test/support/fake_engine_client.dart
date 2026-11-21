import 'dart:async';

import 'package:fiatsonus/src/engine/engine_client.dart';
import 'package:fiatsonus/src/engine/engine_protocol.dart';

/// One recorded [EngineClient] command.
typedef EngineCall = ({String op, String soundscapeId, Duration? fade});

/// An [EngineClient] for host tests: records commands and lets the test
/// push events.
final class FakeEngineClient implements EngineClient {
  /// When [echoState] is set, each `start` is answered with
  /// `state(true)` and each `stop` with `state(false)` on a later
  /// event-queue turn, like an engine whose fades are instant.
  FakeEngineClient({this.echoState = false});

  final bool echoState;
  final StreamController<EngineEvent> _events =
      StreamController<EngineEvent>.broadcast();

  final List<EngineCall> calls = [];
  final List<(String, String, double)> params = [];

  List<String> get ops => [for (final c in calls) c.op];

  /// Delivers [event] to listeners on a later microtask.
  void push(EngineEvent event) => _events.add(event);

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  void start(String soundscapeId, {required Duration fade}) {
    calls.add((op: 'start', soundscapeId: soundscapeId, fade: fade));
    if (echoState) {
      Timer.run(() => push(const EngineStateChanged(playing: true)));
    }
  }

  @override
  void stop(String soundscapeId, {required Duration fade}) {
    calls.add((op: 'stop', soundscapeId: soundscapeId, fade: fade));
    if (echoState) {
      Timer.run(() => push(const EngineStateChanged(playing: false)));
    }
  }

  @override
  void setParam(String soundscapeId, String paramId, double value) =>
      params.add((soundscapeId, paramId, value));
}
