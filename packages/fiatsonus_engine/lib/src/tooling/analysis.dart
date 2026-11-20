import 'dart:math' as math;
import 'dart:typed_data';

/// One K-weighting biquad stage (transposed direct form II, double state).
final class _Stage {
  final double b0, b1, b2, a1, a2;
  double z1 = 0.0, z2 = 0.0;

  _Stage(this.b0, this.b1, this.b2, this.a1, this.a2);

  /// BS.1770 stage 1: the high shelf.
  factory _Stage.shelf(int rate) {
    const f0 = 1681.974450955533;
    const g = 3.999843853973347;
    const q = 0.7071752369554196;
    final k = math.tan(math.pi * f0 / rate);
    final vh = math.pow(10.0, g / 20.0).toDouble();
    final vb = math.pow(vh, 0.4996667741545416).toDouble();
    final a0 = 1.0 + k / q + k * k;
    return _Stage(
      (vh + vb * k / q + k * k) / a0,
      2.0 * (k * k - vh) / a0,
      (vh - vb * k / q + k * k) / a0,
      2.0 * (k * k - 1.0) / a0,
      (1.0 - k / q + k * k) / a0,
    );
  }

  /// BS.1770 stage 2: the high-pass.
  factory _Stage.highPass(int rate) {
    const f0 = 38.13547087602444;
    const q = 0.5003270373238773;
    final k = math.tan(math.pi * f0 / rate);
    final a0 = 1.0 + k / q + k * k;
    return _Stage(
      1.0,
      -2.0,
      1.0,
      2.0 * (k * k - 1.0) / a0,
      (1.0 - k / q + k * k) / a0,
    );
  }

  double process(double x) {
    final y = b0 * x + z1;
    z1 = b1 * x - a1 * y + z2;
    z2 = b2 * x - a2 * y;
    return y;
  }

  void reset() {
    z1 = 0.0;
    z2 = 0.0;
  }
}

/// Ungated BS.1770 K-weighted loudness of 16-bit stereo audio.
final class LoudnessMeter {
  final _Stage _shelfL, _shelfR, _highPassL, _highPassR;
  double _sum = 0.0;
  int _frames = 0;

  LoudnessMeter(int sampleRate)
    : _shelfL = _Stage.shelf(sampleRate),
      _shelfR = _Stage.shelf(sampleRate),
      _highPassL = _Stage.highPass(sampleRate),
      _highPassR = _Stage.highPass(sampleRate);

  /// Adds [frames] interleaved stereo frames. Allocates nothing.
  void add(Int16List interleaved, int frames) {
    const scale = 1.0 / 32768.0;
    var sum = 0.0;
    for (var i = 0; i < frames; i++) {
      final l = _highPassL.process(_shelfL.process(interleaved[2 * i] * scale));
      final r = _highPassR.process(
        _shelfR.process(interleaved[2 * i + 1] * scale),
      );
      sum += l * l + r * r;
    }
    _sum += sum;
    _frames += frames;
  }

  /// Loudness in LUFS of everything added since construction or [reset];
  /// negative infinity for silence or no input.
  double get lufs {
    if (_frames == 0 || _sum == 0.0) return double.negativeInfinity;
    return -0.691 + 10.0 * math.log(_sum / _frames) / math.ln10;
  }

  /// Forgets all input and the filter state.
  void reset() {
    _sum = 0.0;
    _frames = 0;
    _shelfL.reset();
    _shelfR.reset();
    _highPassL.reset();
    _highPassR.reset();
  }
}

/// Largest absolute sample over [frames] stereo frames (-32768 reads 32768).
int peakAbs(Int16List interleaved, int frames) {
  var peak = 0;
  for (var i = 0; i < frames * 2; i++) {
    final a = interleaved[i].abs();
    if (a > peak) peak = a;
  }
  return peak;
}

/// Mean of [channel] (0 left, 1 right) over [frames] frames, divided by
/// 32768.
double dcOffset(Int16List interleaved, int frames, int channel) {
  var sum = 0.0;
  for (var i = 0; i < frames; i++) {
    sum += interleaved[2 * i + channel];
  }
  return sum / frames / 32768.0;
}

/// Click metric: the largest sample-to-sample jump of either channel divided
/// by the RMS of that channel's previous [window] jumps (floored at
/// [floorLsb]), evaluated once the window is full. Zero when no jump was
/// evaluated.
double maxJumpZ(
  Int16List interleaved,
  int frames, {
  int window = 2048,
  double floorLsb = 8.0,
}) {
  final ring = Float64List(window);
  var best = 0.0;
  for (var channel = 0; channel < 2; channel++) {
    var ringSum = 0.0;
    var count = 0;
    var at = 0;
    for (var n = 1; n < frames; n++) {
      final d =
          (interleaved[2 * n + channel] - interleaved[2 * (n - 1) + channel])
              .toDouble();
      if (count == window) {
        final rms = math.sqrt(math.max(ringSum, 0.0) / window);
        final z = d.abs() / math.max(rms, floorLsb);
        if (z > best) best = z;
        ringSum -= ring[at];
      } else {
        count++;
      }
      final sq = d * d;
      ring[at] = sq;
      ringSum += sq;
      at = at + 1 == window ? 0 : at + 1;
    }
  }
  return best;
}
