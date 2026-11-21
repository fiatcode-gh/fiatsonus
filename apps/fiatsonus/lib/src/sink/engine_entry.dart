import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../engine/engine_isolate.dart';
import 'soloud_pull_sink.dart';

/// Entry point of the production engine isolate (PLAN 4.2).
///
/// SoLoud's loader asks `path_provider` for the temporary directory during
/// `init`. A spawned isolate has no platform channel, so the path chosen by
/// the root isolate is served from the boot list instead.
@pragma('vm:entry-point')
void engineIsolateMain(List<Object> boot) {
  PathProviderPlatform.instance = _BootPathProvider(
    boot[kBootTempDir] as String,
  );
  runEngineIsolate(boot, SoloudPullSink.new);
}

final class _BootPathProvider extends PathProviderPlatform {
  _BootPathProvider(this._tempPath);

  final String _tempPath;

  @override
  Future<String?> getTemporaryPath() async => _tempPath;
}
