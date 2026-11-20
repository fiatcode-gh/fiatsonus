import 'dart:io';

import 'package:test/test.dart';

/// Runs `dart run tool/render.dart [args]` from the package directory.
Future<ProcessResult> _render(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'tool/render.dart', ...args],
);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('render_cli_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  const slow = Timeout(Duration(minutes: 2));

  test('renders a file and prints one summary line', () async {
    final a = '${tmp.path}/a.wav';
    final r = await _render(['--secs', '8', '--seed', '5', '--out', a]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final lines = (r.stdout as String).trim().split('\n');
    expect(lines, hasLength(1));
    expect(lines.single, contains(a));
    expect(File(a).lengthSync(), 44 + 8 * 48000 * 4);

    final b = '${tmp.path}/b.wav';
    final r2 = await _render(['--secs', '8', '--seed', '5', '--out', b]);
    expect(r2.exitCode, 0, reason: '${r2.stderr}');
    expect(File(b).readAsBytesSync(), File(a).readAsBytesSync());
  }, timeout: slow);

  test('usage errors exit 64 without an output file', () async {
    for (final args in [
      ['--param', 'nope=1'],
      ['--secs', 'abc'],
      ['--param', 'height'],
      ['--bogus'],
    ]) {
      final out = '${tmp.path}/bad.wav';
      final r = await _render(['--secs', '8', '--out', out, ...args]);
      expect(r.exitCode, 64, reason: '$args');
      expect((r.stderr as String).trim(), isNotEmpty, reason: '$args');
      expect(File(out).existsSync(), isFalse, reason: '$args');
    }
  }, timeout: slow);

  test('--help exits 0 and lists every option', () async {
    final r = await _render(['--help']);
    expect(r.exitCode, 0);
    for (final option in [
      '--scape',
      '--seed',
      '--secs',
      '--rate',
      '--param',
      '--sweep',
      '--out',
      '--help',
    ]) {
      expect(r.stdout, contains(option));
    }
  }, timeout: slow);
}
