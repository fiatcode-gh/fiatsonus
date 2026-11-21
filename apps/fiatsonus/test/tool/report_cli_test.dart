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

    expect(noArgs.exitCode, 64, reason: '${noArgs.stderr}');
    expect(unknown.exitCode, 64, reason: '${unknown.stderr}');
    expect(badRatio.exitCode, 64, reason: '${badRatio.stderr}');
    expect(noDir.exitCode, 64, reason: '${noDir.stderr}');
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
    expect(lines, contains('RESULT battery_mah=388'));
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

  test('--max-render-ratio moves the render limit', () async {
    final t0 = writeSnapshot('t0', passingT0());
    final t1 = writeSnapshot('t1', passingT1());

    final result = await runReport([
      '--t0',
      t0,
      '--t1',
      t1,
      '--max-render-ratio',
      '0.01',
    ]);

    expect(result.exitCode, 1);
    expect(
      (result.stdout as String).trim().split('\n').last,
      'FAIL render_ratio_pct 1.00 >= 1.00',
    );
  });
}
