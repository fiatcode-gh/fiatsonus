// The 3-minute library timeout also covers setUpAll's compile and render.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

List<String> _lines(Object? out) => (out as String)
    .split('\n')
    .map((l) => l.trimRight())
    .where((l) => l.isNotEmpty)
    .toList();

void main() {
  late Directory tmp;
  late String exe;
  late ProcessResult printed;
  late String digests;

  Future<ProcessResult> run(List<String> args) => Process.run(exe, args);

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('digest_cli_test');
    exe = '${tmp.path}/digest';
    final r = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'tool/digest.dart',
      '-o',
      exe,
    ]);
    if (r.exitCode != 0) {
      fail('compile failed (${r.exitCode}): ${r.stdout}\n${r.stderr}');
    }
    printed = await run([]);
    digests = '${tmp.path}/digests.txt';
    File(digests).writeAsStringSync(printed.stdout as String);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('prints 28 digest lines and the done line', () {
    expect(printed.exitCode, 0, reason: '${printed.stderr}');
    final lines = _lines(printed.stdout);
    expect(lines, hasLength(29));
    for (final l in lines.take(28)) {
      expect(
        l,
        matches(r'^FDIGEST v=1 case=\S+ frames=\d+ hash=[0-9a-f]{16}$'),
      );
    }
    expect(lines.last, 'FDIGEST done cases=28');
  });

  test('--check of its own output matches', () async {
    final r = await run(['--check', digests]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(_lines(r.stdout), ['DIGEST MATCH cases=28']);
  });

  test('--check with one hash digit changed reports one difference', () async {
    final lines = _lines(printed.stdout);
    final first = lines.first;
    final last = first[first.length - 1];
    lines[0] = first.substring(0, first.length - 1) + (last == '0' ? '1' : '0');
    final changed = '${tmp.path}/changed.txt';
    File(changed).writeAsStringSync('${lines.join('\n')}\n');

    final r = await run(['--check', changed]);
    expect(r.exitCode, 1);
    final diffs = _lines(r.stderr)
        .where((l) => l.startsWith('DIGEST DIFF case='))
        .toList();
    expect(diffs, hasLength(1));
    expect(
      diffs.single,
      startsWith('DIGEST DIFF case=session-r44100-s1-default '),
    );
    expect(
      _lines(r.stdout).where((l) => l.startsWith('DIGEST MATCH')),
      isEmpty,
    );
  });

  test('--compare of a file with itself matches', () async {
    final r = await run(['--compare', digests, digests]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(_lines(r.stdout), ['DIGEST MATCH cases=28']);
  });

  test('usage errors exit 64', () async {
    for (final args in [
      ['--bogus'],
      ['--compare', digests],
      ['--check', digests, '--compare', digests, digests],
    ]) {
      final r = await run(args);
      expect(r.exitCode, 64, reason: '$args');
      expect((r.stderr as String).trim(), isNotEmpty, reason: '$args');
    }
  });
}
