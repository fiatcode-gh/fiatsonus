import 'package:fiatsonus/src/sink/lead_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

const _tolerance = 42666;

LeadTracker _tracker() =>
    LeadTracker(toleranceMicros: _tolerance, blockDemands: 4);

void _feedMs(LeadTracker tracker, List<int> leadsMs) {
  for (final ms in leadsMs) {
    tracker.observe(ms * 1000);
  }
}

List<int> _steadyMs(int ms, {int blocks = 1}) =>
    List<int>.filled(4 * blocks, ms);

void main() {
  test('a rising start-up then a steady lead is no underrun', () {
    final tracker = _tracker();
    _feedMs(tracker, [0, 42, 85, 128, ..._steadyMs(128, blocks: 3)]);

    expect(tracker.underruns, 0);
    expect(tracker.starvedMicros, 0);
    expect(tracker.referenceMicros, 128000);
    expect(tracker.jitterMicros, 0);
  });

  test('a starvation that leaves the lead lower is one underrun', () {
    final tracker = _tracker();
    _feedMs(tracker, [
      ..._steadyMs(128, blocks: 2),
      -256,
      -213,
      -170,
      -128,
      ..._steadyMs(-128, blocks: 3),
    ]);

    expect(tracker.underruns, 1);
    expect(tracker.starvedMicros, 256000);
    expect(tracker.referenceMicros, -128000);
  });

  test('a second later drop adds to the total', () {
    final tracker = _tracker();
    _feedMs(tracker, [
      ..._steadyMs(128, blocks: 2),
      ..._steadyMs(28),
      ..._steadyMs(28, blocks: 2),
      ..._steadyMs(-72),
    ]);

    expect(tracker.underruns, 2);
    expect(tracker.starvedMicros, 200000);
    expect(tracker.referenceMicros, -72000);
  });

  test('a drop within the tolerance is jitter, not an underrun', () {
    final tracker = _tracker();
    _feedMs(tracker, [
      ..._steadyMs(128, blocks: 2),
      ..._steadyMs(100),
      ..._steadyMs(138),
      ..._steadyMs(120),
    ]);

    expect(tracker.underruns, 0);
    expect(tracker.starvedMicros, 0);
    expect(tracker.jitterMicros, 28000);
    expect(tracker.referenceMicros, 138000);
  });

  test('reset clears everything', () {
    final tracker = _tracker();
    _feedMs(tracker, [..._steadyMs(128, blocks: 2), ..._steadyMs(-128)]);
    expect(tracker.underruns, 1);

    tracker.reset();

    expect(tracker.underruns, 0);
    expect(tracker.starvedMicros, 0);
    expect(tracker.jitterMicros, 0);
    expect(tracker.referenceMicros, 0);
    _feedMs(tracker, [..._steadyMs(-500), ..._steadyMs(128)]);
    expect(tracker.underruns, 0);
    expect(tracker.referenceMicros, 128000);
  });

  test('fewer than two full blocks report nothing', () {
    final tracker = _tracker();
    _feedMs(tracker, [0, 42, 85, 128, 128, 128, 128]);

    expect(tracker.underruns, 0);
    expect(tracker.starvedMicros, 0);
    expect(tracker.jitterMicros, 0);
    expect(tracker.referenceMicros, 0);
  });
}
