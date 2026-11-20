import 'dart:typed_data';

import '../core/engine_constants.dart';
import 'biquad.dart';
import 'dsp_math.dart';
import 'envelope.dart';
import 'noise_table.dart';
import 'panner.dart';

/// Frames over which a stolen voice fades to zero.
const int _stealFade = 64;

/// One grain: a mono table read through one filter and one envelope, panned
/// into the stereo mix.
final class Voice {
  final Biquad filter = Biquad();
  final Envelope envelope = Envelope();
  NoiseTable? table;
  int channel = 0;
  int position = 0;
  double gainL = 0.0;
  double gainR = 0.0;
  int start = 0;
  bool spawnedThisBlock = false;
  bool active = false;

  /// Reads, filters and envelopes `scratch[from..to)`.
  void _shape(NoiseTable source, Float32List scratch, int from, int to) {
    position = source.readMono(scratch, channel, position, from, to);
    filter.processMono(scratch, from, to);
    envelope.process(scratch, from, to);
  }
}

/// Fixed set of grain voices with quietest-voice stealing. Every voice stops
/// on a zero (S7): its envelope ends at 0, and a stolen voice fades to 0 first.
final class VoicePool {
  final List<Voice> _voices;
  final Float32List _scratch = Float32List(kBlockFrames);
  final Float32List _accL = Float32List(kBlockFrames);
  final Float32List _accR = Float32List(kBlockFrames);
  bool _accUsed = false;
  int _active = 0;
  int _stolen = 0;

  /// [capacity] must be 1..[kMaxVoices], else [ArgumentError].
  VoicePool({int capacity = kMaxVoices})
    : _voices = capacity >= 1 && capacity <= kMaxVoices
          ? List<Voice>.generate(capacity, (_) => Voice(), growable: false)
          : throw ArgumentError.value(
              capacity,
              'capacity',
              'must be 1..$kMaxVoices',
            );

  void prepare(int sampleRate) {
    for (var i = 0; i < _voices.length; i++) {
      final v = _voices[i];
      v.filter.prepare(sampleRate);
      v.envelope.prepare(sampleRate);
    }
    reset();
  }

  int get capacity => _voices.length;

  /// Voices that are scheduled or sounding.
  int get activeCount => _active;

  /// Voices stolen since construction.
  int get stolenCount => _stolen;

  /// Schedules a grain [offset] frames into the next [render].
  void spawn(
    NoiseTable table,
    int channel,
    int tablePos,
    BiquadType filterType,
    double freqHz,
    double q,
    double attackSeconds,
    double decaySeconds,
    double level,
    double pan,
    int offset,
  ) {
    final ch = channel & 1;
    final pos = tablePos % table.length;
    final attack = clampD(attackSeconds, 0.0005, 1.0);
    final decay = clampD(decaySeconds, 0.001, 10.0);
    final lvl = clampD(level, 0.0, 4.0);
    var start = offset < 0
        ? 0
        : (offset > kBlockFrames - 1 ? kBlockFrames - 1 : offset);

    Voice? voice;
    final voices = _voices;
    for (var i = 0; i < voices.length; i++) {
      if (!voices[i].active) {
        voice = voices[i];
        break;
      }
    }
    if (voice == null) {
      for (var i = 0; i < voices.length; i++) {
        final v = voices[i];
        if (v.spawnedThisBlock) continue;
        if (voice == null || v.envelope.value < voice.envelope.value) {
          voice = v;
        }
      }
      if (voice == null) return;
      start = start > _stealFade ? start : _stealFade;
      _fadeOut(voice, start);
      _stolen++;
    } else {
      _active++;
    }

    voice
      ..table = table
      ..channel = ch
      ..position = pos
      ..gainL = Panner.left(pan)
      ..gainR = Panner.right(pan)
      ..start = start
      ..spawnedThisBlock = true
      ..active = true;
    voice.filter
      ..reset()
      ..set(filterType, freqHz, q);
    voice.envelope
      ..begin(0.0)
      ..lineTo(lvl, attack)
      ..expTo(lvl * Envelope.floor, decay);
  }

  /// Renders the stolen [voice] for frames `0..k` into the accumulators,
  /// fading the last [_stealFade] of them from 1 to 0 on frame `k - 1`.
  void _fadeOut(Voice voice, int k) {
    final source = voice.table;
    final remaining = voice.envelope.remainingFrames;
    final end = k < remaining ? k : remaining;
    if (source != null && end > 0) {
      final scratch = _scratch;
      voice._shape(source, scratch, 0, end);
      final accL = _accL, accR = _accR;
      final gl = voice.gainL, gr = voice.gainR;
      final fadeStart = k - _stealFade;
      for (var i = 0; i < end; i++) {
        final f = i < fadeStart ? 1.0 : (k - 1 - i) / (_stealFade - 1);
        final s = scratch[i] * f;
        accL[i] += s * gl;
        accR[i] += s * gr;
      }
    }
    _accUsed = true;
  }

  /// Adds every active voice into the first [frames] samples of [left] and
  /// [right].
  void render(Float32List left, Float32List right, int frames) {
    final scratch = _scratch;
    final voices = _voices;
    var active = 0;
    for (var n = 0; n < voices.length; n++) {
      final v = voices[n];
      if (!v.active) continue;
      final source = v.table;
      final from = v.start;
      final remaining = v.envelope.remainingFrames;
      final to = from + remaining < frames ? from + remaining : frames;
      if (source != null && from < to) {
        v._shape(source, scratch, from, to);
        final gl = v.gainL, gr = v.gainR;
        for (var i = from; i < to; i++) {
          final s = scratch[i];
          left[i] += s * gl;
          right[i] += s * gr;
        }
      }
      v.start = 0;
      v.spawnedThisBlock = false;
      if (v.envelope.isDone) {
        v.active = false;
        v.table = null;
      } else {
        active++;
      }
    }
    if (_accUsed) {
      final accL = _accL, accR = _accR;
      for (var i = 0; i < frames; i++) {
        left[i] += accL[i];
        right[i] += accR[i];
      }
      accL.fillRange(0, kBlockFrames, 0.0);
      accR.fillRange(0, kBlockFrames, 0.0);
      _accUsed = false;
    }
    _active = active;
  }

  /// Silences every voice and clears the accumulators.
  void reset() {
    for (var i = 0; i < _voices.length; i++) {
      final v = _voices[i]
        ..active = false
        ..spawnedThisBlock = false
        ..start = 0
        ..table = null;
      v.envelope.reset();
      v.filter.reset();
    }
    _scratch.fillRange(0, kBlockFrames, 0.0);
    _accL.fillRange(0, kBlockFrames, 0.0);
    _accR.fillRange(0, kBlockFrames, 0.0);
    _accUsed = false;
    _active = 0;
  }
}
