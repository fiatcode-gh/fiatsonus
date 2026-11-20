import 'dart:typed_data';

/// Sets the first [frames] samples of [buf] to zero.
void clearBlock(Float32List buf, int frames) {
  buf.fillRange(0, frames, 0.0);
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
  for (var i = 0; i < frames; i++) {
    g += dg;
    dst[i] += src[i] * g;
  }
}
