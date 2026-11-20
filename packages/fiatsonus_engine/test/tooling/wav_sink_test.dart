import 'dart:io';
import 'dart:typed_data';

import 'package:fiatsonus_engine/offline.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('wav_sink_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String path(String name) => '${tmp.path}/$name';

  test('writes a 16-bit PCM header and little-endian payload', () async {
    final sink = WavSink(path('a.wav'));
    await sink.start(sampleRate: 48000, channels: 2);
    await sink.write(Int16List.fromList([1, -1, 258, -32768, 32767, 0]));
    await sink.stop();
    expect(sink.framesWritten, 3);

    final bytes = File(path('a.wav')).readAsBytesSync();
    expect(bytes.length, 44 + 12);
    final h = ByteData.sublistView(bytes);
    String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
    expect(tag(0), 'RIFF');
    expect(h.getUint32(4, Endian.little), 36 + 12);
    expect(tag(8), 'WAVE');
    expect(tag(12), 'fmt ');
    expect(h.getUint32(16, Endian.little), 16);
    expect(h.getUint16(20, Endian.little), 1);
    expect(h.getUint16(22, Endian.little), 2);
    expect(h.getUint32(24, Endian.little), 48000);
    expect(h.getUint32(28, Endian.little), 48000 * 2 * 2);
    expect(h.getUint16(32, Endian.little), 4);
    expect(h.getUint16(34, Endian.little), 16);
    expect(tag(36), 'data');
    expect(h.getUint32(40, Endian.little), 12);
    expect(bytes.sublist(44), [
      0x01, 0x00, 0xff, 0xff, 0x02, 0x01, //
      0x00, 0x80, 0xff, 0x7f, 0x00, 0x00,
    ]);
  });

  test('creates a nested directory that does not exist yet', () async {
    final sink = WavSink(path('x/y/z.wav'));
    await sink.start(sampleRate: 44100, channels: 1);
    await sink.stop();
    expect(File(path('x/y/z.wav')).lengthSync(), 44);
  });

  test('write before start and after stop throws StateError', () async {
    final sink = WavSink(path('b.wav'));
    await expectLater(() => sink.write(Int16List(2)), throwsStateError);
    await sink.start(sampleRate: 48000, channels: 2);
    await sink.stop();
    await expectLater(() => sink.write(Int16List(2)), throwsStateError);
  });

  test('a second start throws, a second stop is harmless', () async {
    final sink = WavSink(path('c.wav'));
    await sink.start(sampleRate: 48000, channels: 2);
    await expectLater(
      () => sink.start(sampleRate: 48000, channels: 2),
      throwsStateError,
    );
    await sink.stop();
    await sink.stop();
    expect(File(path('c.wav')).lengthSync(), 44);
  });

  test('invalid channels or sample rate throw ArgumentError', () async {
    await expectLater(
      () => WavSink(path('d.wav')).start(sampleRate: 48000, channels: 3),
      throwsArgumentError,
    );
    await expectLater(
      () => WavSink(path('e.wav')).start(sampleRate: 0, channels: 2),
      throwsArgumentError,
    );
  });
}
