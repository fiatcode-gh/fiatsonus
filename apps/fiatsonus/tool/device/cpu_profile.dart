// Captures the Dart VM's CPU samples of one isolate (PLAN D7).
//
// Usage: dart tool/device/cpu_profile.dart --uri <http uri> --seconds <n>
//        --isolate <name part> --out <dir>
//
// <http uri> is the VM service address a profile build prints
// (`http://127.0.0.1:<port>/<token>/`), reached over `adb forward` by
// cpu_profile.sh. Clears the isolate's samples, waits <n> seconds, then
// writes cpu_samples.json and cpu_top.txt to <dir> and prints the table.
// Exits 64 on a usage error, 1 when no or several isolates match or no
// sample was taken.
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'src/cpu_top.dart';

const _usage =
    'usage: dart tool/device/cpu_profile.dart --uri <http uri> --seconds <n> '
    '--isolate <name part> --out <dir>';

/// The largest time extent the VM accepts (2^53 − 1), meaning "all samples".
const _allTime = 9007199254740991;

Future<void> main(List<String> args) async {
  String? uri;
  int? seconds;
  String? part;
  String? out;

  for (var i = 0; i < args.length; i++) {
    String value() => ++i < args.length
        ? args[i]
        : _usageError('${args[i - 1]} needs a value');
    switch (args[i]) {
      case '--uri':
        uri = value();
      case '--seconds':
        final text = value();
        seconds = int.tryParse(text);
        if (seconds == null || seconds <= 0 || text.trim() != '$seconds') {
          _usageError('--seconds wants a positive whole number, not $text');
        }
      case '--isolate':
        part = value();
      case '--out':
        out = value();
      default:
        _usageError('unknown argument ${args[i]}');
    }
  }
  if (uri == null || seconds == null || part == null || out == null) {
    _usageError('--uri, --seconds, --isolate and --out are required');
  }
  final http = Uri.tryParse(uri);
  if (http == null || http.scheme != 'http') {
    _usageError('--uri wants the http address of the VM service, not $uri');
  }
  final ws = http.replace(
    scheme: 'ws',
    pathSegments: [...http.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  );

  final service = await vmServiceConnectUri(ws.toString());
  try {
    final isolates = (await service.getVM()).isolates ?? const <IsolateRef>[];
    final names = [for (final i in isolates) '${i.name}'];
    final matching = [
      for (final i in isolates)
        if ((i.name ?? '').contains(part)) i,
    ];
    if (matching.length != 1) {
      stderr.writeln(
        'cpu_profile.dart: ${matching.length} isolates match "$part"; '
        'isolates: ${names.join(', ')}',
      );
      exitCode = 1;
      return;
    }
    final isolate = matching.single;
    stdout.writeln('isolate ${isolate.name} (${isolate.id})');

    try {
      final flag = await service.setFlag('profiler', 'true');
      stdout.writeln('setFlag profiler=true: ${flag.type}');
    } catch (e) {
      stdout.writeln('setFlag profiler=true failed: $e');
    }
    await service.clearCpuSamples(isolate.id!);
    stdout.writeln('sampling for ${seconds}s');
    await Future<void>.delayed(Duration(seconds: seconds));
    final samples = await service.getCpuSamples(isolate.id!, 0, _allTime);

    final dir = Directory(out)..createSync(recursive: true);
    final json = jsonEncode(samples.toJson());
    File('${dir.path}/cpu_samples.json').writeAsStringSync(json);
    final top = cpuTop(jsonDecode(json) as Map<String, Object?>);
    File('${dir.path}/cpu_top.txt').writeAsStringSync('$top\n');
    stdout.writeln(top);
    if ((samples.sampleCount ?? 0) == 0) {
      stderr.writeln('cpu_profile.dart: no samples');
      exitCode = 1;
    }
  } finally {
    await service.dispose();
  }
}

Never _usageError(String message) {
  stderr
    ..writeln('cpu_profile.dart: $message')
    ..writeln(_usage);
  exit(64);
}
