import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'snapshot_pair.dart';

/// Runs the CLI the way the device scripts do: `dart tool/device/report.dart`
/// from the package root (`dart` on PATH is Flutter's).
Future<ProcessResult> runReport(List<String> args) =>
    Process.run('dart', ['tool/device/report.dart', ...args]);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('report_cli_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeSnapshot(String name, Map<String, String> files) {
    final dir = Directory('${tmp.path}/$name')..createSync();
    files.forEach(
      (file, text) => File('${dir.path}/$file').writeAsStringSync(text),
    );
    return dir.path;
  }

  test('usage errors exit 64', () async {
    final noArgs = await runReport([]);
    final unknown = await runReport([
      '--t0',
      tmp.path,
      '--t1',
      tmp.path,
      '--x',
    ]);
    final badRatio = await runReport([
      '--t0',
      tmp.path,
      '--t1',
      tmp.path,
      '--max-render-ratio',
      'lots',
    ]);
    final noDir = await runReport(['--t0', '${tmp.path}/a', '--t1', tmp.path]);
    final badWindows = [
      for (final window in ['0', '-5', '1.5', 'long'])
        await runReport([
          '--t0',
          tmp.path,
          '--t1',
          tmp.path,
          '--min-battery-window',
          window,
        ]),
    ];

    expect(noArgs.exitCode, 64, reason: '${noArgs.stderr}');
    expect(unknown.exitCode, 64, reason: '${unknown.stderr}');
    expect(badRatio.exitCode, 64, reason: '${badRatio.stderr}');
    expect(noDir.exitCode, 64, reason: '${noDir.stderr}');
    for (final result in badWindows) {
      expect(result.exitCode, 64, reason: '${result.stderr}');
    }
  });

  test('a passing pair exits 0 and prints PASS last', () async {
    final t0 = writeSnapshot('t0', passingT0());
    final t1 = writeSnapshot('t1', passingT1());

    final result = await runReport([
      '--t0',
      t0,
      '--t1',
      t1,
      '--battery',
      '--expect-foreground',
      '--max-render-ratio',
      '0.05',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    final lines = (result.stdout as String).trim().split('\n');
    expect(lines, contains('RESULT battery_mah=340'));
    expect(lines.last, 'PASS');
  });

  test('a failing pair exits 1 and prints every reason', () async {
    final t0 = writeSnapshot('t0', passingT0());
    final t1 = writeSnapshot(
      't1',
      passingT1()..['fstat.txt'] = t1Fstat(underruns: 1, overlaps: 2),
    );

    final result = await runReport(['--t0', t0, '--t1', t1]);

    expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
    expect(
      (result.stdout as String).trim().split('\n').last,
      'FAIL underruns 1 != 0; overlaps 2 != 0',
    );
  });

  group('the CPU line does not decide the exit status', () {
    List<String> linesOf(ProcessResult result) =>
        (result.stdout as String).trim().split('\n');

    test('a 17 % pair exits 0 with CPU MISS', () async {
      final t0 = writeSnapshot('t0', passingT0());
      final t1 = writeSnapshot('t1', t1AtRenderPct(17));

      final result = await runReport(['--t0', t0, '--t1', t1]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(linesOf(result).sublist(linesOf(result).length - 2), [
        'CPU MISS render_ratio_pct=17.00 limit_pct=5.00',
        'PASS',
      ]);
    });

    test('--max-render-ratio moves the CPU limit', () async {
      final t0 = writeSnapshot('t0', passingT0());
      final t1 = writeSnapshot('t1', t1AtRenderPct(17));

      final result = await runReport([
        '--t0',
        t0,
        '--t1',
        t1,
        '--max-render-ratio',
        '0.2',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
        linesOf(result),
        contains('CPU PASS render_ratio_pct=17.00 limit_pct=20.00'),
      );
    });

    test(
      'a 17 % pair with an underrun exits 1 and still says CPU MISS',
      () async {
        final t0 = writeSnapshot('t0', passingT0());
        final t1 = writeSnapshot('t1', t1AtRenderPct(17, underruns: 1));

        final result = await runReport(['--t0', t0, '--t1', t1]);

        expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
        expect(linesOf(result).sublist(linesOf(result).length - 2), [
          'CPU MISS render_ratio_pct=17.00 limit_pct=5.00',
          'FAIL underruns 1 != 0',
        ]);
      },
    );
  });

  test('--min-battery-window sets the shortest window', () async {
    // A 180 s unplug, 11-22 09:10:00 to 09:13:00.
    final history = historyOf([
      '11-22 09:00:00.000 090 plug=ac volt=4222 charge=4700 +plugged',
      '11-22 09:10:00.000 090 status=discharging plug=none volt=4291 '
          '-plugged -charging',
      '11-22 09:13:00.000 090 plug=usb volt=4084 charge=4690 +plugged',
      '11-22 09:14:00.000 090 stats=0:"dump"',
    ]);
    final t0 = writeSnapshot(
      't0',
      passingT0()
        ..['time.txt'] = timeTxt(
          epochMs: kEpoch0,
          uptimeS: '1000.00',
          local: '2026-11-22 09:05:00',
        ),
    );
    final t1 = writeSnapshot(
      't1',
      passingT1()
        ..['time.txt'] = timeTxt(
          epochMs: kEpoch1,
          uptimeS: '1600.00',
          local: '2026-11-22 09:15:00',
        )
        ..['batterystats_history.txt'] = history,
    );
    final args = ['--t0', t0, '--t1', t1, '--battery'];

    final byDefault = await runReport(args);
    final at120 = await runReport([...args, '--min-battery-window', '120']);

    expect(byDefault.exitCode, 1, reason: '${byDefault.stdout}');
    expect(
      (byDefault.stdout as String).trim().split('\n').last,
      'FAIL battery window 180 s < 3600 s',
    );
    expect(at120.exitCode, 0, reason: '${at120.stdout}${at120.stderr}');
    expect((at120.stdout as String).trim().split('\n').last, 'PASS');
  });
}
