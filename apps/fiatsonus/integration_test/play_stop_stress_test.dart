import 'package:fiatsonus/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// The pause after tap `i`: a fixed sequence spread over 40–250 ms.
Duration _gap(int i) => Duration(milliseconds: 40 + (i * 37 + 11) % 211);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('100 fast play/stop taps leave one clean feed', (tester) async {
    final clock = Stopwatch()..start();
    final playStop = find.byKey(const Key('playStop'));

    Future<void> pumpUntil(
      bool Function() done,
      Duration timeout,
      String what,
    ) async {
      final deadline = clock.elapsed + timeout;
      while (true) {
        await tester.pump();
        if (done()) return;
        if (clock.elapsed > deadline) fail('timed out waiting for $what');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    String text(Key key) => tester.widget<Text>(find.byKey(key)).data!;
    String phase() => text(const Key('phase'));
    String label() => tester
        .widget<Text>(
          find.descendant(of: playStop, matching: find.byType(Text)),
        )
        .data!;
    Map<String, String> stats() => {
      for (final line in text(const Key('stats')).split('\n'))
        if (line.split(': ') case [final name, final value]) name: value,
    };
    int stat(String name) => int.parse(stats()[name]!.split(' ').first);

    await app.main();
    await pumpUntil(
      () => playStop.evaluate().isNotEmpty,
      const Duration(seconds: 10),
      'the debug screen',
    );
    expect(phase(), 'idle');

    for (var i = 0; i < 100; i++) {
      await tester.tap(playStop);
      await tester.pump(_gap(i));
    }
    if (label() == 'Stop') await tester.tap(playStop);
    await pumpUntil(
      () => phase() == 'idle',
      const Duration(seconds: 10),
      'phase idle after the taps',
    );
    expect(find.byKey(const Key('error')), findsNothing);
    final afterTaps = stats();
    // ignore: avoid_print
    print('FLOW after_taps ${afterTaps.entries.join(' ')}');
    expect(stat('overlaps'), 0);
    expect(stat('faults'), 0);

    // The taps never reach idle (a stop takes about 3.5 s), so the stop's
    // notification repair (PLAN 4.6) runs only after them. Each replay plays
    // 0–99 ms after idle was seen, while that repair may still be polling.
    for (var i = 0; i < 10; i++) {
      await tester.pump(Duration(milliseconds: 11 * i));
      await tester.tap(playStop);
      await pumpUntil(
        () => phase() == 'playing',
        const Duration(seconds: 5),
        'phase playing in replay ${i + 1}',
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('error')), findsNothing);
      await tester.tap(playStop);
      await pumpUntil(
        () => phase() == 'idle',
        const Duration(seconds: 8),
        'phase idle in replay ${i + 1}',
      );
      // ignore: avoid_print
      print('FLOW replay n=${i + 1} delay_ms=${11 * i}');
    }
    expect(stat('overlaps'), 0);
    expect(stat('faults'), 0);

    await tester.tap(playStop);
    await pumpUntil(
      () => phase() == 'playing',
      const Duration(seconds: 5),
      'phase playing',
    );
    await tester.pump(const Duration(seconds: 5));

    // Stats arrive once per second of audio; time the window between
    // arrivals so the frame count and the wall time describe the same span.
    Future<({int frames, int underruns, int atMicros})> nextStats() async {
      final before = stat('frames');
      await pumpUntil(
        () => stat('frames') != before,
        const Duration(seconds: 3),
        'a stats event',
      );
      return (
        frames: stat('frames'),
        underruns: stat('underruns'),
        atMicros: clock.elapsedMicroseconds,
      );
    }

    final from = await nextStats();
    var to = from;
    while (to.atMicros - from.atMicros < 5000000) {
      to = await nextStats();
    }
    final rate = stat('rate');
    final seconds = (to.atMicros - from.atMicros) / 1e6;
    final frameRate = (to.frames - from.frames) / seconds;
    // ignore: avoid_print
    print(
      'FLOW engine_rate=$rate window_s=${seconds.toStringAsFixed(3)} '
      'frames=${to.frames - from.frames} '
      'frame_rate=${frameRate.toStringAsFixed(1)} '
      'underruns=${from.underruns}->${to.underruns} '
      'render=${stats()['render']}',
    );
    expect(frameRate, closeTo(rate, rate * 0.05));
    expect(to.underruns, from.underruns);

    await tester.tap(playStop);
    await pumpUntil(
      () => phase() == 'idle',
      const Duration(seconds: 8),
      'phase idle',
    );
    expect(find.byKey(const Key('error')), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
