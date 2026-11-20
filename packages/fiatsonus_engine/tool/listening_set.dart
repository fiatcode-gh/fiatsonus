// Renders the listening set of a soundscape and writes its README.txt.
// Run from packages/fiatsonus_engine:
//   dart run tool/listening_set.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:fiatsonus_engine/offline.dart';

const int _usageExit = 64;

/// Highest legal peak (about −1 dBFS), as in the check harness.
const int _maxLegalPeak = 29203;

final ArgParser _parser = ArgParser()
  ..addOption('scape', defaultsTo: 'waterfall', help: 'Soundscape id.')
  ..addOption('rate', defaultsTo: '48000', help: 'Sample rate in Hz.')
  ..addOption('seed', defaultsTo: '1', help: 'Integer seed.')
  ..addOption(
    'long-secs',
    defaultsTo: '600',
    help: 'Length of the long file in seconds; 0 leaves it out.',
  )
  ..addOption(
    'out-dir',
    help: 'Target directory (default out/listening/<scape>).',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

String get _usage =>
    'Usage: dart run tool/listening_set.dart [options]\n${_parser.usage}';

Never _usageError(String message) {
  stderr
    ..writeln('error: $message')
    ..writeln(_usage);
  exit(_usageExit);
}

int _int(ArgResults r, String name) =>
    int.tryParse(r.option(name)!) ??
    _usageError('--$name must be an integer, got "${r.option(name)}"');

String _db(int peak) =>
    (20 * math.log(peak / 32768) / math.ln10).toStringAsFixed(1);

Future<void> main(List<String> args) async {
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
  if (r.rest.isNotEmpty) _usageError('unexpected argument "${r.rest.first}"');

  final scape = r.option('scape')!;
  final rate = _int(r, 'rate');
  final seed = _int(r, 'seed');
  final longText = r.option('long-secs')!;
  final longSeconds =
      double.tryParse(longText) ??
      _usageError('--long-secs must be a number, got "$longText"');
  final outDir = r.option('out-dir') ?? 'out/listening/$scape';

  final List<ListeningItem> items;
  try {
    items = listeningSet(
      scape,
      sampleRate: rate,
      seed: seed,
      longSeconds: longSeconds,
    );
  } on ArgumentError catch (e) {
    _usageError(
      '${e.message}${e.invalidValue == null ? '' : ': ${e.invalidValue}'}',
    );
  }

  Directory(outDir).createSync(recursive: true);
  final summaries = <RenderSummary>[];
  for (final item in items) {
    final path = '$outDir/${item.fileName}';
    final RenderSummary s;
    try {
      s = await renderOffline(item.job, WavSink(path));
    } on ArgumentError catch (e) {
      _usageError(
        '${e.message}${e.invalidValue == null ? '' : ': ${e.invalidValue}'}',
      );
    }
    final String? problem = s.faultBlocks != 0
        ? 'faultBlocks ${s.faultBlocks}'
        : !s.endedSilent
        ? 'did not end silent'
        : s.peak > _maxLegalPeak
        ? 'peak ${s.peak} above $_maxLegalPeak'
        : null;
    if (problem != null) {
      stderr.writeln('listening_set: $path: $problem; stopped, no README.txt');
      exitCode = 1;
      return;
    }
    summaries.add(s);
    stdout.writeln(
      '${item.fileName}  ${s.lufs.toStringAsFixed(1)} LUFS  '
      'peak ${_db(s.peak)} dBFS  '
      '${s.realtimeFactor.toStringAsFixed(1)}x realtime',
    );
  }

  final readme = File('$outDir/README.txt')
    ..writeAsStringSync(listeningReadme(scape, items, summaries));
  stdout.writeln(readme.path);
}
