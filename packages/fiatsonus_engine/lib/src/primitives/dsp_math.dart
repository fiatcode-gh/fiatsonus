import 'dart:math' as math;

/// Magnitude below which a recursive state is flushed to exactly zero (S9).
const double kDenormalFloor = 1e-20;

/// Clamps [x] to [lo]..[hi] without boxing. NaN maps to [lo].
@pragma('vm:prefer-inline')
double clampD(double x, double lo, double hi) =>
    x >= lo ? (x <= hi ? x : hi) : lo;

/// Returns 0.0 when [x] is closer to zero than [kDenormalFloor], else [x].
@pragma('vm:prefer-inline')
double flushDenormal(double x) => x.abs() < kDenormalFloor ? 0.0 : x;

/// [base] raised to [exponent], with [base] clamped to `>= 0` so the result is
/// never NaN from a negative base.
@pragma('vm:prefer-inline')
double powD(double base, double exponent) =>
    math.pow(base > 0 ? base : 0.0, exponent).toDouble();

/// Linear gain for a level in decibels.
double dbToGain(double db) => powD(10.0, db / 20.0);
