import 'dart:typed_data';

import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:fiatsonus_engine/offline.dart';
import 'package:test/test.dart';

import '../support/recording_sink.dart';

/// [RecordingSink] that also records the arguments of every `start`.
final class _ArgsSink implements AudioSink {
  final RecordingSink inner = RecordingSink();
  final List<(int, int)> starts = [];

  @override
  Future<void> start({required int sampleRate, required int channels}) {
    starts.add((sampleRate, channels));
    return inner.start(sampleRate: sampleRate, channels: channels);
  }

  @override
  Future<void> write(Int16List interleaved) => inner.write(interleaved);

  @override
  Future<void> stop() => inner.stop();
}

Future<(RenderSummary, Int16List)> _render(RenderJob job) async {
  final sink = RecordingSink();
  final summary = await renderOffline(job, sink);
  return (summary, sink.data);
}

void main() {
  const job = RenderJob(scapeId: 'waterfall', seconds: 8);

  test('an 8 s job writes the whole timeline and ends silent', () async {
    final sink = _ArgsSink();
    final summary = await renderOffline(job, sink);
    expect(summary.frames, 384000);
    expect(sink.starts, [(48000, 2)]);
    expect(sink.inner.startCalls, 1);
    expect(sink.inner.stopCalls, 1);
    final data = sink.inner.data;
    expect(data.length, 384000 * 2);
    expect(data.sublist(data.length - 2048).every((s) => s == 0), isTrue);
    expect(summary.endedSilent, isTrue);
    expect(summary.faultBlocks, 0);
    expect(summary.peak, inInclusiveRange(1000, 29203));
    expect(summary.lufs.isFinite, isTrue);
    expect(summary.realtimeFactor, greaterThan(0));
  });

  test('the same job is sample-identical, another seed differs', () async {
    final (_, a) = await _render(job);
    final (_, b) = await _render(job);
    final (_, c) = await _render(
      const RenderJob(scapeId: 'waterfall', seconds: 8, seed: 2),
    );
    expect(b, a);
    expect(c, isNot(a));
  });

  test('a fixed far distance is quieter than the default', () async {
    final (near, _) = await _render(job);
    final (far, _) = await _render(
      const RenderJob(
        scapeId: 'waterfall',
        seconds: 8,
        params: {'distance': 1.0},
      ),
    );
    expect(far.lufs, lessThan(near.lufs));
  });

  test('a sweep changes the render and still ends silent', () async {
    final (plain, a) = await _render(
      const RenderJob(scapeId: 'waterfall', seconds: 38),
    );
    final (swept, b) = await _render(
      const RenderJob(
        scapeId: 'waterfall',
        seconds: 38,
        sweepParam: 'distance',
      ),
    );
    expect(plain.endedSilent, isTrue);
    expect(swept.endedSilent, isTrue);
    expect(swept.faultBlocks, 0);
    expect(b, isNot(a));
  });

  test('invalid jobs throw ArgumentError', () async {
    for (final bad in [
      const RenderJob(scapeId: 'nope', seconds: 8),
      const RenderJob(scapeId: 'waterfall', seconds: 8, params: {'nope': 1}),
      const RenderJob(scapeId: 'waterfall', seconds: 8, sweepParam: 'nope'),
      const RenderJob(
        scapeId: 'waterfall',
        seconds: 8,
        params: {'height': double.nan},
      ),
      const RenderJob(scapeId: 'waterfall', seconds: 5.9),
    ]) {
      final sink = RecordingSink();
      await expectLater(renderOffline(bad, sink), throwsArgumentError);
      expect(sink.startCalls, 0);
    }
  });

  test('44100 works', () async {
    final (summary, data) = await _render(
      const RenderJob(scapeId: 'waterfall', seconds: 6, sampleRate: 44100),
    );
    expect(summary.frames, 264600);
    expect(data.length, 264600 * 2);
    expect(summary.endedSilent, isTrue);
    expect(summary.sampleRate, 44100);
    final wallSeconds = summary.elapsed.inMicroseconds / 1e6;
    expect(summary.realtimeFactor, closeTo(6.0 / wallSeconds, 1e-9));
  });

  test('realtimeFactor divides by the summary sample rate', () {
    const summary = RenderSummary(
      frames: 88200,
      peak: 0,
      lufs: double.negativeInfinity,
      faultBlocks: 0,
      endedSilent: true,
      elapsed: Duration(milliseconds: 500),
      sampleRate: 44100,
    );
    expect(summary.realtimeFactor, closeTo(4.0, 1e-12));
  });
}
