// The on-device benchmark (PLAN D3): build with
//   tool/device/install.sh [--profile] --target=lib/bench_main.dart
//       [--dart-define=FIATSONUS_BENCH_MODE=loop]
// and run with tool/device/bench_run.sh. lib/main.dart never imports it.
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'src/bench/bench_isolate.dart';

const String _mode = String.fromEnvironment(
  'FIATSONUS_BENCH_MODE',
  defaultValue: 'measure',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Center(
      child: Text(
        'fiatsonus bench: $_mode',
        textDirection: TextDirection.ltr,
        style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 18),
      ),
    ),
  );
  final build = kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';
  await Isolate.spawn(benchIsolateMain, [_mode, build], debugName: 'bench');
}
