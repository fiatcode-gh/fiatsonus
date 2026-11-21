import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'src/engine/engine_client.dart';
import 'src/playback/audio_focus.dart';
import 'src/playback/notification_permission.dart';
import 'src/playback/playback_handler.dart';
import 'src/sink/engine_entry.dart';
import 'src/ui/debug_screen.dart';

const _scapeId = 'waterfall';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = await IsolateEngineClient.spawn(
    sampleRate: await _outputSampleRate(),
    seed: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
    tempDirPath: (await getTemporaryDirectory()).path,
    entryPoint: engineIsolateMain,
  );
  final focus = await AudioSessionFocus.create();
  final handler = await AudioService.init(
    builder: () => PlaybackHandler(
      engine: engine,
      focus: focus,
      requestNotificationPermission: requestNotificationPermission,
      soundscapeId: _scapeId,
      title: 'Waterfall',
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.fiatcode.fiatsonus.playback',
      androidNotificationChannelName: 'Playback',
      androidStopForegroundOnPause: false,
      androidResumeOnClick: false,
    ),
  );
  runApp(
    MaterialApp(
      title: 'fiatsonus',
      home: DebugScreen(
        handler: handler,
        params: createSoundscape(_scapeId)!.params,
        sampleRate: engine.sampleRate,
        sinkId: engine.sinkId,
      ),
    ),
  );
}

/// The device's output rate when the engine supports it, else 48000
/// (PLAN 4.8).
Future<int> _outputSampleRate() async {
  try {
    final rate = await AndroidAudioManager().getOutputSampleRate();
    if (rate == 44100 || rate == 48000) return rate!;
  } on Object {
    // Fall through to the default.
  }
  return 48000;
}
