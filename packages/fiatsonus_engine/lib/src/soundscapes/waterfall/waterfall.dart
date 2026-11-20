import 'dart:typed_data';

import '../../core/engine_constants.dart';
import '../../core/param_set.dart';
import '../../core/param_spec.dart';
import '../../core/soundscape.dart';
import '../../primitives/biquad.dart';
import '../../primitives/block_ops.dart';
import '../../primitives/dsp_math.dart';
import '../../primitives/grain_cloud.dart';
import '../../primitives/modulator.dart';
import '../../primitives/noise_table.dart';
import '../../primitives/reverb.dart';
import '../../primitives/rng.dart';
import '../../primitives/voice_pool.dart';
import 'waterfall_recipe.dart';

/// The four sound layers of the waterfall.
enum WaterfallLayer { roar, body, spray, texture }

/// A thick steady roar with a deep body, fine spray and a dense grain
/// texture, behind one distance low-pass and one reverb. Every recipe number
/// lives in [WaterfallRecipe].
final class Waterfall implements Soundscape {
  static final NoiseTable _placeholder = NoiseTable.fromChannels(
    Float32List(1),
    Float32List(1),
  );

  final bool _roarOn;
  final bool _bodyOn;
  final bool _sprayOn;
  final bool _textureOn;

  final ParamSet _params = ParamSet(WaterfallRecipe.params);
  final List<int> _blocks = List<int>.filled(WaterfallLayer.values.length, 0);

  NoiseTable _white = _placeholder;
  NoiseTable _pink = _placeholder;
  NoiseTable _brown = _placeholder;
  int _roarPinkPos = 0;
  int _roarWhitePos = 0;
  int _bodyPos = 0;
  int _sprayPos = 0;

  Rng _textureRng = Rng(0);
  Modulator _roarMod = Modulator(Rng(0), minHz: 1, maxHz: 1);
  Modulator _sprayMod = Modulator(Rng(0), minHz: 1, maxHz: 1);
  GrainCloud _cloud = GrainCloud(Rng(0));
  final VoicePool _pool = VoicePool();
  final Reverb _reverb = Reverb();

  final Biquad _roarHp = Biquad();
  final Biquad _roarLp = Biquad();
  final Biquad _bodyLp = Biquad();
  final Biquad _sprayHp = Biquad();
  final Biquad _distanceLp = Biquad();

  final Float32List _tempL = Float32List(kBlockFrames);
  final Float32List _tempR = Float32List(kBlockFrames);
  final Float32List _busL = Float32List(kBlockFrames);
  final Float32List _busR = Float32List(kBlockFrames);
  final Float32List _texL = Float32List(kBlockFrames);
  final Float32List _texR = Float32List(kBlockFrames);
  final Float32List _wetL = Float32List(kBlockFrames);
  final Float32List _wetR = Float32List(kBlockFrames);

  bool _first = true;
  double _h = 0.0;
  double _d = 0.0;

  // Height-derived values.
  double _bodyLevel = 0.0;
  double _textureRate = 0.0;

  // Distance-derived values.
  double _textureLevel = 0.0;
  double _send = 0.0;
  double _outputGain = 0.0;

  // Values reached at the end of the previous block.
  double _roarGain = 0.0;
  double _bodyGain = 0.0;
  double _sprayGain = 0.0;
  double _textureGain = 0.0;
  double _prevSend = 0.0;
  double _prevOutputGain = 0.0;
  double _width = 0.0;

  /// [solo] null renders every layer; a set renders only those layers.
  Waterfall({Set<WaterfallLayer>? solo})
    : _roarOn = solo == null || solo.contains(WaterfallLayer.roar),
      _bodyOn = solo == null || solo.contains(WaterfallLayer.body),
      _sprayOn = solo == null || solo.contains(WaterfallLayer.spray),
      _textureOn = solo == null || solo.contains(WaterfallLayer.texture);

  @override
  String get id => 'waterfall';

  @override
  List<ParamSpec> get params => _params.specs;

  /// Sum of the coefficient recomputations of the five bed and bus filters.
  int get coefficientUpdates =>
      _roarHp.updateCount +
      _roarLp.updateCount +
      _bodyLp.updateCount +
      _sprayHp.updateCount +
      _distanceLp.updateCount;

  /// Blocks in which [layer] was processed.
  int blocksRendered(WaterfallLayer layer) => _blocks[layer.index];

  @override
  int get activeVoices => _pool.activeCount;

  /// True when every filter state and the reverb memory are exactly 0.0 and
  /// no voice is active. Scans the reverb memory: diagnostics only, never
  /// called from render.
  bool get isQuiet =>
      _roarHp.isQuiet &&
      _roarLp.isQuiet &&
      _bodyLp.isQuiet &&
      _sprayHp.isQuiet &&
      _distanceLp.isQuiet &&
      _reverb.isQuiet &&
      _pool.activeCount == 0;

  @override
  void prepare(int sampleRate, int seed, NoiseBank noise) {
    _params.prepare(sampleRate);
    _white = noise.white;
    _pink = noise.pink;
    _brown = noise.brown;

    final roarRng = Rng(Rng.mix(seed, 1));
    final bodyRng = Rng(Rng.mix(seed, 2));
    final sprayRng = Rng(Rng.mix(seed, 3));
    _textureRng = Rng(Rng.mix(seed, 4));
    _roarPinkPos = roarRng.nextU32() % _pink.length;
    _roarWhitePos = roarRng.nextU32() % _white.length;
    _bodyPos = bodyRng.nextU32() % _brown.length;
    _sprayPos = sprayRng.nextU32() % _white.length;

    _roarMod = Modulator(
      roarRng,
      minHz: WaterfallRecipe.roarWalkMinHz,
      maxHz: WaterfallRecipe.roarWalkMaxHz,
    )..prepare(sampleRate);
    _sprayMod = Modulator(
      sprayRng,
      minHz: WaterfallRecipe.sprayWalkMinHz,
      maxHz: WaterfallRecipe.sprayWalkMaxHz,
    )..prepare(sampleRate);
    _cloud = GrainCloud(_textureRng)..prepare(sampleRate);

    _roarHp.prepare(sampleRate);
    _roarLp.prepare(sampleRate);
    _bodyLp.prepare(sampleRate);
    _sprayHp.prepare(sampleRate);
    _distanceLp.prepare(sampleRate);
    _roarHp.set(
      BiquadType.highPass,
      WaterfallRecipe.roarHighPassHz,
      WaterfallRecipe.bedQ,
    );
    _sprayHp.set(
      BiquadType.highPass,
      WaterfallRecipe.sprayHighPassHz,
      WaterfallRecipe.bedQ,
    );
    _reverb.prepare(sampleRate);
    _pool.prepare(sampleRate);
    _first = true;
  }

  @override
  void setParam(String id, double value) => _params.set(id, value);

  @override
  void render(Float32List left, Float32List right, int frames) {
    _params.advance();
    final h = _params.value(WaterfallRecipe.heightIndex);
    final s = _params.value(WaterfallRecipe.sprayIndex);
    final w = _params.value(WaterfallRecipe.widthIndex);
    final d = _params.value(WaterfallRecipe.distanceIndex);
    final first = _first;

    if (first || h != _h) {
      _h = h;
      _bodyLevel = WaterfallRecipe.bodyLevel(h);
      _textureRate = WaterfallRecipe.textureRate(h);
      _roarLp.set(
        BiquadType.lowPass,
        WaterfallRecipe.roarLowPassHz(h),
        WaterfallRecipe.bedQ,
      );
      _bodyLp.set(
        BiquadType.lowPass,
        WaterfallRecipe.bodyLowPassHz(h),
        WaterfallRecipe.bedQ,
      );
    }
    if (first || d != _d) {
      _d = d;
      _textureLevel = WaterfallRecipe.textureLevel(d);
      _send = WaterfallRecipe.reverbSend(d);
      _outputGain = WaterfallRecipe.outputGain(d);
      _distanceLp.set(
        BiquadType.lowPass,
        WaterfallRecipe.distanceLowPassHz(d),
        WaterfallRecipe.bedQ,
      );
    }

    var roarGain = 0.0;
    if (_roarOn) {
      _roarMod.next();
      roarGain = _roarMod.modulate(
        WaterfallRecipe.roarGain,
        WaterfallRecipe.roarWalkDepth,
      );
    }
    final bodyGain = _bodyOn ? _bodyLevel : 0.0;
    final sprayLevel = _sprayOn ? WaterfallRecipe.sprayLevel(s) : 0.0;
    final sprayActive = _sprayOn && !(sprayLevel == 0.0 && _sprayGain == 0.0);
    var sprayGain = 0.0;
    if (sprayActive) {
      _sprayMod.next();
      sprayGain = _sprayMod.modulate(
        sprayLevel,
        WaterfallRecipe.sprayWalkDepth,
      );
    }
    final textureGain = _textureOn ? _textureLevel : 0.0;

    if (first) {
      _roarGain = roarGain;
      _bodyGain = bodyGain;
      _sprayGain = sprayGain;
      _textureGain = textureGain;
      _prevSend = _send;
      _prevOutputGain = _outputGain;
      _width = w;
      _first = false;
    }

    final busL = _busL;
    final busR = _busR;
    final tempL = _tempL;
    final tempR = _tempR;
    clearBlock(busL, frames);
    clearBlock(busR, frames);

    if (!(roarGain == 0.0 && _roarGain == 0.0)) {
      _roarPinkPos = _pink.read(
        tempL,
        tempR,
        _roarPinkPos,
        frames,
        WaterfallRecipe.pinkMix,
      );
      _roarWhitePos = _white.mix(
        tempL,
        tempR,
        _roarWhitePos,
        frames,
        WaterfallRecipe.whiteMix,
      );
      _roarHp.processStereo(tempL, tempR, frames);
      _roarLp.processStereo(tempL, tempR, frames);
      addRamp(tempL, busL, frames, _roarGain, roarGain);
      addRamp(tempR, busR, frames, _roarGain, roarGain);
      _blocks[WaterfallLayer.roar.index]++;
    }
    if (!(bodyGain == 0.0 && _bodyGain == 0.0)) {
      _bodyPos = _brown.read(tempL, tempR, _bodyPos, frames, 1.0);
      _bodyLp.processStereo(tempL, tempR, frames);
      addRamp(tempL, busL, frames, _bodyGain, bodyGain);
      addRamp(tempR, busR, frames, _bodyGain, bodyGain);
      _blocks[WaterfallLayer.body.index]++;
    }
    if (sprayActive) {
      _sprayPos = _white.read(tempL, tempR, _sprayPos, frames, 1.0);
      _sprayHp.processStereo(tempL, tempR, frames);
      addRamp(tempL, busL, frames, _sprayGain, sprayGain);
      addRamp(tempR, busR, frames, _sprayGain, sprayGain);
      _blocks[WaterfallLayer.spray.index]++;
    }
    if (!(textureGain == 0.0 && _textureGain == 0.0)) {
      _renderTexture(frames);
      addRamp(_texL, busL, frames, _textureGain, textureGain);
      addRamp(_texR, busR, frames, _textureGain, textureGain);
      _blocks[WaterfallLayer.texture.index]++;
    }

    _distanceLp.processStereo(busL, busR, frames);

    final wetL = _wetL;
    final wetR = _wetR;
    clearBlock(wetL, frames);
    clearBlock(wetR, frames);
    _reverb.process(
      busL,
      busR,
      wetL,
      wetR,
      frames,
      _prevSend,
      _send,
      WaterfallRecipe.wetGain,
    );
    for (var i = 0; i < frames; i++) {
      busL[i] += wetL[i];
      busR[i] += wetR[i];
    }

    final dg = (_outputGain - _prevOutputGain) / frames;
    final dw = (w - _width) / frames;
    var gain = _prevOutputGain;
    var width = _width;
    for (var i = 0; i < frames; i++) {
      gain += dg;
      width += dw;
      final l = busL[i];
      final r = busR[i];
      final m = (l + r) * 0.5;
      final sd = (l - r) * 0.5 * width;
      left[i] += (m + sd) * gain;
      right[i] += (m - sd) * gain;
    }

    _roarGain = roarGain;
    _bodyGain = bodyGain;
    _sprayGain = sprayGain;
    _textureGain = textureGain;
    _prevSend = _send;
    _prevOutputGain = _outputGain;
    _width = w;
  }

  /// Schedules this block's grains and renders the voice pool into the
  /// texture pair.
  void _renderTexture(int frames) {
    final rng = _textureRng;
    final white = _white;
    _cloud.rate = _textureRate;
    for (
      var offset = _cloud.nextStart(frames);
      offset >= 0;
      offset = _cloud.nextStart(frames)
    ) {
      final r = rng.nextDouble();
      final q = rng.range(WaterfallRecipe.grainMinQ, WaterfallRecipe.grainMaxQ);
      final length = rng.range(
        WaterfallRecipe.grainMinSeconds,
        WaterfallRecipe.grainMaxSeconds,
      );
      final drawnAttack = rng.range(
        WaterfallRecipe.grainMinAttack,
        WaterfallRecipe.grainMaxAttack,
      );
      final level = rng.range(
        WaterfallRecipe.grainMinLevel,
        WaterfallRecipe.grainMaxLevel,
      );
      final pan = rng.range(
        -WaterfallRecipe.grainPan,
        WaterfallRecipe.grainPan,
      );
      final channel = rng.nextU32() & 1;
      final position = rng.nextU32() % white.length;
      final cap = length * WaterfallRecipe.grainAttackMaxShare;
      final attack = drawnAttack < cap ? drawnAttack : cap;
      _pool.spawn(
        white,
        channel,
        position,
        BiquadType.bandPass,
        WaterfallRecipe.grainBaseHz * powD(WaterfallRecipe.grainSpanFactor, r),
        q,
        attack,
        length - attack,
        level,
        pan,
        offset,
      );
    }
    clearBlock(_texL, frames);
    clearBlock(_texR, frames);
    _pool.render(_texL, _texR, frames);
  }

  @override
  void reset() {
    _roarHp.reset();
    _roarLp.reset();
    _bodyLp.reset();
    _sprayHp.reset();
    _distanceLp.reset();
    _reverb.reset();
    _pool.reset();
  }
}
