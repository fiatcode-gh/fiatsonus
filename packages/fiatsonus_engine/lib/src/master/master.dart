import 'dart:typed_data';

import '../core/engine_constants.dart';
import '../core/soundscape.dart';
import '../primitives/block_ops.dart';
import '../primitives/dsp_math.dart';
import '../primitives/noise_table.dart';
import '../primitives/rng.dart';
import '../primitives/smoother.dart';
import 'limiter.dart';

/// One soundscape with its gain and fade state.
final class _Slot {
  final Soundscape scape;
  final Smoother gain;

  /// Smoothed gain reached at the end of the previous block.
  double gainPrev;

  /// Fade position 0..1; the applied fade gain is `u * u`.
  double u = 0.0;

  /// Per-sample step of [u].
  double du = 0.0;

  _Slot(this.scape, this.gain) : gainPrev = gain.value;

  bool get isStopped => u == 0.0 && du <= 0.0;
}

/// Sums soundscapes with fades and gain, guards against non-finite output
/// (S8), limits and converts to interleaved 16-bit stereo (PLAN 4.4).
///
/// Rendering runs in internal 256-frame blocks read through a one-block
/// FIFO, so the output does not depend on how callers chunk [render].
final class Master {
  static const double _maxGain = 4.0;

  final int sampleRate;
  final NoiseBank noise;
  final List<_Slot> _slots = [];
  final Limiter _limiter = Limiter();

  final Float32List _mixL = Float32List(kBlockFrames);
  final Float32List _mixR = Float32List(kBlockFrames);
  final Float32List _scratchL = Float32List(kBlockFrames);
  final Float32List _scratchR = Float32List(kBlockFrames);
  final Int16List _block = Int16List(kBlockFrames * 2);

  /// Next unread frame of [_block]; [kBlockFrames] when the FIFO is empty.
  int _readFrame = kBlockFrames;

  /// Last frame of [_block] holding a non-zero sample; -1 when none.
  int _lastNonZero = -1;

  final int _seed;
  int _faultBlocks = 0;

  /// Throws [ArgumentError] when [sampleRate] is outside 8000..192000.
  Master({required this.sampleRate, required int seed})
    : _seed = seed,
      noise = _checkedBank(sampleRate, seed) {
    _limiter.prepare(sampleRate);
    // Creates block_ops' lazily initialised zero block here, so the first
    // render does not allocate it.
    clearBlock(_mixL, kBlockFrames);
  }

  static NoiseBank _checkedBank(int sampleRate, int seed) {
    if (sampleRate < 8000 || sampleRate > 192000) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'must be within 8000..192000',
      );
    }
    return NoiseBank(sampleRate, Rng.mix(seed, 1));
  }

  /// Prepares [scape] and adds it, stopped, with [gain] (clamped 0..4).
  /// Throws [StateError] when a soundscape with the same id exists.
  void add(Soundscape scape, {double gain = 1.0}) {
    if (_find(scape.id) != null) {
      throw StateError('Duplicate soundscape id: ${scape.id}');
    }
    scape.prepare(sampleRate, Rng.mix(_seed, 100 + _slots.length), noise);
    final smoother = Smoother(clampD(gain, 0.0, _maxGain))
      ..prepare(sampleRate, const Duration(milliseconds: 200));
    _slots.add(_Slot(scape, smoother));
  }

  /// Fades [id] in over [fade] (clamped 5 ms..60 s), continuing from its
  /// current level. Returns false for an unknown id.
  bool start(String id, {Duration fade = const Duration(seconds: 2)}) {
    final slot = _find(id);
    if (slot == null) return false;
    slot.du = 1.0 / (_fadeSeconds(fade) * sampleRate);
    return true;
  }

  /// Fades [id] out over [fade] (clamped 5 ms..60 s), continuing from its
  /// current level. Returns false for an unknown id.
  bool stop(String id, {Duration fade = const Duration(seconds: 3)}) {
    final slot = _find(id);
    if (slot == null) return false;
    if (!slot.isStopped) slot.du = -1.0 / (_fadeSeconds(fade) * sampleRate);
    return true;
  }

  /// Sets the gain of [id], clamped 0..4 and smoothed over 200 ms. NaN is
  /// ignored. Returns false for an unknown id.
  bool setGain(String id, double gain) {
    final slot = _find(id);
    if (slot == null) return false;
    if (!gain.isNaN) slot.gain.target = clampD(gain, 0.0, _maxGain);
    return true;
  }

  /// Forwards [value] unmodified to the soundscape [soundscapeId]. Returns
  /// false for an unknown soundscape id.
  bool setParam(String soundscapeId, String paramId, double value) {
    final slot = _find(soundscapeId);
    if (slot == null) return false;
    slot.scape.setParam(paramId, value);
    return true;
  }

  /// Writes [frames] interleaved stereo frames (L, R, L, R ...) into
  /// [interleaved], which must hold at least `frames * 2` samples.
  void render(Int16List interleaved, int frames) {
    if (frames < 0 || interleaved.length < frames * 2) {
      throw ArgumentError.value(frames, 'frames', 'exceeds the buffer');
    }
    final block = _block;
    var out = 0;
    var remaining = frames;
    while (remaining > 0) {
      if (_readFrame == kBlockFrames) {
        _renderBlock();
        _readFrame = 0;
      }
      var n = kBlockFrames - _readFrame;
      if (n > remaining) n = remaining;
      final end = (_readFrame + n) * 2;
      for (var i = _readFrame * 2; i < end; i++) {
        interleaved[out++] = block[i];
      }
      _readFrame += n;
      remaining -= n;
    }
  }

  /// True when every soundscape is stopped and no unread non-zero output is
  /// buffered, so every later [render] returns zeros until a [start].
  bool get isSilent {
    if (_lastNonZero >= _readFrame) return false;
    for (var i = 0; i < _slots.length; i++) {
      if (!_slots[i].isStopped) return false;
    }
    return true;
  }

  /// Number of blocks muted by the S8 guard.
  int get faultBlocks => _faultBlocks;

  void _renderBlock() {
    const frames = kBlockFrames;
    final mixL = _mixL;
    final mixR = _mixR;
    final scratchL = _scratchL;
    final scratchR = _scratchR;
    clearBlock(mixL, frames);
    clearBlock(mixR, frames);

    var bad = false;
    for (var s = 0; s < _slots.length; s++) {
      final slot = _slots[s];
      if (slot.isStopped) continue;
      clearBlock(scratchL, frames);
      clearBlock(scratchR, frames);
      try {
        slot.scape.render(scratchL, scratchR, frames);
      } on Object {
        bad = true;
        break;
      }
      final g0 = slot.gainPrev;
      final g1 = slot.gain.next();
      slot.gainPrev = g1;
      final dg = (g1 - g0) / frames;
      final du = slot.du;
      var g = g0;
      var u = slot.u;
      for (var i = 0; i < frames; i++) {
        u += du;
        if (u > 1.0) {
          u = 1.0;
        } else if (u < 0.0) {
          u = 0.0;
        }
        g += dg;
        final k = g * (u * u);
        mixL[i] += scratchL[i] * k;
        mixR[i] += scratchR[i] * k;
      }
      slot.u = u;
    }

    if (!bad) {
      var acc = 0.0;
      for (var i = 0; i < frames; i++) {
        acc += mixL[i] * 0.0 + mixR[i] * 0.0;
      }
      bad = acc != 0.0;
    }

    final block = _block;
    if (bad) {
      _fault();
      block.fillRange(0, frames * 2, 0);
      _lastNonZero = -1;
      return;
    }

    _limiter.process(mixL, mixR, frames);
    var lastNonZero = -1;
    for (var i = 0; i < frames; i++) {
      final l = _toInt16(mixL[i]);
      final r = _toInt16(mixR[i]);
      block[i * 2] = l;
      block[i * 2 + 1] = r;
      if (l != 0 || r != 0) lastNonZero = i;
    }
    _lastNonZero = lastNonZero;
  }

  /// S8 recovery: reset every soundscape and the limiter, and restart every
  /// sounding slot with a 2 s fade-in; slots fading out become stopped.
  void _fault() {
    _faultBlocks++;
    _limiter.reset();
    final refade = 1.0 / (2.0 * sampleRate);
    for (var s = 0; s < _slots.length; s++) {
      final slot = _slots[s];
      slot.scape.reset();
      slot.du = slot.du > 0.0 ? refade : 0.0;
      slot.u = 0.0;
    }
  }

  @pragma('vm:prefer-inline')
  static int _toInt16(double x) {
    final v = (x * 32767.0).round();
    return v > 32767 ? 32767 : (v < -32767 ? -32767 : v);
  }

  double _fadeSeconds(Duration fade) =>
      clampD(fade.inMicroseconds / 1e6, 0.005, 60.0);

  _Slot? _find(String id) {
    for (var i = 0; i < _slots.length; i++) {
      if (_slots[i].scape.id == id) return _slots[i];
    }
    return null;
  }
}
