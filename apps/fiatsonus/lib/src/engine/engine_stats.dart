/// Engine counters, cumulative since the engine started (PLAN 4.5).
final class EngineStats {
  /// Wall time inside sessions.
  final int playMicros;

  /// Time spent rendering chunks.
  final int renderMicros;

  /// Longest render of one chunk.
  final int maxRenderMicros;

  /// Frames handed to the sink.
  final int frames;

  /// Sink underruns across every session.
  final int underruns;

  /// Starved output time across every session.
  final int starvedMicros;

  /// Writes entered while one was pending. Must stay 0.
  final int overlaps;

  /// Blocks muted by the master's non-finite guard.
  final int faults;

  /// Times a session opened the sink.
  final int sessions;

  const EngineStats({
    required this.playMicros,
    required this.renderMicros,
    required this.maxRenderMicros,
    required this.frames,
    required this.underruns,
    required this.starvedMicros,
    required this.overlaps,
    required this.faults,
    required this.sessions,
  });

  static const EngineStats zero = EngineStats(
    playMicros: 0,
    renderMicros: 0,
    maxRenderMicros: 0,
    frames: 0,
    underruns: 0,
    starvedMicros: 0,
    overlaps: 0,
    faults: 0,
    sessions: 0,
  );

  /// Reads the fields in [toFields] order. Throws when [fields] does not
  /// hold exactly nine ints.
  factory EngineStats.fromFields(List<Object?> fields) {
    if (fields.length != 9) {
      throw ArgumentError.value(fields, 'fields', 'needs 9 ints');
    }
    int at(int i) => fields[i] as int;
    return EngineStats(
      playMicros: at(0),
      renderMicros: at(1),
      maxRenderMicros: at(2),
      frames: at(3),
      underruns: at(4),
      starvedMicros: at(5),
      overlaps: at(6),
      faults: at(7),
      sessions: at(8),
    );
  }

  /// Engine CPU share: render time over play time; 0 before any play.
  double get renderRatio => playMicros == 0 ? 0 : renderMicros / playMicros;

  List<int> toFields() => [
    playMicros,
    renderMicros,
    maxRenderMicros,
    frames,
    underruns,
    starvedMicros,
    overlaps,
    faults,
    sessions,
  ];

  /// The `FSTAT` log line.
  String logLine({required String sinkId, required int sampleRate}) =>
      'FSTAT v=1 sink=$sinkId rate=$sampleRate play_us=$playMicros '
      'render_us=$renderMicros max_render_us=$maxRenderMicros frames=$frames '
      'underruns=$underruns starved_us=$starvedMicros overlaps=$overlaps '
      'faults=$faults sessions=$sessions';

  @override
  bool operator ==(Object other) =>
      other is EngineStats &&
      other.playMicros == playMicros &&
      other.renderMicros == renderMicros &&
      other.maxRenderMicros == maxRenderMicros &&
      other.frames == frames &&
      other.underruns == underruns &&
      other.starvedMicros == starvedMicros &&
      other.overlaps == overlaps &&
      other.faults == faults &&
      other.sessions == sessions;

  @override
  int get hashCode => Object.hashAll(toFields());

  @override
  String toString() => 'EngineStats(${toFields().join(', ')})';
}
