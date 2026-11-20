import 'dart:math' as math;
import 'dart:typed_data';

import 'biquad.dart';
import 'rng.dart';

enum NoiseColor { white, pink, brown }

/// Table length in seconds per colour. The lengths differ so that layers
/// reading different colours never loop in step.
double _seconds(NoiseColor color) => switch (color) {
  NoiseColor.white => 4.37,
  NoiseColor.pink => 5.23,
  NoiseColor.brown => 5.81,
};

/// A seamless stereo loop of coloured noise at the engine rate, with each
/// channel centred and normalised to RMS 0.25.
final class NoiseTable {
  final Float32List _left;
  final Float32List _right;

  /// Generates [color] noise at [sampleRate]; the channels use the seeds
  /// `Rng.mix(seed, 1)` and `Rng.mix(seed, 2)`.
  NoiseTable.generate(NoiseColor color, int sampleRate, int seed)
    : this._(
        _channel(color, sampleRate, Rng.mix(seed, 1)),
        _channel(color, sampleRate, Rng.mix(seed, 2)),
      );

  /// Wraps [left] and [right] without copying. They must have equal lengths
  /// of at least one frame.
  NoiseTable.fromChannels(Float32List left, Float32List right)
    : this._(left, right);

  NoiseTable._(this._left, this._right) {
    if (_left.isEmpty || _left.length != _right.length) {
      throw ArgumentError(
        'channels must have equal lengths >= 1 '
        '(got ${_left.length} and ${_right.length})',
      );
    }
  }

  int get length => _left.length;
  Float32List get left => _left;
  Float32List get right => _right;

  /// Writes `table × gain` into the first [frames] samples of [outL] and
  /// [outR], starting at table position [pos] (`0 <= pos < length`). Returns
  /// the wrapped next position.
  int read(
    Float32List outL,
    Float32List outR,
    int pos,
    int frames,
    double gain,
  ) {
    final l = _left, r = _right, n = l.length;
    for (var i = 0; i < frames; i++) {
      outL[i] = l[pos] * gain;
      outR[i] = r[pos] * gain;
      if (++pos == n) pos = 0;
    }
    return pos;
  }

  /// Like [read], but adds into [outL] and [outR].
  int mix(
    Float32List outL,
    Float32List outR,
    int pos,
    int frames,
    double gain,
  ) {
    final l = _left, r = _right, n = l.length;
    for (var i = 0; i < frames; i++) {
      outL[i] += l[pos] * gain;
      outR[i] += r[pos] * gain;
      if (++pos == n) pos = 0;
    }
    return pos;
  }

  /// Writes `out[start..end)` from [channel] (0 = left, 1 = right), starting
  /// at table position [pos]. Returns the wrapped next position.
  int readMono(Float32List out, int channel, int pos, int start, int end) {
    final src = channel == 0 ? _left : _right;
    final n = src.length;
    for (var i = start; i < end; i++) {
      out[i] = src[pos];
      if (++pos == n) pos = 0;
    }
    return pos;
  }

  static Float32List _channel(NoiseColor color, int rate, int seed) {
    final n = (_seconds(color) * rate).round();
    final warm = rate;
    final x = (0.1 * rate).round();
    final work = Float32List(warm + n + x);
    final rng = Rng(seed);
    const scale = 2.0 / 4294967296.0;

    switch (color) {
      case NoiseColor.white:
        for (var i = 0; i < work.length; i++) {
          work[i] = rng.nextU32() * scale - 1.0;
        }
      case NoiseColor.pink:
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0;
        var b6 = 0.0;
        for (var i = 0; i < work.length; i++) {
          final w = rng.nextU32() * scale - 1.0;
          b0 = 0.99886 * b0 + w * 0.0555179;
          b1 = 0.99332 * b1 + w * 0.0750759;
          b2 = 0.96900 * b2 + w * 0.1538520;
          b3 = 0.86650 * b3 + w * 0.3104856;
          b4 = 0.55000 * b4 + w * 0.5329522;
          b5 = -0.7616 * b5 - w * 0.0168980;
          work[i] = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
          b6 = w * 0.115926;
        }
      case NoiseColor.brown:
        final a = 0.02 * 44100 / rate;
        var last = 0.0;
        for (var i = 0; i < work.length; i++) {
          final w = rng.nextU32() * scale - 1.0;
          last = (last + a * w) / (1 + a);
          work[i] = last;
        }
    }

    if (color != NoiseColor.white) {
      (Biquad()
            ..prepare(rate)
            ..set(BiquadType.highPass, 20, 0.7071))
          .processMono(work, 0, work.length);
    }

    final out = Float32List(n)..setRange(0, n, work, warm);
    // Crossfade the head with the continuation past the end, so the frame
    // after the last one flows into the first.
    for (var i = 0; i < x; i++) {
      final t = (i + 0.5) / x;
      out[i] =
          out[i] * math.sin(t * math.pi / 2) +
          work[warm + n + i] * math.cos(t * math.pi / 2);
    }

    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += out[i];
    }
    final mean = sum / n;
    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      final v = out[i] - mean;
      energy += v * v;
    }
    final gain = 0.25 / math.sqrt(energy / n);
    for (var i = 0; i < n; i++) {
      out[i] = (out[i] - mean) * gain;
    }
    return out;
  }
}

/// The three shared noise tables a soundscape reads from.
final class NoiseBank {
  final NoiseTable white;
  final NoiseTable pink;
  final NoiseTable brown;

  /// Builds the tables at [sampleRate] with seeds `Rng.mix(seed, 11)`, `12`
  /// and `13`.
  NoiseBank(int sampleRate, int seed)
    : white = NoiseTable.generate(
        NoiseColor.white,
        sampleRate,
        Rng.mix(seed, 11),
      ),
      pink = NoiseTable.generate(
        NoiseColor.pink,
        sampleRate,
        Rng.mix(seed, 12),
      ),
      brown = NoiseTable.generate(
        NoiseColor.brown,
        sampleRate,
        Rng.mix(seed, 13),
      );
}
