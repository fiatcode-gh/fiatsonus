import 'dart:async';
import 'dart:typed_data';

import 'package:fiatsonus/src/engine/metered_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_device_sink.dart';

void main() {
  late FakeDeviceSink inner;
  late MeteredSink sink;
  var now = 0;

  setUp(() async {
    now = 0;
    inner = FakeDeviceSink();
    sink = MeteredSink(inner, nowMicros: () => now);
    await sink.start(sampleRate: 48000, channels: 2);
  });

  test('forwards start, write and stop to the device sink', () async {
    expect(inner.startCount, 1);
    expect(inner.sampleRate, 48000);
    expect(inner.channels, 2);
    await sink.write(Int16List.fromList([1, 2, 3, 4]));
    expect(inner.writes.single, [1, 2, 3, 4]);
    await sink.stop();
    expect(inner.stopCount, 1);
  });

  test('counts frames per write', () async {
    await sink.write(Int16List(2048 * 2));
    expect(sink.frames, 2048);
    await sink.write(Int16List(100 * 2));
    expect(sink.frames, 2148);
  });

  test('render time runs from chunkStart to write entry', () async {
    now = 1000;
    sink.chunkStart();
    now = 1250;
    final write = sink.write(Int16List(4));
    now = 9000; // the write's own wait is not render time
    await write;
    expect(sink.renderMicros, 250);
    expect(sink.maxRenderMicros, 250);

    sink.chunkStart();
    now = 9100;
    await sink.write(Int16List(4));
    expect(sink.renderMicros, 350);
    expect(sink.maxRenderMicros, 250);
  });

  test('maxRenderMicros keeps the longest chunk', () async {
    for (final d in [30, 400, 120]) {
      sink.chunkStart();
      now += d;
      await sink.write(Int16List(4));
    }
    expect(sink.maxRenderMicros, 400);
    expect(sink.renderMicros, 550);
  });

  test('a write without chunkStart adds no render time', () async {
    now = 500;
    await sink.write(Int16List(4));
    expect(sink.renderMicros, 0);
  });

  test('sequential writes are no overlap', () async {
    await sink.write(Int16List(4));
    await sink.write(Int16List(4));
    expect(sink.overlaps, 0);
  });

  test('a write entered while one is pending is an overlap', () async {
    final gate = inner.gate = Completer<void>();
    final first = sink.write(Int16List(4));
    final second = sink.write(Int16List(4));
    expect(sink.overlaps, 1);
    gate.complete();
    await Future.wait([first, second]);
    await sink.write(Int16List(4));
    expect(sink.overlaps, 1);
  });
}
