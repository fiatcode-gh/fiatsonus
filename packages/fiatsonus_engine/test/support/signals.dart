import 'dart:math' as math;
import 'dart:typed_data';

/// A sine of [hz] at [rate], [frames] long, with peak [amplitude].
Float32List sine(double hz, int rate, int frames, {double amplitude = 0.5}) {
  final out = Float32List(frames);
  final w = 2 * math.pi * hz / rate;
  for (var i = 0; i < frames; i++) {
    out[i] = amplitude * math.sin(w * i);
  }
  return out;
}

/// Root mean square of [buf] from [start] to the end.
double rms(Float32List buf, [int start = 0]) {
  var sum = 0.0;
  for (var i = start; i < buf.length; i++) {
    sum += buf[i] * buf[i];
  }
  return math.sqrt(sum / (buf.length - start));
}

/// Ratio of [a] to [b] in decibels.
double ratioDb(double a, double b) => 20 * math.log(a / b) / math.ln10;
