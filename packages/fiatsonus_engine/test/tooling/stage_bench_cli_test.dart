// The 3-minute library timeout also covers setUpAll's compile.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

List<String> _lines(Object? out) => (out as String)
    .split('\n')
    .map((l) => l.trimRight())
    .where((l) => l.isNotEmpty)
    .toList();

const List<String> _stages = [
  'full',
  'scape',
  'bus',
  'roar',
  'body',
  'spray',
  'texture',
  'reverb',
  'limiter',
];

const List<String> _shares = [
  'roar',
  'body',
  'spray',
  'texture',
  'reverb',
  'bus_other',
  'master',
  'unexplained',
  'full',
];

void main() {
  late Directory tmp;
  late String exe;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('stage_bench_cli_test');
    exe = '${tmp.path}/stage_bench';
    final r = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'tool/stage_bench.dart',
      '-o',
      exe,
    ]);
    if (r.exitCode != 0) {
      fail('compile failed (${r.exitCode}): ${r.stdout}\n${r.stderr}');
    }
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args) => Process.run(exe, args);

  test('prints the stage lines, the share lines and done', () async {
    final r = await run(['--secs', '1', '--runs', '2']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final lines = _lines(r.stdout);
    expect(lines, hasLength(1 + 18 + 9 + 1));
    expect(lines.first, 'FBENCH begin v=1 mode=aot build=desktop');
    var i = 1;
    for (final run in [1, 2]) {
      for (final stage in _stages) {
        expect(
          lines[i++],
          matches(
            '^FBENCH v=1 stage=$stage rate=48000 secs=1 run=$run '
            r'us_per_s=\d+ factor=\d+\.\d$',
          ),
        );
      }
    }
    for (final share in _shares) {
      expect(
        lines[i++],
        matches(
          '^FBENCH v=1 share=$share '
          r'us_per_s=-?\d+ pct=-?\d+\.\d$',
        ),
      );
    }
    expect(lines.last, 'FBENCH done');
  });

  test('usage errors exit 64', () async {
    for (final args in [
      ['--runs', '0'],
      ['--secs', '0'],
      ['--rate', 'abc'],
      ['--bogus'],
    ]) {
      final r = await run(args);
      expect(r.exitCode, 64, reason: '$args');
      expect((r.stderr as String).trim(), isNotEmpty, reason: '$args');
    }
  });

  test('--help exits 0 and lists every option', () async {
    final r = await run(['--help']);
    expect(r.exitCode, 0);
    for (final option in ['--rate', '--secs', '--runs', '--seed', '--help']) {
      expect(r.stdout, contains(option));
    }
  });
}
