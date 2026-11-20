import 'dart:typed_data';

import '../primitives/noise_table.dart';
import 'param_spec.dart';

/// A procedural sound source rendered by the master. It renders raw audio;
/// fades, gain, summing and limiting belong to the master.
abstract interface class Soundscape {
  String get id;

  List<ParamSpec> get params;

  /// Called once; may allocate.
  void prepare(int sampleRate, int seed, NoiseBank noise);

  /// Stores a target only; clamp 0..1; NaN and unknown id ignored.
  void setParam(String id, double value);

  /// ADDS; 1 <= frames <= kBlockFrames; no allocation; no throw.
  void render(Float32List left, Float32List right, int frames);

  /// S8: zero filter and reverb memory, silence voices; no allocation.
  void reset();

  int get activeVoices;
}
