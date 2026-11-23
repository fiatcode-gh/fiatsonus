import 'dart:io';

import 'package:fiatsonus_engine/profiling.dart';

/// Runs the bench and writes its lines (PLAN 5.3) through [log].
///
/// `measure`: `begin`, one `FDIGEST` line per case, a `tis` line, then for
/// each of [runs] every [BenchStage] in enum order, each stage line followed
/// by a `tis` line, then the nine share lines of the medians, then `done`.
/// `loop`: `begin`, then 10-second `full` runs until [loopFor] of wall time
/// passed (at least one), then `done`. Any other [mode] throws
/// [ArgumentError] before the first line.
void runBench({
  required String mode,
  required String build,
  required void Function(String line) log,
  String? Function() readThreadTimes = readThreadTimeInState,
  List<DigestCase>? cases,
  int seconds = 60,
  int leadSeconds = 5,
  int runs = 5,
  Duration loopFor = const Duration(seconds: 90),
}) {
  if (mode != 'measure' && mode != 'loop') {
    throw ArgumentError.value(mode, 'mode', "not 'measure' or 'loop'");
  }
  final clock = Stopwatch()..start();
  log('FBENCH begin v=1 mode=$mode build=$build');
  if (mode == 'loop') {
    do {
      log(runStage(BenchStage.full, run: 1, seconds: 10, leadSeconds: 0).line);
    } while (clock.elapsed < loopFor);
    log('FBENCH done');
    return;
  }

  void logTimes() {
    final data = readThreadTimes();
    log(
      'FBENCH tis t_us=${clock.elapsedMicroseconds} data=${data ?? 'unavailable'}',
    );
  }

  for (final c in cases ?? digestCases) {
    log(renderDigest(c).line);
  }
  logTimes();
  final perStage = {for (final s in BenchStage.values) s: <double>[]};
  for (var run = 1; run <= runs; run++) {
    for (final stage in BenchStage.values) {
      final result = runStage(
        stage,
        run: run,
        seconds: seconds,
        leadSeconds: leadSeconds,
      );
      perStage[stage]!.add(result.microsPerSecond);
      log(result.line);
      logTimes();
    }
  }
  final shares = stageShares({
    for (final MapEntry(:key, :value) in perStage.entries) key: _median(value),
  });
  final full = shares['full']!;
  for (final MapEntry(:key, :value) in shares.entries) {
    log(
      'FBENCH v=1 share=$key us_per_s=${value.round()} '
      'pct=${(value / full * 100).toStringAsFixed(1)}',
    );
  }
  log('FBENCH done');
}

/// `/proc/thread-self/time_in_state` with newlines as commas; null when it
/// cannot be read.
String? readThreadTimeInState() {
  try {
    final text = File('/proc/thread-self/time_in_state').readAsStringSync();
    return text.trim().replaceAll('\n', ',');
  } on FileSystemException {
    return null;
  }
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}
