import 'dart:async';
import 'dart:typed_data';

import 'package:fiatsonus_engine/src/master/master.dart';
import 'package:fiatsonus_engine/src/master/sink_pump.dart';
import 'package:test/test.dart';

import '../support/fake_soundscape.dart';
import '../support/recording_sink.dart';

/// A playing master whose output differs from block to block.
(Master, FakeSoundscape) _master() {
  final f = FakeSoundscape(left: 0.1, right: -0.1, rampPerBlock: 1e-3);
  final m = Master(sampleRate: 48000, seed: 3)
    ..add(f)
    ..start('fake', fade: Duration.zero);
  return (m, f);
}

/// The first [frames] frames of a fresh twin master, rendered in one call.
Int16List _twin(int frames) {
  final (m, _) = _master();
  final out = Int16List(frames * 2);
  m.render(out, frames);
  return out;
}

void main() {
  test('run(frames) writes exactly that many frames in chunks', () async {
    final (m, _) = _master();
    final sink = RecordingSink();
    final pump = SinkPump(m, sink);
    expect(await pump.run(frames: 10000), 10000);
    expect(sink.writes.map((w) => w.length ~/ 2), [
      ...List.filled(9, 1024),
      784,
    ]);
    expect(sink.data, _twin(10000));
    expect(sink.startCalls, 0);
    expect(sink.stopCalls, 0);
  });

  test('beforeChunk sees the running frame count once per chunk', () async {
    final (m, _) = _master();
    final pump = SinkPump(m, RecordingSink());
    final seen = <int>[];
    await pump.run(frames: 3000, beforeChunk: seen.add);
    expect(seen, [0, 1024, 2048]);
  });

  test('run() without frames returns once the master is silent', () async {
    final (m, _) = _master();
    final sink = RecordingSink();
    final pump = SinkPump(m, sink);
    await pump.run(frames: 2048);
    m.stop('fake', fade: const Duration(milliseconds: 100));
    final written = await pump.run();
    expect(written, greaterThanOrEqualTo(4800));
    expect(written % 1024, 0);
    expect(m.isSilent, isTrue);
    final after = Int16List(2048);
    m.render(after, 1024);
    expect(after.every((s) => s == 0), isTrue);
  });

  test('a superseding run continues where the old one stopped', () async {
    final (m, f) = _master();
    final sink = RecordingSink()..gate = Completer<void>();
    final pump = SinkPump(m, sink);
    final a = pump.run(frames: 4096);
    await Future<void>.delayed(Duration.zero);
    expect(sink.writes, hasLength(1));
    final b = pump.run(frames: 3072);
    await Future<void>.delayed(Duration.zero);
    expect(sink.writes, hasLength(1));
    expect(f.renderCount, 4);
    sink.gate!.complete();
    expect(await a, 1024);
    expect(await b, 3072);
    expect(sink.writes, hasLength(4));
    expect(sink.data, _twin(4096));
    expect(pump.session, 2);
  });

  test('S6: 100 overlapping runs leave one writer', () async {
    final (m, _) = _master();
    final sink = RecordingSink(deferWrites: true);
    final pump = SinkPump(m, sink);
    final runs = [for (var i = 0; i < 100; i++) pump.run(frames: 20480)];
    final written = await Future.wait(runs);
    expect(written.first, 1024);
    expect(written.sublist(1, 99).every((w) => w == 0), isTrue);
    expect(written.last, 20480);
    expect(sink.frames, 21504);
    expect(sink.data, _twin(21504));
    expect(pump.session, 100);
  });

  test('cancel stops a blocked run after its current write', () async {
    final (m, f) = _master();
    final sink = RecordingSink()..gate = Completer<void>();
    final pump = SinkPump(m, sink);
    final run = pump.run(frames: 10000);
    await Future<void>.delayed(Duration.zero);
    final rendered = f.renderCount;
    pump.cancel();
    sink.gate!.complete();
    expect(await run, 1024);
    expect(f.renderCount, rendered);
    expect(sink.writes, hasLength(1));
  });

  test('chunkFrames below 1 throws ArgumentError', () async {
    for (final bad in [0, -1]) {
      final (m, _) = _master();
      expect(
        () => SinkPump(m, RecordingSink(), chunkFrames: bad),
        throwsArgumentError,
        reason: '$bad',
      );
    }
    final (m, _) = _master();
    final sink = RecordingSink();
    final pump = SinkPump(m, sink, chunkFrames: 1);
    expect(await pump.run(frames: 3), 3);
    expect(sink.writes.map((w) => w.length), [2, 2, 2]);
    expect(sink.data, _twin(3));
  });

  test('a failing write completes run with that error', () async {
    final (m, _) = _master();
    final pump = SinkPump(m, RecordingSink(writeError: StateError('device')));
    await expectLater(pump.run(frames: 4096), throwsStateError);
  });
}
