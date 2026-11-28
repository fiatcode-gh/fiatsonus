import 'dart:typed_data';

import '../core/engine_constants.dart';

/// Positive zeros, the source of every [clearBlock]; never written.
final Float32List _zeros = Float32List(kBlockFrames);

/// Sets the first [frames] samples of [buf] to zero; `frames <= kBlockFrames`.
void clearBlock(Float32List buf, int frames) {
  buf.setRange(0, frames, _zeros);
}

/// Adds `src[i] * g` into `dst[i]` for the first [frames] samples, with `g`
/// moving linearly from [g0] and reaching [g1] on the last frame.
void addRamp(
  Float32List src,
  Float32List dst,
  int frames,
  double g0,
  double g1,
) {
  final dg = (g1 - g0) / frames;
  var g = g0;
  var i = 0;
  // Four frames per iteration, in frame order: one interrupt check and one
  // loop test per four frames. The remainder runs in the loop below.
  for (; i <= frames - 4; i += 4) {
    g += dg;
    dst[i] += src[i] * g;
    g += dg;
    dst[i + 1] += src[i + 1] * g;
    g += dg;
    dst[i + 2] += src[i + 2] * g;
    g += dg;
    dst[i + 3] += src[i + 3] * g;
  }
  for (; i < frames; i++) {
    g += dg;
    dst[i] += src[i] * g;
  }
}
