import 'package:fiatsonus_engine/fiatsonus_engine.dart';

/// Frames the engine renders per `write`.
const int kChunkFrames = 2048;

/// Frames a device sink keeps queued ahead of the output.
const int kSinkBufferFrames = 8192;

/// Fade of a play tap.
const Duration kPlayFade = Duration(milliseconds: 2000);

/// Fade of a stop tap.
const Duration kStopFade = Duration(milliseconds: 3000);

/// Fade of an audio-focus interruption.
const Duration kInterruptFade = Duration(milliseconds: 200);

/// An [AudioSink] on a real output. `write` waits for the package's demand,
/// then hands the chunk over. Its future completes from the event queue.
abstract interface class DeviceSink implements AudioSink {
  /// Short name of the sink, used in logs and stats.
  String get id;

  /// Underruns since the last `start`.
  int get underruns;

  /// Starved output time since the last `start`; 0 when not measurable.
  int get starvedMicros;
}
