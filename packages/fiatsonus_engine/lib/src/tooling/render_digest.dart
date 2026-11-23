import 'dart:math' as math;
import 'dart:typed_data';

import '../core/engine_constants.dart';
import '../master/master.dart';
import '../primitives/biquad.dart';
import '../primitives/noise_table.dart';
import '../primitives/rng.dart';
import '../primitives/voice_pool.dart';
import '../soundscapes/registry.dart';

/// The scripted renders a digest case can run (PLAN 5.1).
enum DigestScript { session, long, poolSteal }

/// One render whose output is hashed: a script at a rate, seed and param set.
final class DigestCase {
  const DigestCase(this.script, this.sampleRate, this.seed, this.paramSet);

  final DigestScript script;
  final int sampleRate;
  final int seed;

  /// Key of [digestParamSets].
  final String paramSet;

  /// `<script>-r<rate>-s<seed>-<paramSet>`.
  String get name => '${script.name}-r$sampleRate-s$seed-$paramSet';
}

/// Param values set at the start of a `session` render.
const Map<String, Map<String, double>> digestParamSets = {
  'default': {},
  'low': {'height': 0, 'spray': 0, 'width': 0, 'distance': 0},
  'high': {'height': 1, 'spray': 1, 'width': 1, 'distance': 1},
  'mixed': {'height': 0.8, 'spray': 0, 'width': 0.2, 'distance': 0.9},
};

const List<int> _rates = [44100, 48000];

/// 28 cases, in this order: session × rates [44100, 48000] × seeds
/// [1, 42, 20261123] × the four param sets; long × rates × seed 1 × default;
/// poolSteal × rates × seed 1 × default.
final List<DigestCase> digestCases = List.unmodifiable([
  for (final rate in _rates)
    for (final seed in const [1, 42, 20261123])
      for (final set in digestParamSets.keys)
        DigestCase(DigestScript.session, rate, seed, set),
  for (final rate in _rates) DigestCase(DigestScript.long, rate, 1, 'default'),
  for (final rate in _rates)
    DigestCase(DigestScript.poolSteal, rate, 1, 'default'),
]);

/// The hash of one rendered case.
final class DigestResult {
  const DigestResult(this.name, this.frames, this.hash);

  final String name;
  final int frames;

  /// 16 lowercase hex digits.
  final String hash;

  static const String _tag = 'FDIGEST v=1 ';
  static final RegExp _pattern = RegExp(
    r'^FDIGEST v=1 case=(\S+) frames=(\d+) hash=([0-9a-f]{16})$',
  );

  /// `FDIGEST v=1 case=<name> frames=<frames> hash=<hash>`.
  String get line => '${_tag}case=$name frames=$frames hash=$hash';

  /// Parses a [line] found anywhere in [text], so logcat prefixes are
  /// allowed. Returns null when [text] holds no valid digest line.
  static DigestResult? parse(String text) {
    final at = text.indexOf(_tag);
    if (at < 0) return null;
    final m = _pattern.firstMatch(text.substring(at).trimRight());
    if (m == null) return null;
    return DigestResult(m.group(1)!, int.parse(m.group(2)!), m.group(3)!);
  }
}

/// Outcome of [compareDigests]; the lists hold case names.
final class DigestComparison {
  DigestComparison._(this.expected, this.actual);

  /// Every digest of each text, keyed by case name, in text order.
  final Map<String, DigestResult> expected;
  final Map<String, DigestResult> actual;

  /// In both texts with a different hash or frame count.
  final List<String> differing = [];

  /// Only in the expected text.
  final List<String> missing = [];

  /// Only in the actual text.
  final List<String> extra = [];

  /// In both texts with the same hash and frame count.
  int matched = 0;

  /// At least one case matched and nothing differs, is missing or extra.
  bool get isMatch =>
      matched > 0 && differing.isEmpty && missing.isEmpty && extra.isEmpty;
}

const int _fnvOffset = 0xcbf29ce484222325;
const int _fnvPrime = 0x100000001b3;

/// FNV-1a 64 of [bytes], as 16 lowercase hex digits.
String fnv1a64Hex(List<int> bytes) {
  final h = _Fnv();
  for (final b in bytes) {
    h.byte(b);
  }
  return h.hex;
}

final class _Fnv {
  int _h = _fnvOffset;

  void byte(int b) {
    _h = (_h ^ (b & 0xFF)) * _fnvPrime;
  }

  /// Low byte, then high byte, of the first [count] samples.
  void int16(Int16List samples, int count) {
    var h = _h;
    for (var i = 0; i < count; i++) {
      final s = samples[i];
      h = (h ^ (s & 0xFF)) * _fnvPrime;
      h = (h ^ ((s >> 8) & 0xFF)) * _fnvPrime;
    }
    _h = h;
  }

  /// The four little-endian bytes of each float, left then right per frame.
  void float32Pairs(Float32List left, Float32List right, int frames) {
    final bytes = ByteData(8);
    for (var i = 0; i < frames; i++) {
      bytes
        ..setFloat32(0, left[i], Endian.little)
        ..setFloat32(4, right[i], Endian.little);
      for (var b = 0; b < 8; b++) {
        byte(bytes.getUint8(b));
      }
    }
  }

  String get hex =>
      (_h >>> 32).toRadixString(16).padLeft(8, '0') +
      (_h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
}

/// Renders [c] and hashes its output (PLAN 5.1). Master calls cycle through
/// [chunks] from its first entry; a call is shortened to end on the next
/// event frame. Throws [StateError] when the script's checks fail and
/// [ArgumentError] for an empty [chunks] or a chunk below 1.
DigestResult renderDigest(DigestCase c, {List<int> chunks = const [2048]}) {
  if (chunks.isEmpty || chunks.any((n) => n < 1)) {
    throw ArgumentError.value(chunks, 'chunks', 'must be non-empty, each >= 1');
  }
  return switch (c.script) {
    DigestScript.session => _session(c, chunks),
    DigestScript.long => _long(c, chunks),
    DigestScript.poolSteal => _poolSteal(c),
  };
}

const String _scapeId = 'waterfall';

/// Renders a master to exact event frames and hashes every sample.
final class _Renderer {
  _Renderer(DigestCase c, this._chunks)
    : rate = c.sampleRate,
      master = Master(sampleRate: c.sampleRate, seed: c.seed),
      _buffer = Int16List(_chunks.reduce(math.max) * 2);

  final int rate;
  final Master master;
  final List<int> _chunks;
  final Int16List _buffer;
  final _Fnv _hash = _Fnv();
  int _call = 0;
  int frames = 0;

  /// Renders up to the frame of second [t].
  void renderTo(int t) {
    final target = (t * rate).round();
    while (frames < target) {
      var n = _chunks[_call++ % _chunks.length];
      if (n > target - frames) n = target - frames;
      master.render(_buffer, n);
      _hash.int16(_buffer, n * 2);
      frames += n;
    }
  }

  DigestResult result(DigestCase c) => DigestResult(c.name, frames, _hash.hex);
}

DigestResult _session(DigestCase c, List<int> chunks) {
  final scape = createSoundscape(_scapeId)!;
  final set = digestParamSets[c.paramSet]!;
  final r = _Renderer(c, chunks);
  final m = r.master..add(scape);
  for (final e in set.entries) {
    m.setParam(_scapeId, e.key, e.value);
  }
  m.start(_scapeId);
  r.renderTo(6);
  for (final spec in scape.params) {
    m.setParam(_scapeId, spec.id, 1 - (set[spec.id] ?? spec.defaultValue));
  }
  r.renderTo(9);
  m.setGain(_scapeId, 0.5);
  r.renderTo(12);
  m.stop(_scapeId);
  r.renderTo(13);
  m.start(_scapeId);
  r.renderTo(16);
  m.stop(_scapeId, fade: const Duration(milliseconds: 200));
  r.renderTo(17);
  if (!m.isSilent) throw StateError('${c.name}: not silent at 17 s');
  m.start(_scapeId);
  r.renderTo(20);
  m.setGain(_scapeId, 4.0);
  r.renderTo(23);
  m.stop(_scapeId, fade: const Duration(milliseconds: 5));
  r.renderTo(24);
  if (!m.isSilent) throw StateError('${c.name}: not silent at 24 s');
  if (m.faultBlocks != 0) {
    throw StateError('${c.name}: ${m.faultBlocks} fault blocks');
  }
  return r.result(c);
}

DigestResult _long(DigestCase c, List<int> chunks) {
  final r = _Renderer(c, chunks);
  r.master
    ..add(createSoundscape(_scapeId)!)
    ..start(_scapeId);
  r.renderTo(300);
  if (r.master.faultBlocks != 0) {
    throw StateError('${c.name}: ${r.master.faultBlocks} fault blocks');
  }
  return r.result(c);
}

DigestResult _poolSteal(DigestCase c) {
  const blocks = 40;
  const spawns = 24;
  const frames = kBlockFrames;
  final white = NoiseBank(c.sampleRate, Rng.mix(c.seed, 1)).white;
  final pool = VoicePool()..prepare(c.sampleRate);
  final rng = Rng(c.seed);
  final left = Float32List(frames);
  final right = Float32List(frames);
  final hash = _Fnv();
  for (var b = 0; b < blocks; b++) {
    for (var s = 0; s < spawns; s++) {
      final channel = rng.nextU32() & 1;
      final position = rng.nextU32() % white.length;
      final freq = 800 * math.pow(5.0, rng.nextDouble()).toDouble();
      final q = rng.range(0.7, 1.2);
      final decay = rng.range(0.05, 0.2);
      final level = rng.range(0.6, 1.0);
      final pan = rng.range(-0.9, 0.9);
      final offset = rng.nextU32() % frames;
      pool.spawn(
        white,
        channel,
        position,
        BiquadType.bandPass,
        freq,
        q,
        0.002,
        decay,
        level,
        pan,
        offset,
      );
    }
    left.fillRange(0, frames, 0.0);
    right.fillRange(0, frames, 0.0);
    pool.render(left, right, frames);
    hash.float32Pairs(left, right, frames);
  }
  if (pool.stolenCount == 0) throw StateError('${c.name}: no voice stolen');
  return DigestResult(c.name, blocks * frames, hash.hex);
}

/// Compares the digest lines of two texts by case name. Lines may carry any
/// prefix (logcat); other lines are ignored. Throws [FormatException] when a
/// case name appears twice in one text.
DigestComparison compareDigests(String expected, String actual) {
  final c = DigestComparison._(_digests(expected), _digests(actual));
  for (final e in c.expected.values) {
    final a = c.actual[e.name];
    if (a == null) {
      c.missing.add(e.name);
    } else if (a.hash != e.hash || a.frames != e.frames) {
      c.differing.add(e.name);
    } else {
      c.matched++;
    }
  }
  for (final name in c.actual.keys) {
    if (!c.expected.containsKey(name)) c.extra.add(name);
  }
  return c;
}

Map<String, DigestResult> _digests(String text) {
  final out = <String, DigestResult>{};
  for (final line in text.split('\n')) {
    final d = DigestResult.parse(line);
    if (d == null) continue;
    if (out.containsKey(d.name)) {
      throw FormatException('case ${d.name} appears twice', line);
    }
    out[d.name] = d;
  }
  return out;
}
