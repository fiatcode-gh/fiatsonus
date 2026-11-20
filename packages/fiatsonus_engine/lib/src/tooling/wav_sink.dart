import 'dart:io';
import 'dart:typed_data';

import '../core/audio_sink.dart';

/// [AudioSink] that writes a 16-bit PCM WAV file (desktop tooling).
final class WavSink implements AudioSink {
  static const int _headerBytes = 44;
  static const int _maxDataBytes = 0xFFFFFFFF - 36;

  final String _path;
  RandomAccessFile? _file;
  bool _started = false;
  int _channels = 0;
  int _dataBytes = 0;
  int _framesWritten = 0;

  /// Throws [UnsupportedError] on a big-endian host.
  WavSink(String path) : _path = path {
    if (Endian.host != Endian.little) {
      throw UnsupportedError('WavSink needs a little-endian host');
    }
  }

  /// Frames written so far.
  int get framesWritten => _framesWritten;

  /// Creates parent directories and opens the file (truncating), writing a
  /// header with zero sizes. Throws [ArgumentError] unless [channels] is 1 or
  /// 2 and [sampleRate] is positive; throws [StateError] on a second call.
  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    if (channels != 1 && channels != 2) {
      throw ArgumentError.value(channels, 'channels', 'must be 1 or 2');
    }
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
    }
    if (_started) throw StateError('WavSink already started');
    _started = true;
    _channels = channels;
    File(_path).parent.createSync(recursive: true);
    final file = File(_path).openSync(mode: FileMode.write);
    _file = file;
    final h = ByteData(_headerBytes);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    h.setUint32(4, 0, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, channels, Endian.little);
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * channels * 2, Endian.little);
    h.setUint16(32, channels * 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    h.setUint32(40, 0, Endian.little);
    file.writeFromSync(h.buffer.asUint8List());
  }

  /// Appends [interleaved]. Throws [StateError] before [start], after [stop],
  /// or when the data chunk would outgrow the WAV size field.
  @override
  Future<void> write(Int16List interleaved) async {
    final file = _file;
    if (file == null) throw StateError('WavSink is not open');
    final bytes = interleaved.lengthInBytes;
    if (_dataBytes + bytes > _maxDataBytes) {
      throw StateError('WAV data would exceed the 4 GiB size limit');
    }
    file.writeFromSync(
      interleaved.buffer.asUint8List(interleaved.offsetInBytes, bytes),
    );
    _dataBytes += bytes;
    _framesWritten += interleaved.length ~/ _channels;
  }

  /// Patches the RIFF and data sizes and closes the file. A second call does
  /// nothing.
  @override
  Future<void> stop() async {
    final file = _file;
    if (file == null) return;
    _file = null;
    final size = ByteData(4);
    file.setPositionSync(4);
    size.setUint32(0, 36 + _dataBytes, Endian.little);
    file.writeFromSync(size.buffer.asUint8List());
    file.setPositionSync(40);
    size.setUint32(0, _dataBytes, Endian.little);
    file.writeFromSync(size.buffer.asUint8List());
    file.closeSync();
  }
}
