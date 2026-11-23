// Render digests for byte identity (PLAN 5.1). Run from
// packages/fiatsonus_engine:
//   mkdir -p build && dart compile exe tool/digest.dart -o build/digest
//   build/digest > build/digests.txt
//   build/digest --check build/digests.txt
//   build/digest --compare <a> <b>
import 'dart:io';

import 'package:args/args.dart';
import 'package:fiatsonus_engine/profiling.dart';

const int _usageExit = 64;

final ArgParser _parser = ArgParser()
  ..addOption(
    'check',
    valueHelp: 'file',
    help: 'Render every case and compare with the digests in <file>.',
  )
  ..addOption(
    'compare',
    valueHelp: 'a',
    help:
        'Compare the digests in <a> with those in the next argument <b>, '
        'without rendering.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

String get _usage =>
    'Usage: build/digest [--check <file> | --compare <a> <b>]\n'
    'Without an option, prints one FDIGEST line per case.\n'
    '${_parser.usage}';

Never _usageError(String message) {
  stderr
    ..writeln('digest: $message')
    ..writeln(_usage);
  exit(_usageExit);
}

String _readFile(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException catch (e) {
    _usageError('cannot read "$path": ${e.message}');
  }
}

String _renderAll({required bool print}) {
  final out = StringBuffer();
  for (final c in digestCases) {
    final line = renderDigest(c).line;
    out.writeln(line);
    if (print) stdout.writeln(line);
  }
  return out.toString();
}

void _report(String expected, String actual) {
  final DigestComparison c;
  try {
    c = compareDigests(expected, actual);
  } on FormatException catch (e) {
    stderr.writeln('digest: ${e.message}: ${e.source}');
    exitCode = 1;
    return;
  }
  if (c.isMatch) {
    stdout.writeln('DIGEST MATCH cases=${c.matched}');
    return;
  }
  for (final name in c.differing) {
    stderr.writeln(
      'DIGEST DIFF case=$name expected=${c.expected[name]!.hash} '
      'actual=${c.actual[name]!.hash}',
    );
  }
  for (final name in c.missing) {
    stderr.writeln('DIGEST MISSING case=$name');
  }
  for (final name in c.extra) {
    stderr.writeln('DIGEST EXTRA case=$name');
  }
  if (c.matched == 0 &&
      c.differing.isEmpty &&
      c.missing.isEmpty &&
      c.extra.isEmpty) {
    stderr.writeln('digest: no FDIGEST lines to compare');
  }
  exitCode = 1;
}

void main(List<String> args) {
  final ArgResults r;
  try {
    r = _parser.parse(args);
  } on FormatException catch (e) {
    _usageError(e.message);
  }
  if (r.flag('help')) {
    stdout.writeln(_usage);
    return;
  }
  final check = r.option('check');
  final compare = r.option('compare');
  if (check != null && compare != null) {
    _usageError('--check and --compare exclude each other');
  }

  if (compare != null) {
    if (r.rest.length != 1) _usageError('--compare needs two files');
    _report(_readFile(compare), _readFile(r.rest.single));
    return;
  }
  if (r.rest.isNotEmpty) _usageError('unexpected argument "${r.rest.first}"');
  if (check != null) {
    final expected = _readFile(check);
    _report(expected, _renderAll(print: false));
    return;
  }
  _renderAll(print: true);
  stdout.writeln('FDIGEST done cases=${digestCases.length}');
}
