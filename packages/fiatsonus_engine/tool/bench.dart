// CPU benchmark: realtime factor of the full master path per soundscape.
// The number counts only on the AOT build. Run from packages/fiatsonus_engine:
//   mkdir -p build && dart compile exe tool/bench.dart -o build/bench
//   build/bench --min-factor 150
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:fiatsonus_engine/fiatsonus_engine.dart';

const int _usageExit = 64;
const int _chunkFrames = 1024;
const int _leadSeconds = 20;
const bool _aot = bool.fromEnvironment('dart.vm.product');

final ArgParser _parser = ArgParser()
  ..addOption(
    'scape',
    help: 'One soundscape id (default: every soundscape, in order).',
  )
  ..addOption('rate', defaultsTo: '48000', help: 'Sample rate in Hz.')
  ..addOption(
    'secs',
    defaultsTo: '300',
    help: 'Simulated seconds measured per run (integer, at least 1).',
  )
  ..addOption(
    'runs',
    defaultsTo: '5',
    help: 'Measured runs per soundscape (integer, at least 1).',
  )
  ..addOption('seed', defaultsTo: '1', help: 'Integer seed.')
  ..addOption(
    'min-factor',
    help: 'Lowest accepted median realtime factor (AOT build only).',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

String get _usage => 'Usage: build/bench [options]\n${_parser.usage}';

Never _usageError(String message) {
  stderr
    ..writeln('bench: $message')
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

/// One measured run: realtime factor, or null for a fault or silent master.
double? _run(String id, int rate, int seed, int secs, Int16List buffer) {
  final master = Master(sampleRate: rate, seed: seed)
    ..add(createSoundscape(id)!);
  master.start(id);
  final lead = (_leadSeconds * rate / _chunkFrames).ceil();
  for (var i = 0; i < lead; i++) {
    master.render(buffer, _chunkFrames);
  }
  final chunks = (secs * rate / _chunkFrames).ceil();
  final clock = Stopwatch()..start();
  for (var i = 0; i < chunks; i++) {
    master.render(buffer, _chunkFrames);
  }
  clock.stop();
  if (master.faultBlocks != 0 || master.isSilent) return null;
  return (chunks * _chunkFrames / rate) / (clock.elapsedMicroseconds / 1e6);
}

double _median(List<double> sorted) {
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

  final scape = r.option('scape');
  if (scape != null && !soundscapeIds.contains(scape)) {
    _usageError('unknown soundscape "$scape"');
  }
  final ids = scape == null ? soundscapeIds : [scape];
  final rate = _int(r, 'rate', min: 8000);
  if (rate > 192000) _usageError('--rate must be at most 192000');
  final secs = _int(r, 'secs', min: 1);
  final runs = _int(r, 'runs', min: 1);
  final seed = _int(r, 'seed');
  double? minFactor;
  final minText = r.option('min-factor');
  if (minText != null) {
    minFactor = double.tryParse(minText);
    if (minFactor == null || !(minFactor > 0) || minFactor.isInfinite) {
      _usageError('--min-factor must be a number above 0, got "$minText"');
    }
  }
  if (minFactor != null && !_aot) {
    stderr.writeln(
      'bench: --min-factor needs the AOT build '
      '(dart compile exe tool/bench.dart)',
    );
    exit(_usageExit);
  }

  final buffer = Int16List(_chunkFrames * 2);
  final failures = <String>[];
  for (final id in ids) {
    final factors = <double>[];
    for (var i = 0; i < runs; i++) {
      final f = _run(id, rate, seed, secs, buffer);
      if (f == null) {
        stderr.writeln('bench: $id rendered a fault or silence; result void');
        exitCode = 1;
        return;
      }
      factors.add(f);
    }
    factors.sort();
    final median = _median(factors);
    stdout.writeln(
      'bench scape=$id rate=$rate mode=${_aot ? 'aot' : 'jit'} secs=$secs '
      'runs=$runs min=${factors.first.toStringAsFixed(1)} '
      'median=${median.toStringAsFixed(1)} '
      'max=${factors.last.toStringAsFixed(1)}',
    );
    if (minFactor != null && median < minFactor) {
      failures.add(
        'FAIL scape=$id median=${median.toStringAsFixed(1)} '
        'min-factor=$minFactor',
      );
    }
  }
  if (minFactor == null) return;
  if (failures.isEmpty) {
    stdout.writeln('PASS min-factor=$minFactor');
  } else {
    failures.forEach(stderr.writeln);
    exitCode = 1;
  }
}
