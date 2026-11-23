import 'package:fiatsonus_engine/profiling.dart';
import 'package:test/test.dart';

final RegExp _line = RegExp(
  r'^FBENCH v=1 stage=(\w+) rate=(\d+) secs=(\d+) run=(\d+) '
  r'us_per_s=(\d+) factor=(\d+\.\d)$',
);

void main() {
  test('every stage measures a positive time', () {
    for (final stage in BenchStage.values) {
      final r = runStage(stage, run: 1, seconds: 1, leadSeconds: 0);
      expect(r.stage, stage);
      expect(r.sampleRate, 48000);
      expect(r.seconds, 1);
      expect(r.run, 1);
      expect(r.micros, greaterThan(0), reason: stage.name);
    }
  });

  test('a measured line matches the log format and parses back', () {
    final r = runStage(
      BenchStage.limiter,
      run: 2,
      sampleRate: 44100,
      seconds: 1,
      leadSeconds: 0,
    );
    final m = _line.firstMatch(r.line);
    expect(m, isNotNull, reason: r.line);
    expect(m!.group(1), 'limiter');
    expect(m.group(2), '44100');
    expect(m.group(3), '1');
    expect(m.group(4), '2');
    expect(int.parse(m.group(5)!), r.microsPerSecond.round());
    final p = StageRun.parse(r.line)!;
    expect(p.stage, r.stage);
    expect(p.sampleRate, r.sampleRate);
    expect(p.seconds, r.seconds);
    expect(p.run, r.run);
    expect(p.microsPerSecond.round(), r.microsPerSecond.round());
  });

  test('line and parse round-trip', () {
    const r = StageRun(
      stage: BenchStage.full,
      sampleRate: 48000,
      seconds: 60,
      run: 3,
      micros: 250020,
    );
    expect(
      r.line,
      'FBENCH v=1 stage=full rate=48000 secs=60 run=3 us_per_s=4167 '
      'factor=240.0',
    );
    expect(StageRun.parse(r.line)!.line, r.line);
    expect(StageRun.parse('I flutter : ${r.line}')!.line, r.line);
    expect(StageRun.parse('FBENCH done'), isNull);
  });

  test('stageShares splits full into eight parts', () {
    final shares = stageShares({
      BenchStage.full: 1000,
      BenchStage.scape: 900,
      BenchStage.bus: 300,
      BenchStage.roar: 400,
      BenchStage.body: 350,
      BenchStage.spray: 360,
      BenchStage.texture: 420,
      BenchStage.reverb: 200,
      BenchStage.limiter: 20,
    });
    expect(shares.keys.toList(), [
      'roar',
      'body',
      'spray',
      'texture',
      'reverb',
      'bus_other',
      'master',
      'unexplained',
      'full',
    ]);
    expect(shares['roar'], 100);
    expect(shares['body'], 50);
    expect(shares['spray'], 60);
    expect(shares['texture'], 120);
    expect(shares['reverb'], 200);
    expect(shares['bus_other'], 100);
    expect(shares['master'], 100);
    expect(shares['unexplained'], 270);
    expect(shares['full'], 1000);
    final parts = shares.values.take(8).fold<double>(0, (a, b) => a + b);
    expect(parts, shares['full']);
  });
}
