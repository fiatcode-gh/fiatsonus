import 'dart:async';
import 'dart:isolate';

import 'engine_isolate.dart';
import 'engine_protocol.dart';

/// The UI isolate's handle on the engine (PLAN 4.2, 4.3).
abstract interface class EngineClient {
  /// Engine events; a broadcast stream.
  Stream<EngineEvent> get events;

  void start(String soundscapeId, {required Duration fade});

  void stop(String soundscapeId, {required Duration fade});

  void setParam(String soundscapeId, String paramId, double value);
}

/// Entry point of the engine isolate; receives the boot list of
/// [runEngineIsolate].
typedef EngineEntryPoint = void Function(List<Object> boot);

/// An [EngineClient] on an engine running in its own isolate.
final class IsolateEngineClient implements EngineClient {
  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _eventPort;
  final ReceivePort _errorPort;
  final StreamController<EngineEvent> _events;

  /// Sample rate of the engine, from its `ready` event.
  final int sampleRate;

  /// Id of the engine's sink, from its `ready` event.
  final String sinkId;

  /// The first uncaught isolate error after `ready`; the isolate is dead.
  String? _failure;

  IsolateEngineClient._(
    this._isolate,
    this._commands,
    this._eventPort,
    this._errorPort,
    this._events,
    this.sampleRate,
    this.sinkId,
  );

  /// Spawns the engine isolate at [entryPoint] and completes after its
  /// `ready` event. Throws a [StateError] with the message of an `error`
  /// event or an uncaught isolate error that arrives first.
  static Future<IsolateEngineClient> spawn({
    required int sampleRate,
    required int seed,
    required String tempDirPath,
    required EngineEntryPoint entryPoint,
  }) async {
    final eventPort = ReceivePort();
    final errorPort = ReceivePort();
    final events = StreamController<EngineEvent>.broadcast();
    final ready = Completer<EngineReady>();
    SendPort? commands;
    IsolateEngineClient? client;

    void fail(String message) {
      if (ready.isCompleted) {
        client?._died(message);
      } else {
        ready.completeError(StateError(message));
      }
    }

    eventPort.listen((raw) {
      if (raw case ['port', final SendPort port]) {
        commands = port;
        return;
      }
      final event = EngineEvent.decode(raw);
      if (event == null) return;
      if (ready.isCompleted) {
        events.add(event);
      } else if (event is EngineReady) {
        ready.complete(event);
      } else if (event is EngineError) {
        fail(event.message);
      }
    });
    errorPort.listen((raw) {
      if (raw case [final Object? error, _]) fail('$error');
    });

    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<List<Object>>(entryPoint, [
        eventPort.sendPort,
        sampleRate,
        seed,
        tempDirPath,
      ], onError: errorPort.sendPort);
    } on Object {
      eventPort.close();
      errorPort.close();
      await events.close();
      rethrow;
    }

    final EngineReady event;
    try {
      event = await ready.future;
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      eventPort.close();
      errorPort.close();
      await events.close();
      rethrow;
    }
    return client = IsolateEngineClient._(
      isolate,
      commands!,
      eventPort,
      errorPort,
      events,
      event.sampleRate,
      event.sinkId,
    );
  }

  @override
  Stream<EngineEvent> get events => _events.stream;

  /// An uncaught error ends the engine isolate (errors are fatal there), so
  /// nothing answers a later command. From then on the client answers every
  /// `start` itself, the way a failed sink does (PLAN 4.4).
  void _died(String message) {
    _failure ??= message;
    _reportFailure();
  }

  void _reportFailure() {
    _events
      ..add(EngineError(_failure!))
      ..add(const EngineStateChanged(playing: false));
  }

  @override
  void start(String soundscapeId, {required Duration fade}) {
    if (_failure != null) {
      _reportFailure();
      return;
    }
    _commands.send(EngineCommand.start(soundscapeId, fade));
  }

  @override
  void stop(String soundscapeId, {required Duration fade}) =>
      _commands.send(EngineCommand.stop(soundscapeId, fade));

  @override
  void setParam(String soundscapeId, String paramId, double value) =>
      _commands.send(EngineCommand.param(soundscapeId, paramId, value));

  /// Kills the engine isolate and closes [events].
  Future<void> dispose() async {
    _isolate.kill(priority: Isolate.immediate);
    _eventPort.close();
    _errorPort.close();
    await _events.close();
  }
}
