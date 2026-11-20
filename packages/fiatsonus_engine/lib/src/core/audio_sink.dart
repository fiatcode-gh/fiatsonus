import 'dart:typed_data';

/// Destination for the master's 16-bit output: a device, a file or a test.
abstract interface class AudioSink {
  /// Opens the sink for [channels] interleaved channels at [sampleRate].
  Future<void> start({required int sampleRate, required int channels});

  /// Accepts interleaved 16-bit samples.
  Future<void> write(Int16List interleaved);

  /// Flushes and closes the sink.
  Future<void> stop();
}
