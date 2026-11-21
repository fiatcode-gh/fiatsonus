import 'dart:async';

import 'package:fiatsonus/src/engine/device_sink.dart';
import 'package:fiatsonus/src/engine/engine_client.dart';
import 'package:fiatsonus/src/engine/engine_protocol.dart';
import 'package:fiatsonus/src/engine/engine_stats.dart';
import 'package:fiatsonus/src/sink/engine_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _rate = 48000;

/// A stats snapshot and the wall time it arrived.
typedef _Sample = ({EngineStats stats, int atMicros});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the engine isolate plays the waterfall through the soloud sink',
    (tester) async {
      final client = await IsolateEngineClient.spawn(
        sampleRate: _rate,
        seed: 20261121,
        tempDirPath: (await getTemporaryDirectory()).path,
        entryPoint: engineIsolateMain,
      );
      expect(client.sinkId, 'soloud');

      final clock = Stopwatch()..start();
      final errors = <EngineError>[];
      final states = StreamController<bool>.broadcast();
      _Sample? latest;
      final sub = client.events.listen((event) {
        switch (event) {
          case EngineError():
            errors.add(event);
          case EngineStateChanged(:final playing):
            states.add(playing);
          case EngineStatsEvent(:final stats):
            latest = (stats: stats, atMicros: clock.elapsedMicroseconds);
          case EngineReady():
        }
      });

      final playing = states.stream.firstWhere((p) => p);
      client.start('waterfall', fade: kPlayFade);
      await playing.timeout(const Duration(seconds: 5));

      await Future<void>.delayed(const Duration(seconds: 5));
      final from = latest!;
      await Future<void>.delayed(const Duration(seconds: 15));
      final to = latest!;

      final seconds = (to.atMicros - from.atMicros) / 1e6;
      final frameRate = (to.stats.frames - from.stats.frames) / seconds;
      // ignore: avoid_print
      print(
        'SMOKE window_s=${seconds.toStringAsFixed(3)} '
        'frame_rate=${frameRate.toStringAsFixed(1)} '
        'render_ratio=${to.stats.renderRatio.toStringAsFixed(4)} '
        'max_render_us=${to.stats.maxRenderMicros} '
        'underruns=${to.stats.underruns} starved_us=${to.stats.starvedMicros}',
      );
      expect(seconds, greaterThan(13));
      expect(frameRate, closeTo(_rate, _rate * 0.03));
      expect(to.stats.underruns, from.stats.underruns);
      expect(to.stats.starvedMicros, from.stats.starvedMicros);
      expect(to.stats.overlaps, from.stats.overlaps);
      expect(to.stats.faults, from.stats.faults);
      expect(to.stats.renderRatio, lessThan(0.25));

      final stopped = states.stream.firstWhere((p) => !p);
      client.stop('waterfall', fade: kStopFade);
      await stopped.timeout(const Duration(seconds: 6));

      expect(errors, isEmpty);
      await sub.cancel();
      await states.close();
      await client.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
