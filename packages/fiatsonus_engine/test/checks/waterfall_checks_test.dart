import 'dart:typed_data';

import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:test/test.dart';

import '../support/fake_soundscape.dart';
import 'soundscape_checks.dart';

const _config = SoundscapeCheckConfig(
  id: 'waterfall',
  lufsMin: -21.0,
  lufsMax: -19.0,
  edgeLufsMin: -36.0,
  edgeLufsMax: -8.0,
);

/// Loudness over 5 s..20 s of a 20 s render of [scape] with [params].
double _lufs(Waterfall scape, int rate, Map<String, double> params) =>
    renderMaster(scape, rate: rate, seconds: 20, params: params).lufs(5, 20);

void main() {
  defineSoundscapeChecks(_config);

  group('S8: a master fault resets the waterfall', () {
    for (final rate in checkRates) {
      test('$rate Hz', () {
        final waterfall = Waterfall();
        final fake = FakeSoundscape(left: 0, right: 0)..faultAtBlock = 400;
        final master = Master(sampleRate: rate, seed: 1)
          ..add(waterfall)
          ..add(fake)
          ..start(waterfall.id)
          ..start(fake.id);
        final out = Int16List(kBlockFrames * 2);
        for (var b = 0; b < 400; b++) {
          master.render(out, kBlockFrames);
        }
        expect(waterfall.isQuiet, isFalse);

        master.render(out, kBlockFrames);
        expect(out, everyElement(0));
        expect(master.faultBlocks, 1);
        expect(waterfall.isQuiet, isTrue);

        master.render(out, kBlockFrames);
        expect(waterfall.isQuiet, isFalse);
        expect(master.faultBlocks, 1);
      });
    }
  });

  group('width 0 is mono', () {
    for (final rate in checkRates) {
      test('$rate Hz: left equals right from 5 s on', () {
        final run = renderMaster(
          Waterfall(),
          rate: rate,
          seconds: 10,
          params: {'width': 0.0},
        );
        var differing = 0;
        for (var f = run.at(5); f < run.frames; f++) {
          if (run.out[2 * f] != run.out[2 * f + 1]) differing++;
        }
        expect(differing, 0);
      });
    }
  });

  group('S4: no layer is hidden', () {
    const configurations = <String, Map<String, double>>{
      'defaults': {},
      'height 0': {'height': 0.0},
      'spray 0': {'spray': 0.0},
      'width 0': {'width': 0.0},
      'distance 0': {'distance': 0.0},
    };
    for (final rate in checkRates) {
      for (final MapEntry(key: name, value: params) in configurations.entries) {
        test('$rate Hz: $name', () {
          final full = _lufs(Waterfall(), rate, params);
          for (final layer in WaterfallLayer.values) {
            if (name == 'spray 0' && layer == WaterfallLayer.spray) {
              final run = renderMaster(
                Waterfall(solo: {layer}),
                rate: rate,
                seconds: 20,
                params: params,
              );
              final from = run.at(5) * 2;
              expect(
                run.out.skip(from).every((s) => s == 0),
                isTrue,
                reason: 'spray at Spray 0 is silent',
              );
              continue;
            }
            expect(
              _lufs(Waterfall(solo: {layer}), rate, params),
              greaterThanOrEqualTo(full - 22.0),
              reason: '${layer.name} (full mix $full LUFS)',
            );
          }
        });
      }
    }
  });

  group('spray gusts and texture are audible at Distance 0', () {
    for (final rate in checkRates) {
      test('$rate Hz', () {
        const params = {'distance': 0.0};
        final full = _lufs(Waterfall(), rate, params);
        for (final layer in [WaterfallLayer.spray, WaterfallLayer.texture]) {
          expect(
            _lufs(Waterfall(solo: {layer}), rate, params),
            greaterThanOrEqualTo(full - 14.0),
            reason: '${layer.name} (full mix $full LUFS)',
          );
        }
      });
    }
  });
}
