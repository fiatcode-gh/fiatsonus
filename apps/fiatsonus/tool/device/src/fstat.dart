/// One `FSTAT v=1` statistics line of the app (PLAN 4.5) as logcat printed
/// it with `-v epoch`.
class Fstat {
  const Fstat({
    required this.epochMs,
    required this.sink,
    required this.rate,
    required this.playUs,
    required this.renderUs,
    required this.maxRenderUs,
    required this.frames,
    required this.underruns,
    required this.starvedUs,
    required this.overlaps,
    required this.faults,
    required this.sessions,
  });

  /// When logcat received the line.
  final int epochMs;
  final String sink;
  final int rate;
  final int playUs;
  final int renderUs;
  final int maxRenderUs;
  final int frames;
  final int underruns;
  final int starvedUs;
  final int overlaps;
  final int faults;
  final int sessions;
}

final _epoch = RegExp(r'^\s*(\d+)\.(\d{3})\s');

Fstat parseFstat(String line) {
  final epoch = _epoch.firstMatch(line);
  final at = line.indexOf('FSTAT ');
  if (epoch == null || at < 0) {
    throw FormatException('not a logcat -v epoch FSTAT line', line);
  }
  final fields = <String, String>{
    for (final pair in line.substring(at + 'FSTAT '.length).trim().split(' '))
      if (pair.contains('='))
        pair.substring(0, pair.indexOf('=')): pair.substring(
          pair.indexOf('=') + 1,
        ),
  };
  if (fields['v'] != '1') {
    throw FormatException('unknown FSTAT version ${fields['v']}', line);
  }
  int field(String key) {
    final value = int.tryParse(fields[key] ?? '');
    if (value == null) throw FormatException('FSTAT has no integer $key', line);
    return value;
  }

  final sink = fields['sink'];
  if (sink == null) throw FormatException('FSTAT has no sink', line);
  final rate = field('rate');
  if (rate <= 0) throw FormatException('FSTAT rate $rate', line);
  return Fstat(
    epochMs: int.parse(epoch.group(1)!) * 1000 + int.parse(epoch.group(2)!),
    sink: sink,
    rate: rate,
    playUs: field('play_us'),
    renderUs: field('render_us'),
    maxRenderUs: field('max_render_us'),
    frames: field('frames'),
    underruns: field('underruns'),
    starvedUs: field('starved_us'),
    overlaps: field('overlaps'),
    faults: field('faults'),
    sessions: field('sessions'),
  );
}
