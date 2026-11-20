// Long-run check (PLAN 4.6, N11): renders simulated hours of one soundscape
// with nothing allocated in the steady phase. Compile it with
// `dart compile exe tool/soak.dart` and run it with
// `DART_VM_OPTIONS=--verbose_gc`; the soak test does both.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:fiatsonus_engine/offline.dart';

const int _usageExit = 64;
const int _chunkFrames = 1024;
const int _windowSeconds = 600;
const int _meterSeconds = 60;
const int _warmUpSeconds = 20;

/// Keeps the deliberate garbage reachable, so the compiler cannot drop it.
final List<List<int>?> _garbageRing = List<List<int>?>.filled(16, null);

final ArgParser _parser = ArgParser()
  ..addOption('scape', defaultsTo: 'waterfall', help: 'Soundscape id.')
  ..addOption('rate', defaultsTo: '48000', help: 'Sample rate in Hz.')
  ..addOption('hours', defaultsTo: '8', help: 'Simulated hours (integer).')
  ..addOption('seed', defaultsTo: '1', help: 'Integer seed.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

Never _usageError(String message) {
  stderr
    ..writeln('error: $message')
    ..writeln(_usage);
  exit(_usageExit);
}

String get _usage =>
    'Usage: dart compile exe tool/soak.dart -o soak && ./soak [options]\n'
    '${_parser.usage}';

int _int(ArgResults r, String name) =>
    int.tryParse(r.option(name)!) ??
    _usageError('--$name must be an integer, got "${r.option(name)}"');

Future<void> _marker(String text) async {
  stderr.writeln(text);
  await stderr.flush();
}

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
  if (r.rest.isNotEmpty) _usageError('unexpected arguments: ${r.rest}');
  final id = r.option('scape')!;
  final rate = _int(r, 'rate');
  final hours = _int(r, 'hours');
  final seed = _int(r, 'seed');
  final scape = createSoundscape(id);
  if (scape == null) _usageError('unknown soundscape "$id"');
  if (hours < 1) _usageError('--hours must be at least 1');
  final Master master;
  try {
    master = Master(sampleRate: rate, seed: seed);
  } on ArgumentError catch (e) {
    _usageError('--rate: ${e.message}');
  }

  master
    ..add(scape)
    ..start(id);
  final chunk = Int16List(_chunkFrames * 2);
  final meter = LoudnessMeter(rate);
  final windows = hours * 6;
  final lufs = Float64List(windows);
  final rss = Int64List(windows);
  final windowFrames = _windowSeconds * rate;
  final meterFrames = _meterSeconds * rate;

  for (var left = _warmUpSeconds * rate; left > 0; left -= _chunkFrames) {
    master.render(chunk, left < _chunkFrames ? left : _chunkFrames);
  }

  await _marker('SOAK-STEADY-BEGIN');
  final clock = Stopwatch()..start();
  var peak = 0;
  var maxVoices = 0;
  for (var w = 0; w < windows; w++) {
    meter.reset();
    var done = 0;
    while (done < windowFrames) {
      final left = windowFrames - done;
      final n = left < _chunkFrames ? left : _chunkFrames;
      master.render(chunk, n);
      if (done < meterFrames) {
        final m = meterFrames - done;
        meter.add(chunk, m < n ? m : n);
      }
      for (var i = 0; i < n * 2; i++) {
        final s = chunk[i];
        final a = s < 0 ? -s : s;
        if (a > peak) peak = a;
      }
      final v = scape.activeVoices;
      if (v > maxVoices) maxVoices = v;
      done += n;
    }
    lufs[w] = meter.lufs;
    rss[w] = ProcessInfo.currentRss;
  }
  clock.stop();
  await _marker('SOAK-STEADY-END');

  stdout.writeln(
    jsonEncode({
      'scape': id,
      'rate': rate,
      'hours': hours,
      'elapsedSeconds': clock.elapsedMicroseconds / 1e6,
      'maxVoices': maxVoices,
      'peak': peak,
      'faultBlocks': master.faultBlocks,
      'lufs': lufs,
      'rssBytes': rss,
    }),
  );
  await stdout.flush();

  // Deliberate garbage: proves the GC log is on (the test expects GC lines
  // here).
  for (var i = 0; i < 200000; i++) {
    _garbageRing[i & 15] = List<int>.filled(64, i);
  }
  await _marker('SOAK-GARBAGE-DONE');
}
