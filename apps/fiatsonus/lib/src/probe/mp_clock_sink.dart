import 'dart:typed_data';

import 'package:mp_audio_stream/mp_audio_stream.dart';

import '../engine/device_sink.dart';

/// The `mp` probe sink on `mp_audio_stream`, which has no demand signal:
/// `write` pushes, then waits on a clock until no more than 128 ms are
/// queued ahead of it. Non-compliant by design (PLAN 2).
final class MpClockSink implements DeviceSink {
  static const int _aheadMicros = 128000;

  final AudioStream _stream = getAudioStream();
  final Stopwatch _clock = Stopwatch();
  Float32List _floats = Float32List(0);
  int _rate = 0;
  int _pushedFrames = 0;
  int _exhaustAtStart = 0;
  int _closedUnderruns = 0;
  bool _open = false;

  @override
  String get id => 'mp';

  @override
  int get underruns =>
      _open ? _stream.stat().exhaust - _exhaustAtStart : _closedUnderruns;

  @override
  int get starvedMicros => 0;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    if (channels != 2) {
      throw ArgumentError.value(channels, 'channels', 'must be 2');
    }
    final result = _stream.init(
      bufferMilliSec: 171,
      waitingBufferMilliSec: 85,
      channels: 2,
      sampleRate: sampleRate,
    );
    if (result != 0) throw StateError('mp_audio_stream init returned $result');
    _rate = sampleRate;
    _pushedFrames = 0;
    _clock
      ..stop()
      ..reset();
    _exhaustAtStart = _stream.stat().exhaust;
    _open = true;
  }

  @override
  Future<void> write(Int16List interleaved) async {
    if (_floats.length != interleaved.length) {
      _floats = Float32List(interleaved.length);
    }
    for (var i = 0; i < interleaved.length; i++) {
      _floats[i] = interleaved[i] / 32768;
    }
    _stream.push(_floats);
    _clock.start();
    _pushedFrames += interleaved.length ~/ 2;
    final ahead = _pushedFrames * 1000000 ~/ _rate - _clock.elapsedMicroseconds;
    if (ahead > _aheadMicros) {
      await Future<void>.delayed(Duration(microseconds: ahead - _aheadMicros));
    }
  }

  @override
  Future<void> stop() async {
    if (!_open) return;
    _closedUnderruns = underruns;
    _open = false;
    _stream.uninit();
  }
}
