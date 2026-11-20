import '../../core/param_spec.dart';
import '../../primitives/dsp_math.dart';

/// Every number of the waterfall recipe (PLAN 4.5) and its param mappings.
/// The design doc's waterfall tables state the same values; change both
/// together.
abstract final class WaterfallRecipe {
  /// The user controls, in index order.
  static const List<ParamSpec> params = [
    ParamSpec('height', 'Height', 0.5),
    ParamSpec('spray', 'Spray', 0.4),
    ParamSpec('width', 'Width', 0.7),
    ParamSpec('distance', 'Distance', 0.4),
  ];

  static const int heightIndex = 0;
  static const int sprayIndex = 1;
  static const int widthIndex = 2;
  static const int distanceIndex = 3;

  // Tunable constants: changed only by the listening loop (PLAN section 8).
  static const double roarGain = 1.0;
  static const double bodyGain = 1.0;
  static const double sprayGain = 1.0;
  static const double textureGain = 1.4;
  static const double textureDistanceDb = -12.0;
  static const double wetGain = 0.5;
  static const double outputTrim = 0.78;

  // Structural constants.
  static const double pinkMix = 0.7;
  static const double whiteMix = 0.3;
  static const double roarHighPassHz = 80;
  static const double sprayHighPassHz = 4000;
  static const double bedQ = 0.7071;

  static const double roarWalkMinHz = 0.02;
  static const double roarWalkMaxHz = 0.05;
  static const double roarWalkDepth = 0.04;
  static const double sprayWalkMinHz = 0.1;
  static const double sprayWalkMaxHz = 0.4;
  static const double sprayWalkDepth = 0.15;

  /// Grain band-pass centre: `grainBaseHz × grainSpanFactor^r`, r in 0..1.
  static const double grainBaseHz = 800;
  static const double grainSpanFactor = 5;
  static const double grainMinQ = 0.7;
  static const double grainMaxQ = 1.2;
  static const double grainMinSeconds = 0.005;
  static const double grainMaxSeconds = 0.030;
  static const double grainMinAttack = 0.0015;
  static const double grainMaxAttack = 0.002;

  /// The attack never takes more than this share of a grain's length.
  static const double grainAttackMaxShare = 1 / 3;
  static const double grainMinLevel = 0.6;
  static const double grainMaxLevel = 1.0;

  /// Grains pan uniformly in `-grainPan..grainPan`.
  static const double grainPan = 0.9;

  static const double _roarLowPassBaseHz = 6000;
  static const double _roarLowPassSpanHz = 4000;
  static const double _bodyLowPassBaseHz = 250;
  static const double _bodyLowPassSpanHz = -130;
  static const double _bodyLevelBase = 0.3;
  static const double _bodyLevelSpan = 0.7;
  static const double _textureRateBase = 100;
  static const double _textureRateSpan = 300;
  static const double _distanceLowPassHz = 12000;
  static const double _distanceLowPassRatio = 0.125;
  static const double _reverbSendBase = 0.1;
  static const double _reverbSendSpan = 0.5;
  static const double _distanceLevelDb = -12.0;

  static double _unit(double x) => clampD(x, 0.0, 1.0);

  /// Roar low-pass for height [h].
  static double roarLowPassHz(double h) =>
      _roarLowPassBaseHz + _roarLowPassSpanHz * _unit(h);

  /// Body low-pass for height [h].
  static double bodyLowPassHz(double h) =>
      _bodyLowPassBaseHz + _bodyLowPassSpanHz * _unit(h);

  /// Body gain for height [h].
  static double bodyLevel(double h) =>
      bodyGain * (_bodyLevelBase + _bodyLevelSpan * _unit(h));

  /// Texture grains per second for height [h].
  static double textureRate(double h) =>
      _textureRateBase + _textureRateSpan * _unit(h);

  /// Spray gain before its random walk, for spray [s]; 0 switches it off.
  static double sprayLevel(double s) => sprayGain * _unit(s);

  /// Texture bus gain for distance [d].
  static double textureLevel(double d) =>
      textureGain * dbToGain(textureDistanceDb * _unit(d));

  /// Whole-mix low-pass for distance [d].
  static double distanceLowPassHz(double d) =>
      _distanceLowPassHz * powD(_distanceLowPassRatio, _unit(d));

  /// Reverb send for distance [d].
  static double reverbSend(double d) =>
      _reverbSendBase + _reverbSendSpan * _unit(d);

  /// Output gain for distance [d].
  static double outputGain(double d) =>
      outputTrim * dbToGain(_distanceLevelDb * _unit(d));
}
