// Turns bench files into the stage and share tables of PLAN 5.5.
//
// Usage: dart tool/device/bench_report.dart --phone <bench.txt>
//        [--desktop <file>] [--base-phone <bench.txt>] [--base-desktop <file>]
//
// <bench.txt> is the file bench_run.sh writes; a desktop <file> is the output
// of packages/fiatsonus_engine's stage_bench. Exits 0 after printing, 64 on a
// usage error and 1 when a file has no complete stage set.
import 'dart:convert';
import 'dart:io';

import 'src/bench_report.dart';

const _usage =
    'usage: dart tool/device/bench_report.dart --phone <bench.txt> '
    '[--desktop <file>] [--base-phone <bench.txt>] [--base-desktop <file>]';

void main(List<String> args) {
  String? phone;
  String? desktop;
  String? basePhone;
  String? baseDesktop;

  for (var i = 0; i < args.length; i++) {
    String value() => ++i < args.length
        ? args[i]
        : _usageError('${args[i - 1]} needs a value');
    switch (args[i]) {
      case '--phone':
        phone = value();
      case '--desktop':
        desktop = value();
      case '--base-phone':
        basePhone = value();
      case '--base-desktop':
        baseDesktop = value();
      default:
        _usageError('unknown argument ${args[i]}');
    }
  }
  if (phone == null) _usageError('--phone is required');
  if (baseDesktop != null && desktop == null) {
    _usageError('--base-desktop needs --desktop');
  }

  try {
    stdout.writeln(
      benchReport(
        phone: _read(phone)!,
        desktop: _read(desktop),
        basePhone: _read(basePhone),
        baseDesktop: _read(baseDesktop),
      ),
    );
  } on _BadFile catch (e) {
    stderr.writeln('bench_report.dart: $e');
    exitCode = 1;
  }
}

BenchFile? _read(String? path) {
  if (path == null) return null;
  final file = File(path);
  if (!file.existsSync()) _usageError('no file $path');
  try {
    return BenchFile.parse(
      utf8.decode(file.readAsBytesSync(), allowMalformed: true),
    );
  } on FormatException catch (e) {
    throw _BadFile('$path: ${e.message}');
  }
}

final class _BadFile implements Exception {
  const _BadFile(this.message);

  final String message;

  @override
  String toString() => message;
}

Never _usageError(String message) {
  stderr
    ..writeln('bench_report.dart: $message')
    ..writeln(_usage);
  exit(64);
}
