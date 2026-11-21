import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../engine/device_sink.dart';
import '../engine/engine_log.dart';
import 'lead_tracker.dart';

/// A [DeviceSink] on `flutter_soloud`'s pull stream (PLAN 2, 4.4).
///
/// `write` waits for the stream's `onMoreDataIsNeeded` callback, which
/// arrives through the event queue of this isolate, then appends the chunk.
/// Starvation is measured by a [LeadTracker] on the stream's lead at each
/// demand.
final class SoloudPullSink implements DeviceSink {
  AudioSource? _source;
  SoundHandle? _handle;
  Completer<void> _demand = Completer<void>();
  LeadTracker? _tracker;

  @override
  String get id => 'soloud';

  @override
  int get underruns => _tracker?.underruns ?? 0;

  @override
  int get starvedMicros => _tracker?.starvedMicros ?? 0;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    if (channels != 2) {
      throw ArgumentError.value(channels, 'channels', 'must be 2');
    }
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      await soloud.init(
        sampleRate: sampleRate,
        bufferSize: kChunkFrames,
        channels: Channels.stereo,
        lowLatency: false,
      );
    }
    _demand = Completer<void>();
    _tracker = LeadTracker(
      toleranceMicros: kChunkFrames * 1000000 ~/ sampleRate,
    );
    final source = _source = soloud.setPullBufferStream(
      bufferSizeBytes: kSinkBufferFrames * 2 * 4,
      bufferTriggerPosition: 0.1,
      sampleRate: sampleRate,
      channels: Channels.stereo,
      format: BufferType.s16le,
      audioSizeBytes: 1 << 46,
      onMoreDataIsNeeded: (_) {
        if (!_demand.isCompleted) _demand.complete();
      },
    );
    _handle = soloud.play(source);
  }

  @override
  Future<void> write(Int16List interleaved) async {
    await _demand.future;
    _demand = Completer<void>();
    final soloud = SoLoud.instance;
    final source = _source!;
    final lead =
        soloud.getPullBufferTimeRange(source).endTime.inMicroseconds -
        soloud.getPosition(_handle!).inMicroseconds;
    _tracker!.observe(lead);
    soloud.addPullBufferDataStream(source, Uint8List.sublistView(interleaved));
  }

  @override
  Future<void> stop() async {
    final soloud = SoLoud.instance;
    final handle = _handle;
    final source = _source;
    _handle = null;
    _source = null;
    if (handle != null) await soloud.stop(handle);
    if (source != null) await soloud.disposeSource(source);
    final tracker = _tracker;
    if (tracker != null) {
      logLine(
        'FLEAD sink=soloud ref_us=${tracker.referenceMicros} '
        'jitter_us=${tracker.jitterMicros} underruns=${tracker.underruns} '
        'starved_us=${tracker.starvedMicros}',
      );
    }
  }
}
