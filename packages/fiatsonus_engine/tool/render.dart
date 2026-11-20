// Renders a soundscape to a 16-bit WAV file. Run from packages/fiatsonus_engine:
//   dart run tool/render.dart --scape waterfall --seed 42 --secs 120
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:fiatsonus_engine/offline.dart';

const int _usageExit = 64;

final ArgParser _parser = ArgParser()
  ..addOption('scape', defaultsTo: 'waterfall', help: 'Soundscape id.')
  ..addOption('seed', defaultsTo: '1', help: 'Integer seed.')
  ..addOption(
    'secs',
    defaultsTo: '60',
    help: 'Total file length in seconds, fades included (at least 6).',
  )
  ..addOption('rate', defaultsTo: '48000', help: 'Sample rate in Hz.')
  ..addMultiOption(
    'param',
    valueHelp: 'id=value',
    splitCommas: false,
    help: 'Fixed param value (repeatable).',
  )
  ..addOption('sweep', valueHelp: 'id', help: 'Sweep this param 0 -> 1 -> 0.')
  ..addOption(
    'out',
    help: 'Output file (default out/<scape>-seed<seed>-<rate>.wav).',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

Never _usageError(String message) {
  stderr
    ..writeln('error: $message')
    ..writeln(_usage);
  exit(_usageExit);
}

String get _usage =>
    'Usage: dart run tool/render.dart [options]\n${_parser.usage}';

int _int(ArgResults r, String name) =>
    int.tryParse(r.option(name)!) ??
    _usageError('--$name must be an integer, got "${r.option(name)}"');

double _double(String name, String text) =>
    double.tryParse(text) ?? _usageError('$name must be a number, got "$text"');

String _db(int peak) => peak == 0
    ? '-inf'
    : (20 * math.log(peak / 32768) / math.ln10).toStringAsFixed(1);

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
  final seed = _int(r, 'seed');
  final rate = _int(r, 'rate');
  final secs = _double('--secs', r.option('secs')!);
  final params = <String, double>{};
  for (final p in r.multiOption('param')) {
    final eq = p.indexOf('=');
    if (eq <= 0) _usageError('--param must be id=value, got "$p"');
    params[p.substring(0, eq)] = _double(
      '--param ${p.substring(0, eq)}',
      p.substring(eq + 1),
    );
  }
  final out = r.option('out') ?? 'out/$scape-seed$seed-$rate.wav';
  final job = RenderJob(
    scapeId: scape,
    sampleRate: rate,
    seed: seed,
    seconds: secs,
    params: params,
    sweepParam: r.option('sweep'),
  );

  final RenderSummary s;
  try {
    // renderOffline validates the job before it starts the sink, so a
    // rejected job leaves no file behind.
    s = await renderOffline(job, WavSink(out));
  } on ArgumentError catch (e) {
    _usageError(
      '${e.message}${e.invalidValue == null ? '' : ': ${e.invalidValue}'}',
    );
  }

  stdout.writeln(
    '$out: ${s.frames} frames, ${(s.frames / rate).toStringAsFixed(1)} s, '
    'peak ${_db(s.peak)} dBFS, ${s.lufs.toStringAsFixed(1)} LUFS, '
    'faultBlocks ${s.faultBlocks}, '
    'elapsed ${(s.elapsed.inMicroseconds / 1e6).toStringAsFixed(2)} s, '
    '${s.realtimeFactor.toStringAsFixed(1)}x realtime',
  );
  if (s.faultBlocks != 0) exitCode = 1;
}
