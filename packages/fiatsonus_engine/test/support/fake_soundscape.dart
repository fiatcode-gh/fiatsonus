import 'dart:typed_data';

import 'package:fiatsonus_engine/src/core/param_spec.dart';
import 'package:fiatsonus_engine/src/core/soundscape.dart';
import 'package:fiatsonus_engine/src/primitives/noise_table.dart';

/// Soundscape test double that adds constants and records every call.
final class FakeSoundscape implements Soundscape {
  FakeSoundscape({
    this.id = 'fake',
    this.left = 0.25,
    this.right = 0.25,
    this.rampPerBlock = 0.0,
  });

  @override
  final String id;

  /// Constants added to each channel on the first render call.
  final double left;
  final double right;

  /// Added to both constants once per render call, so successive blocks
  /// differ.
  final double rampPerBlock;

  int? preparedRate;
  int? preparedSeed;
  NoiseBank? preparedNoise;
  final List<(String, double)> paramCalls = [];
  int resetCount = 0;
  int renderCount = 0;

  /// 0-based render call that writes NaN (or infinity with
  /// [faultWithInfinity]).
  int? faultAtBlock;
  bool faultWithInfinity = false;

  /// Writes the fault sample into the right channel instead of the left.
  bool faultOnRight = false;

  /// 0-based render call that throws a [StateError].
  int? throwAtBlock;

  @override
  List<ParamSpec> get params => const [ParamSpec('level', 'Level', 0.5)];

  @override
  void prepare(int sampleRate, int seed, NoiseBank noise) {
    preparedRate = sampleRate;
    preparedSeed = seed;
    preparedNoise = noise;
  }

  @override
  void setParam(String id, double value) {
    paramCalls.add((id, value));
  }

  @override
  void render(Float32List left, Float32List right, int frames) {
    final block = renderCount++;
    if (block == throwAtBlock) throw StateError('fake failure');
    final l = this.left + rampPerBlock * block;
    final r = this.right + rampPerBlock * block;
    for (var i = 0; i < frames; i++) {
      left[i] += l;
      right[i] += r;
    }
    if (block == faultAtBlock) {
      final fault = faultWithInfinity ? double.infinity : double.nan;
      if (faultOnRight) {
        right[frames ~/ 2] += fault;
      } else {
        left[frames ~/ 2] += fault;
      }
    }
  }

  @override
  void reset() {
    resetCount++;
  }

  @override
  int get activeVoices => 0;
}
