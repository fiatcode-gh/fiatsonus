/// Desktop tooling for the engine: analysis metrics, a WAV file sink and the
/// offline renderer. Uses `dart:io`, so it is not part of the app barrel.
library;

export 'src/tooling/analysis.dart';
export 'src/tooling/offline_render.dart';
export 'src/tooling/wav_sink.dart';
