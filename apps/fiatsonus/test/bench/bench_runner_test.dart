import 'package:fiatsonus/src/bench/bench_runner.dart';
import 'package:fiatsonus_engine/profiling.dart';
import 'package:flutter_test/flutter_test.dart';

/// One thread's `time_in_state` as [readThreadTimeInState] returns it.
const _threadTimes = 'cpu0,691200 12,cpu4,2208000 3';

/// The kind of a bench line: `begin`, `digest`, `tis`, `stage`, `share`,
/// `done`, or the line itself when it is none of them.
String _kind(String line) {
  if (line.startsWith('FBENCH begin ')) return 'begin';
  if (line.startsWith('FDIGEST v=1 ')) return 'digest';
  if (line.startsWith('FBENCH tis ')) return 'tis';
  if (StageRun.parse(line) != null) return 'stage';
  if (line.startsWith('FBENCH v=1 share=')) return 'share';
  if (line == 'FBENCH done') return 'done';
  return line;
}

List<String> _measure({String? Function()? readThreadTimes}) {
  final lines = <String>[];
  runBench(
    mode: 'measure',
    build: 'debug',
    log: lines.add,
    readThreadTimes: readThreadTimes ?? () => _threadTimes,
    cases: [digestCases.first],
    seconds: 1,
    leadSeconds: 0,
    runs: 1,
  );
  return lines;
}

void main() {
  test('measure logs begin, digests, a tis line per stage, shares, done', () {
    final lines = _measure();

    expect(lines.map(_kind), [
      'begin',
      'digest',
      'tis',
      for (var i = 0; i < BenchStage.values.length; i++) ...['stage', 'tis'],
      for (var i = 0; i < 9; i++) 'share',
      'done',
    ]);
    expect(lines.first, 'FBENCH begin v=1 mode=measure build=debug');
    expect(lines[1], renderDigest(digestCases.first).line);
    expect([
      for (final l in lines) ?StageRun.parse(l)?.stage,
    ], BenchStage.values);
    expect(
      [
        for (final l in lines)
          if (_kind(l) == 'share') l.split(' ')[2],
      ],
      [
        'share=roar',
        'share=body',
        'share=spray',
        'share=texture',
        'share=reverb',
        'share=bus_other',
        'share=master',
        'share=unexplained',
        'share=full',
      ],
    );
  });

  test('a tis line holds the stopwatch time and the reader text', () {
    final tis = _measure().where((l) => _kind(l) == 'tis').toList();
    final pattern = RegExp(r'^FBENCH tis t_us=(\d+) data=(.*)$');

    expect(tis, everyElement(matches(pattern)));
    expect(
      pattern.firstMatch(tis.first)!.group(2),
      'cpu0,691200 12,cpu4,2208000 3',
    );
    final times = [
      for (final l in tis) int.parse(pattern.firstMatch(l)!.group(1)!),
    ];
    expect(times, orderedEquals([...times]..sort()));
    expect(times.last, greaterThan(times.first));
  });

  test('an unreadable time_in_state gives data=unavailable', () {
    final tis = _measure(readThreadTimes: () => null)
        .where((l) => _kind(l) == 'tis');

    expect(tis, hasLength(BenchStage.values.length + 1));
    expect(tis, everyElement(endsWith(' data=unavailable')));
  });

  test('loop logs begin, at least one full stage line, done', () {
    final lines = <String>[];
    runBench(
      mode: 'loop',
      build: 'profile',
      log: lines.add,
      loopFor: Duration.zero,
    );

    expect(lines.map(_kind), ['begin', 'stage', 'done']);
    expect(lines.first, 'FBENCH begin v=1 mode=loop build=profile');
    final run = StageRun.parse(lines[1])!;
    expect(run.stage, BenchStage.full);
    expect(run.seconds, 10);
  });

  test('an unknown mode throws before any line', () {
    final lines = <String>[];

    expect(
      () => runBench(mode: 'fast', build: 'release', log: lines.add),
      throwsArgumentError,
    );
    expect(lines, isEmpty);
  });
}
