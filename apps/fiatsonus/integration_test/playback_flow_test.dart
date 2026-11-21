import 'package:fiatsonus/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// A stats readout and the wall time it was first seen.
typedef _Sample = ({Map<String, String> stats, int atMicros});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app plays the waterfall through the foreground service', (
    tester,
  ) async {
    final clock = Stopwatch()..start();

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

    String text(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

    Map<String, String> stats() => {
      for (final line in text('stats').split('\n'))
        if (line.split(': ') case [final name, final value]) name: value,
    };
    int frames() => int.parse(stats()['frames'] ?? '0');

    await app.main();
    await pumpUntil(
      () => find.byKey(const Key('playStop')).evaluate().isNotEmpty,
      const Duration(seconds: 10),
      'the debug screen',
    );
    expect(text('phase'), 'idle');

    await tester.tap(find.byKey(const Key('playStop')));
    await pumpUntil(
      () => text('phase') == 'playing',
      const Duration(seconds: 5),
      'phase playing',
    );

    await pumpUntil(() => frames() > 0, const Duration(seconds: 5), 'stats');
    Future<_Sample> nextStats() async {
      final before = frames();
      await pumpUntil(
        () => frames() != before,
        const Duration(seconds: 3),
        'a stats event',
      );
      return (stats: stats(), atMicros: clock.elapsedMicroseconds);
    }

    final from = await nextStats();
    var to = from;
    while (to.atMicros - from.atMicros < 10000000) {
      to = await nextStats();
    }

    final rate = int.parse(to.stats['rate']!.split(' ').first);
    final seconds = (to.atMicros - from.atMicros) / 1e6;
    final advanced =
        int.parse(to.stats['frames']!) - int.parse(from.stats['frames']!);
    final frameRate = advanced / seconds;
    // ignore: avoid_print
    print(
      'FLOW engine_rate=$rate window_s=${seconds.toStringAsFixed(3)} '
      'frames=$advanced frame_rate=${frameRate.toStringAsFixed(1)} '
      'render=${to.stats['render']} underruns=${to.stats['underruns']} '
      'overlaps=${to.stats['overlaps']} starved=${to.stats['starved']}',
    );
    expect(frameRate, closeTo(rate, rate * 0.05));
    expect(to.stats['underruns'], '0');
    expect(to.stats['overlaps'], '0');

    await tester.tap(find.byKey(const Key('playStop')));
    await pumpUntil(
      () => text('phase') == 'idle',
      const Duration(seconds: 8),
      'phase idle',
    );
    expect(find.byKey(const Key('error')), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
