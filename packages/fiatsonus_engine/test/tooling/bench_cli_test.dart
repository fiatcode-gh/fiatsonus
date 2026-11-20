import 'dart:io';

import 'package:test/test.dart';

final RegExp _line = RegExp(
  r'^bench scape=(\S+) rate=(\d+) mode=(aot|jit) secs=(\d+) runs=(\d+) '
  r'min=(\d+\.\d) median=(\d+\.\d) max=(\d+\.\d)$',
);

List<String> _lines(Object? out) => (out as String)
    .split('\n')
    .map((l) => l.trimRight())
    .where((l) => l.isNotEmpty)
    .toList();

void main() {
  late Directory tmp;
  late String exe;

  const slow = Timeout(Duration(minutes: 3));

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('bench_cli_test');
    exe = '${tmp.path}/bench';
    final r = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'tool/bench.dart',
      '-o',
      exe,
    ]);
    if (r.exitCode != 0) {
      fail('compile failed (${r.exitCode}): ${r.stdout}\n${r.stderr}');
    }
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<ProcessResult> jit(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'tool/bench.dart', ...args],
  );
  Future<ProcessResult> aot(List<String> args) => Process.run(exe, args);

  test('JIT run prints one bench line', () async {
    final r = await jit(['--secs', '2', '--runs', '1']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final lines = _lines(r.stdout);
    expect(lines, hasLength(1));
    expect(
      lines.single,
      matches(
        r'^bench scape=waterfall rate=48000 mode=jit secs=2 runs=1 '
        r'min=\d+\.\d median=\d+\.\d max=\d+\.\d$',
      ),
    );
  }, timeout: slow);

  test('--min-factor refuses JIT', () async {
    final r = await jit(['--secs', '2', '--runs', '1', '--min-factor', '1']);
    expect(r.exitCode, 64);
    expect(r.stderr, contains('AOT'));
    expect(_lines(r.stdout).where((l) => l.startsWith('bench')), isEmpty);
  }, timeout: slow);

  test('AOT pass prints ordered stats and PASS', () async {
    final r = await aot(['--secs', '2', '--runs', '3', '--min-factor', '1']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final lines = _lines(r.stdout);
    final m = _line.firstMatch(lines.first);
    expect(m, isNotNull, reason: lines.first);
    expect(m!.group(3), 'aot');
    expect(m.group(5), '3');
    final min = double.parse(m.group(6)!);
    final median = double.parse(m.group(7)!);
    final max = double.parse(m.group(8)!);
    expect(min, lessThanOrEqualTo(median));
    expect(median, lessThanOrEqualTo(max));
    expect(lines.last, 'PASS min-factor=1.0');
  }, timeout: slow);

  test('AOT median below the factor fails', () async {
    final r = await aot([
      '--secs',
      '2',
      '--runs',
      '2',
      '--min-factor',
      '1000000',
    ]);
    expect(r.exitCode, 1);
    expect(
      _lines(r.stderr)
          .where((l) => l.startsWith('FAIL scape=waterfall median=')),
      hasLength(1),
    );
  }, timeout: slow);

  test('AOT --rate reaches the line', () async {
    final r = await aot(['--rate', '44100', '--secs', '2', '--runs', '1']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(_lines(r.stdout).single, contains('rate=44100'));
  }, timeout: slow);

  test('usage errors exit 64', () async {
    for (final args in [
      ['--scape', 'nope'],
      ['--secs', '0'],
      ['--runs', '0'],
      ['--min-factor', 'abc'],
      ['--min-factor', '0'],
      ['--bogus'],
    ]) {
      final r = await aot(args);
      expect(r.exitCode, 64, reason: '$args');
      expect((r.stderr as String).trim(), isNotEmpty, reason: '$args');
    }
  }, timeout: slow);

  test('--help exits 0 and lists every option', () async {
    final r = await aot(['--help']);
    expect(r.exitCode, 0);
    for (final option in [
      '--scape',
      '--rate',
      '--secs',
      '--runs',
      '--seed',
      '--min-factor',
      '--help',
    ]) {
      expect(r.stdout, contains(option));
    }
  }, timeout: slow);
}
