import 'engine_stats.dart';

/// Messages from the UI isolate to the engine isolate (PLAN 4.3): plain
/// lists of `String`, `int` and `double`.
abstract final class EngineCommand {
  static List<Object> start(String soundscapeId, Duration fade) => [
    'start',
    soundscapeId,
    fade.inMilliseconds,
  ];

  static List<Object> stop(String soundscapeId, Duration fade) => [
    'stop',
    soundscapeId,
    fade.inMilliseconds,
  ];

  static List<Object> param(
    String soundscapeId,
    String paramId,
    double value,
  ) => ['param', soundscapeId, paramId, value];
}

/// Messages from the engine isolate to the UI isolate (PLAN 4.3).
sealed class EngineEvent {
  const EngineEvent();

  List<Object> encode();

  /// The event [raw] encodes, or null for anything malformed.
  static EngineEvent? decode(Object? raw) => switch (raw) {
    ['ready', final int sampleRate, final String sinkId] => EngineReady(
      sampleRate: sampleRate,
      sinkId: sinkId,
    ),
    ['state', final bool playing] => EngineStateChanged(playing: playing),
    ['stats', ...final fields]
        when fields.length == 9 && fields.every((f) => f is int) =>
      EngineStatsEvent(EngineStats.fromFields(fields)),
    ['error', final String message] => EngineError(message),
    _ => null,
  };
}

/// The engine isolate is running its sink at [sampleRate].
final class EngineReady extends EngineEvent {
  final int sampleRate;
  final String sinkId;

  const EngineReady({required this.sampleRate, required this.sinkId});

  @override
  List<Object> encode() => ['ready', sampleRate, sinkId];
}

/// [playing] is true when a session opened the sink, false after it closed.
final class EngineStateChanged extends EngineEvent {
  final bool playing;

  const EngineStateChanged({required this.playing});

  @override
  List<Object> encode() => ['state', playing];
}

/// A snapshot of the engine counters.
final class EngineStatsEvent extends EngineEvent {
  final EngineStats stats;

  const EngineStatsEvent(this.stats);

  @override
  List<Object> encode() => ['stats', ...stats.toFields()];
}

/// The sink failed; [message] describes the error.
final class EngineError extends EngineEvent {
  final String message;

  const EngineError(this.message);

  @override
  List<Object> encode() => ['error', message];
}
