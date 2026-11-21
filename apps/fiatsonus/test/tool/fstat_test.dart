import 'package:flutter_test/flutter_test.dart';

import '../../tool/device/src/fstat.dart';
import 'fixtures.dart';

void main() {
  test('every field of an FSTAT v=1 logcat line', () {
    final fstat = parseFstat(
      fstatLine(
        epochMs: 1795226960356,
        rate: 44100,
        playUs: 10000000,
        renderUs: 150000,
        maxRenderUs: 900,
        frames: 441000,
        underruns: 2,
        starvedUs: 42000,
        overlaps: 3,
        faults: 1,
        sessions: 4,
      ),
    );

    expect(fstat.epochMs, 1795226960356);
    expect(fstat.sink, 'soloud');
    expect(fstat.rate, 44100);
    expect(fstat.playUs, 10000000);
    expect(fstat.renderUs, 150000);
    expect(fstat.maxRenderUs, 900);
    expect(fstat.frames, 441000);
    expect(fstat.underruns, 2);
    expect(fstat.starvedUs, 42000);
    expect(fstat.overlaps, 3);
    expect(fstat.faults, 1);
    expect(fstat.sessions, 4);
  });

  test('an unknown version is an error', () {
    final line = fstatLine(
      epochMs: 1795226960356,
      version: 2,
      playUs: 1,
      renderUs: 1,
      frames: 1,
    );

    expect(() => parseFstat(line), throwsA(isA<FormatException>()));
  });

  test('a missing field is an error', () {
    final line = fstatLine(
      epochMs: 1795226960356,
      playUs: 1,
      renderUs: 1,
      frames: 1,
    ).replaceFirst(' frames=1', '');

    expect(() => parseFstat(line), throwsA(isA<FormatException>()));
  });

  test('a line without FSTAT is an error', () {
    expect(
      () => parseFstat(
        '         1795226960.356 1 2 I flutter : FSTATE '
        'phase=playing',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
