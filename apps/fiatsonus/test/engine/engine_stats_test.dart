import 'package:fiatsonus/src/engine/engine_stats.dart';
import 'package:flutter_test/flutter_test.dart';

const _stats = EngineStats(
  playMicros: 10000000,
  renderMicros: 150000,
  maxRenderMicros: 900,
  frames: 480000,
  underruns: 2,
  starvedMicros: 42000,
  overlaps: 0,
  faults: 1,
  sessions: 3,
);

void main() {
  test('fields round-trip in protocol order', () {
    expect(_stats.toFields(), [
      10000000,
      150000,
      900,
      480000,
      2,
      42000,
      0,
      1,
      3,
    ]);
    expect(EngineStats.fromFields(_stats.toFields()), _stats);
  });

  test('logLine is the FSTAT line', () {
    expect(
      _stats.logLine(sinkId: 'soloud', sampleRate: 48000),
      'FSTAT v=1 sink=soloud rate=48000 play_us=10000000 render_us=150000 '
      'max_render_us=900 frames=480000 underruns=2 starved_us=42000 '
      'overlaps=0 faults=1 sessions=3',
    );
  });

  test('renderRatio is render time over play time', () {
    expect(_stats.renderRatio, closeTo(0.015, 1e-12));
  });

  test('renderRatio is 0 when nothing played', () {
    expect(
      const EngineStats(
        playMicros: 0,
        renderMicros: 5,
        maxRenderMicros: 5,
        frames: 0,
        underruns: 0,
        starvedMicros: 0,
        overlaps: 0,
        faults: 0,
        sessions: 0,
      ).renderRatio,
      0,
    );
  });
}
