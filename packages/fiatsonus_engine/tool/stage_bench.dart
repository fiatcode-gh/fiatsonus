// Per-stage CPU benchmark of the engine path (PLAN 5.2). The numbers count
// only on the AOT build. Run from packages/fiatsonus_engine:
//   mkdir -p build && dart compile exe tool/stage_bench.dart -o build/stage_bench
//   build/stage_bench
import 'dart:io';

import 'package:args/args.dart';
import 'package:fiatsonus_engine/profiling.dart';

const int _usageExit = 64;
const bool _aot = bool.fromEnvironment('dart.vm.product');

final ArgParser _parser = ArgParser()
  ..addOption('rate', defaultsTo: '48000', help: 'Sample rate in Hz.')
  ..addOption(
    'secs',
    defaultsTo: '60',
    help: 'Audio seconds measured per stage and run (integer, at least 1).',
  )
  ..addOption(
    'runs',
    defaultsTo: '5',
    help: 'Runs over every stage (integer, at least 1).',
  )
  ..addOption('seed', defaultsTo: '1', help: 'Integer seed.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

String get _usage => 'Usage: build/stage_bench [options]\n${_parser.usage}';

Never _usageError(String message) {
  stderr
    ..writeln('stage_bench: $message')
    ..writeln(_usage);
  exit(_usageExit);
}

int _int(ArgResults r, String name, {int? min}) {
  final v = int.tryParse(r.option(name)!);
  if (v == null) {
    _usageError('--$name must be an integer, got "${r.option(name)}"');
  }
  if (min != null && v < min) _usageError('--$name must be at least $min');
  return v;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
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
  if (r.rest.isNotEmpty) _usageError('unexpected argument "${r.rest.first}"');
  final rate = _int(r, 'rate', min: 8000);
  if (rate > 192000) _usageError('--rate must be at most 192000');
  final secs = _int(r, 'secs', min: 1);
  final runs = _int(r, 'runs', min: 1);
  final seed = _int(r, 'seed');

  stdout.writeln('FBENCH begin v=1 mode=${_aot ? 'aot' : 'jit'} build=desktop');
  final perStage = {for (final s in BenchStage.values) s: <double>[]};
  for (var run = 1; run <= runs; run++) {
    for (final stage in BenchStage.values) {
      final result = runStage(
        stage,
        run: run,
        sampleRate: rate,
        seed: seed,
        seconds: secs,
      );
      perStage[stage]!.add(result.microsPerSecond);
      stdout.writeln(result.line);
    }
  }
  final shares = stageShares({
    for (final e in perStage.entries) e.key: _median(e.value),
  });
  final full = shares['full']!;
  for (final e in shares.entries) {
    stdout.writeln(
      'FBENCH v=1 share=${e.key} us_per_s=${e.value.round()} '
      'pct=${(e.value / full * 100).toStringAsFixed(1)}',
    );
  }
  stdout.writeln('FBENCH done');
}
