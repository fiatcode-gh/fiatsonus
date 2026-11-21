import 'package:flutter_test/flutter_test.dart';

import '../../tool/device/src/audio_flinger.dart';
import 'fixtures.dart';

void main() {
  test('the active track of the player sits on a 48 kHz output thread', () {
    final threads = parseAudioFlinger(fixture('audio_flinger_active.txt'));
    final tracks = tracksOfPid(threads, kPlayerPid);

    expect(tracks.map((t) => t.id), [214]);
    expect(tracks.single.uid, 10105);
    expect(underrunsOfPid(threads, kPlayerPid), 0);
    expect(sampleRateOfPid(threads, kPlayerPid), 48000);
  });

  test('underruns of the pid are read from the Underruns column', () {
    final threads = parseAudioFlinger(activeAudioFlinger(underruns: 1234));

    expect(underrunsOfPid(threads, kPlayerPid), 1234);
  });

  test('the idle capture sums the tracks of one client', () {
    final threads = parseAudioFlinger(fixture('audio_flinger_idle.txt'));

    expect(tracksOfPid(threads, 4887).map((t) => t.id), [207, 88]);
    expect(underrunsOfPid(threads, 4887), 0);
  });

  test('a pid with no track has 0 underruns and no sample rate', () {
    final threads = parseAudioFlinger(fixture('audio_flinger_active.txt'));

    expect(underrunsOfPid(threads, 1), 0);
    expect(sampleRateOfPid(threads, 1), isNull);
  });

  test('rows of the local log are not tracks', () {
    // The idle capture logs a removed track of pid 2883 in AudioOut_D's
    // local log; no live track of that pid exists.
    final threads = parseAudioFlinger(fixture('audio_flinger_idle.txt'));

    expect(tracksOfPid(threads, 2883), isEmpty);
  });

  test('a track table without the Underruns column is a parse error', () {
    final text = fixture('audio_flinger_active.txt')
        .replaceAll('F Underruns  Flushed', 'F Underflow  Flushed');

    expect(() => parseAudioFlinger(text), throwsA(isA<FormatException>()));
  });
}
