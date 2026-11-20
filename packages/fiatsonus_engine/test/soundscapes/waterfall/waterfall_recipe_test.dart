import 'package:fiatsonus_engine/src/soundscapes/waterfall/waterfall_recipe.dart';
import 'package:test/test.dart';

typedef _Fn = double Function(double);

const _functions = <String, _Fn>{
  'roarLowPassHz': WaterfallRecipe.roarLowPassHz,
  'bodyLowPassHz': WaterfallRecipe.bodyLowPassHz,
  'bodyLevel': WaterfallRecipe.bodyLevel,
  'textureRate': WaterfallRecipe.textureRate,
  'sprayLevel': WaterfallRecipe.sprayLevel,
  'textureLevel': WaterfallRecipe.textureLevel,
  'distanceLowPassHz': WaterfallRecipe.distanceLowPassHz,
  'reverbSend': WaterfallRecipe.reverbSend,
  'outputGain': WaterfallRecipe.outputGain,
};

void _expectAt(_Fn f, List<double> args, List<double> want, double tol) {
  for (var i = 0; i < args.length; i++) {
    expect(f(args[i]), closeTo(want[i], tol), reason: 'at ${args[i]}');
  }
}

void main() {
  test('params: ids, labels, defaults, order and smoothing', () {
    final p = WaterfallRecipe.params;
    expect(p.map((s) => s.id), ['height', 'spray', 'width', 'distance']);
    expect(p.map((s) => s.label), ['Height', 'Spray', 'Width', 'Distance']);
    expect(p.map((s) => s.defaultValue), [0.5, 0.4, 0.7, 0.4]);
    for (final s in p) {
      expect(s.smoothing, const Duration(milliseconds: 200));
    }
  });

  test('height mappings', () {
    const at = [0.0, 0.5, 1.0];
    _expectAt(WaterfallRecipe.roarLowPassHz, at, [6000, 8000, 10000], 1e-9);
    _expectAt(WaterfallRecipe.bodyLowPassHz, at, [250, 185, 120], 1e-9);
    _expectAt(WaterfallRecipe.bodyLevel, at, [0.3, 0.65, 1.0], 1e-12);
    _expectAt(WaterfallRecipe.textureRate, at, [100, 250, 400], 1e-9);
  });

  test('spray level is linear', () {
    _expectAt(WaterfallRecipe.sprayLevel, [0, 0.4, 1], [0, 0.4, 1], 1e-12);
    expect(WaterfallRecipe.sprayLevel(0), 0.0);
  });

  test('distance mappings', () {
    _expectAt(WaterfallRecipe.distanceLowPassHz, [0, 1], [12000, 1500], 0.01);
    expect(WaterfallRecipe.distanceLowPassHz(0.4), closeTo(5223, 1));
    _expectAt(WaterfallRecipe.reverbSend, [0, 0.4, 1], [0.1, 0.3, 0.6], 1e-12);
    expect(WaterfallRecipe.outputGain(0), closeTo(0.78, 1e-12));
    expect(WaterfallRecipe.outputGain(1), closeTo(0.78 * 0.2512, 0.0005));
    expect(WaterfallRecipe.textureLevel(0), closeTo(1.4, 1e-12));
    expect(WaterfallRecipe.textureLevel(1), closeTo(1.4 * 0.2512, 0.0005));
  });

  test('every mapping clamps its argument and stays finite', () {
    _functions.forEach((name, f) {
      expect(f(-1), f(0), reason: '$name(-1)');
      expect(f(2), f(1), reason: '$name(2)');
      expect(f(double.nan), f(0), reason: '$name(NaN)');
      for (final x in [-1.0, 0.0, 0.5, 1.0, 2.0, double.nan]) {
        expect(f(x).isFinite, isTrue, reason: '$name($x)');
      }
    });
  });

  test('tunable constants equal the plan values', () {
    expect(WaterfallRecipe.roarGain, 1.0);
    expect(WaterfallRecipe.bodyGain, 1.0);
    expect(WaterfallRecipe.sprayGain, 1.0);
    expect(WaterfallRecipe.textureGain, 1.4);
    expect(WaterfallRecipe.textureDistanceDb, -12.0);
    expect(WaterfallRecipe.wetGain, 0.5);
    expect(WaterfallRecipe.outputTrim, 0.78);
  });
}
