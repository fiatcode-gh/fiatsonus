// Turns two device snapshots into measured results and a verdict.
//
// Usage: dart tool/device/report.dart --t0 <dir> --t1 <dir> [--battery]
//        [--expect-foreground] [--max-render-ratio 0.05]
//        [--min-battery-window 3600]
//
// Prints one `RESULT key=value` line per result, one `CPU` line (the render
// ratio against --max-render-ratio), then `PASS` or
// `FAIL <reason>; <reason>…`. Exits 0 on PASS, 1 on FAIL, whatever the CPU
// line says, and 64 on a usage error.
import 'dart:convert';
import 'dart:io';

import 'src/report.dart';

const _usage =
    'usage: dart tool/device/report.dart --t0 <dir> --t1 <dir> [--battery] '
    '[--expect-foreground] [--max-render-ratio 0.05] '
    '[--min-battery-window 3600]';

void main(List<String> args) {
  String? t0;
  String? t1;
  var battery = false;
  var expectForeground = false;
  var maxRenderRatio = 0.05;
  var minBatteryWindow = 3600;

  for (var i = 0; i < args.length; i++) {
    String value() => ++i < args.length
        ? args[i]
        : _usageError('${args[i - 1]} needs a value');
    switch (args[i]) {
      case '--t0':
        t0 = value();
      case '--t1':
        t1 = value();
      case '--battery':
        battery = true;
      case '--expect-foreground':
        expectForeground = true;
      case '--max-render-ratio':
        final text = value();
        final ratio = double.tryParse(text);
        if (ratio == null || ratio <= 0) {
          _usageError('--max-render-ratio wants a positive number, not $text');
        }
        maxRenderRatio = ratio;
      case '--min-battery-window':
        final text = value();
        final seconds = int.tryParse(text);
        if (seconds == null || seconds <= 0 || text.trim() != '$seconds') {
          _usageError(
            '--min-battery-window wants a positive whole number of seconds, '
            'not $text',
          );
        }
        minBatteryWindow = seconds;
      default:
        _usageError('unknown argument ${args[i]}');
    }
  }
  if (t0 == null || t1 == null) _usageError('--t0 and --t1 are required');

  final report = buildReport(
    _readSnapshot('t0', t0),
    _readSnapshot('t1', t1),
    ReportOptions(
      battery: battery,
      expectForeground: expectForeground,
      maxRenderRatio: maxRenderRatio,
      minBatteryWindowSeconds: minBatteryWindow,
    ),
  );
  stdout.writeln(report.format());
  exitCode = report.passed ? 0 : 1;
}

Snapshot _readSnapshot(String label, String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) _usageError('no snapshot directory $path');
  return Snapshot(label, {
    for (final file in dir.listSync().whereType<File>())
      file.uri.pathSegments.last: utf8.decode(
        file.readAsBytesSync(),
        allowMalformed: true,
      ),
  });
}

Never _usageError(String message) {
  stderr
    ..writeln('report.dart: $message')
    ..writeln(_usage);
  exit(64);
}
