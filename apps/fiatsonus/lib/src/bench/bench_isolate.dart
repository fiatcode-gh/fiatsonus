import '../engine/engine_log.dart';
import 'bench_runner.dart';

/// Entry point of the `bench` isolate: `boot[0]` is the mode, `boot[1]` the
/// build. Anything thrown becomes one `FBENCH error` line, which ends the run
/// for `bench_run.sh`.
@pragma('vm:entry-point')
void benchIsolateMain(List<String> boot) {
  try {
    runBench(mode: boot[0], build: boot[1], log: logLine);
  } catch (e) {
    logLine('FBENCH error ${'$e'.replaceAll(RegExp(r'\s*\n\s*'), ' ')}');
  }
}
