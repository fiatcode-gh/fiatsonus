import 'package:fiatsonus_engine/profiling.dart';

import 'time_in_state.dart';

/// A stage's CPU ticks per cluster and frequency and its wall time, summed
/// over its runs; each run counts from the `tis` line before its stage line
/// to the one after it.
final class StageResidency {
  const StageResidency(this.ticks, this.wallMicros);

  final TimeInState ticks;
  final int wallMicros;
}

/// The stage lines of one bench file (`bench.txt` of `bench_run.sh` or the
/// output of `stage_bench`) and, where its `tis` lines allow, each stage's
/// residency.
final class BenchFile {
  BenchFile._(this.runs, this.residency);

  /// Throws [FormatException] when a [BenchStage] has no stage line or a
  /// `tis` line's data does not parse.
  factory BenchFile.parse(String text) {
    final runs = {for (final s in BenchStage.values) s: <StageRun>[]};
    final ticks = <BenchStage, TimeInState>{};
    final wall = <BenchStage, int>{};
    final measured = <BenchStage, int>{};
    _Tis? last;
    (BenchStage, _Tis?)? pending;
    for (final line in text.split('\n')) {
      final run = StageRun.parse(line);
      if (run != null) {
        runs[run.stage]!.add(run);
        pending = (run.stage, last);
        last = null;
        continue;
      }
      final tis = _Tis.parse(line);
      if (tis == null) continue;
      if (pending case (final stage, final before?)) {
        final (b, a) = (before.data, tis.data);
        if (b != null && a != null) {
          _addTicks(ticks.putIfAbsent(stage, () => {}), timeInStateDelta(b, a));
          wall[stage] = (wall[stage] ?? 0) + tis.micros - before.micros;
          measured[stage] = (measured[stage] ?? 0) + 1;
        }
      }
      pending = null;
      last = tis;
    }
    for (final MapEntry(:key, :value) in runs.entries) {
      if (value.isEmpty) {
        throw FormatException('no stage line for ${key.name}', text);
      }
    }
    return BenchFile._(runs, {
      for (final s in BenchStage.values)
        if (measured[s] == runs[s]!.length)
          s: StageResidency(ticks[s]!, wall[s]!),
    });
  }

  /// Every run of each stage, in file order.
  final Map<BenchStage, List<StageRun>> runs;

  /// The stages whose every run has readable `tis` lines on both sides.
  final Map<BenchStage, StageResidency> residency;

  List<double> _sorted(BenchStage s) =>
      [for (final r in runs[s]!) r.microsPerSecond]..sort();

  double median(BenchStage s) {
    final v = _sorted(s);
    final n = v.length;
    return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
  }

  double min(BenchStage s) => _sorted(s).first;

  double max(BenchStage s) => _sorted(s).last;

  /// [stageShares] of the medians.
  Map<String, double> get shares =>
      stageShares({for (final s in BenchStage.values) s: median(s)});
}

/// One `FBENCH tis` line: the bench stopwatch and the thread's residency,
/// null when the phone could not read it.
final class _Tis {
  const _Tis(this.micros, this.data);

  final int micros;
  final TimeInState? data;

  static const String _tag = 'FBENCH tis ';
  static final RegExp _pattern = RegExp(r'^FBENCH tis t_us=(\d+) data=(.*)$');

  static _Tis? parse(String line) {
    final at = line.indexOf(_tag);
    if (at < 0) return null;
    final m = _pattern.firstMatch(line.substring(at).trimRight());
    if (m == null) throw FormatException('bad tis line', line);
    final data = m.group(2)!;
    return _Tis(
      int.parse(m.group(1)!),
      data == 'unavailable'
          ? null
          : parseTimeInState(data.replaceAll(',', '\n')),
    );
  }
}

void _addTicks(TimeInState sum, TimeInState delta) {
  for (final MapEntry(key: cluster, value: khz) in delta.entries) {
    final into = sum.putIfAbsent(cluster, () => {});
    for (final MapEntry(key: freq, value: ticks) in khz.entries) {
      into[freq] = (into[freq] ?? 0) + ticks;
    }
  }
}

/// One tick of `time_in_state` in microseconds.
const int _tickMicros = 10000;

/// The Markdown stage and share tables of PLAN 5.5, then one line per
/// `UNRELIABLE split` and `INCOMPARABLE placement` finding.
String benchReport({
  required BenchFile phone,
  BenchFile? desktop,
  BenchFile? basePhone,
  BenchFile? baseDesktop,
}) {
  final out = <String>[
    '## Stages',
    '',
    _row([
      'stage',
      'median us/s',
      'min',
      'max',
      'factor',
      'cluster %',
      'mean MHz',
      'CPU/wall',
      'desktop us/s',
      'phone/desktop',
      'vs base phone',
      'vs base desktop',
    ]),
    _rule(12),
  ];
  for (final s in BenchStage.values) {
    final median = phone.median(s);
    final residency = phone.residency[s];
    final clusters = residency == null
        ? const <String>[]
        : (residency.ticks.keys.toList()..sort());
    final desktopMedian = desktop?.median(s);
    out.add(
      _row([
        s.name,
        _int(median),
        _int(phone.min(s)),
        _int(phone.max(s)),
        (1e6 / median).toStringAsFixed(1),
        [
          for (final c in clusters)
            '$c ${(clusterShare(residency!.ticks, c) * 100).toStringAsFixed(1)}',
        ].join(', '),
        [
          for (final c in clusters)
            '$c ${(meanKhz(residency!.ticks, c) / 1000).round()}',
        ].join(', '),
        residency == null || residency.wallMicros == 0
            ? ''
            : (totalTicks(residency.ticks) * _tickMicros / residency.wallMicros)
                  .toStringAsFixed(2),
        desktopMedian == null ? '' : _int(desktopMedian),
        _ratio(median, desktopMedian, 1),
        _ratio(basePhone?.median(s), median, 2),
        desktopMedian == null
            ? ''
            : _ratio(baseDesktop?.median(s), desktopMedian, 2),
      ]),
    );
  }

  final shares = phone.shares;
  final desktopShares = desktop?.shares;
  final fullRatio = desktopShares == null
      ? null
      : shares['full']! / desktopShares['full']!;
  out.addAll([
    '',
    '## Shares',
    '',
    _row([
      'share',
      'phone us/s',
      'phone %',
      'desktop us/s',
      'desktop %',
      'phone/desktop',
      'mark',
    ]),
    _rule(7),
  ]);
  for (final MapEntry(:key, :value) in shares.entries) {
    final d = desktopShares?[key];
    final ratio = d == null || d == 0 ? null : value / d;
    out.add(
      _row([
        key,
        _int(value),
        _pct(value, shares['full']!),
        d == null ? '' : _int(d),
        d == null ? '' : _pct(d, desktopShares!['full']!),
        ratio == null ? '' : ratio.toStringAsFixed(1),
        key != 'full' && ratio != null && ratio >= 1.5 * fullRatio!
            ? 'OUTLIER'
            : '',
      ]),
    );
  }

  final findings = [
    ?_unreliable('phone', shares),
    if (desktopShares != null) ?_unreliable('desktop', desktopShares),
    ?_placement(phone, basePhone),
  ];
  if (findings.isNotEmpty) out.addAll(['', ...findings]);
  return out.join('\n');
}

/// PLAN 5.2: the split is unreliable when |unexplained| exceeds 5 % of full.
String? _unreliable(String label, Map<String, double> shares) {
  final part = shares['unexplained']! / shares['full']!;
  if (part.abs() <= 0.05) return null;
  return 'UNRELIABLE split $label: unexplained '
      '${(part * 100).toStringAsFixed(1)} % of full';
}

/// `full`'s share on the big cluster (the one with the highest listed
/// frequency) moved by more than 20 points against the base.
String? _placement(BenchFile phone, BenchFile? base) {
  final now = phone.residency[BenchStage.full]?.ticks;
  final then = base?.residency[BenchStage.full]?.ticks;
  if (now == null || then == null) return null;
  final clusters = {...now.keys, ...then.keys}.toList()..sort();
  if (clusters.isEmpty) return null;
  int top(String c) =>
      [maxKhz(now, c), maxKhz(then, c)].reduce((a, b) => a > b ? a : b);
  final big = clusters.reduce((a, b) => top(b) > top(a) ? b : a);
  final a = clusterShare(now, big) * 100;
  final b = clusterShare(then, big) * 100;
  if ((a - b).abs() <= 20) return null;
  return 'INCOMPARABLE placement: full on $big ${a.toStringAsFixed(1)} % '
      'against ${b.toStringAsFixed(1)} % in the base';
}

String _row(List<String> cells) => '| ${cells.join(' | ')} |';

String _rule(int columns) => '|${List.filled(columns, '---').join('|')}|';

String _int(double v) => '${v.round()}';

String _pct(double v, double full) => (v / full * 100).toStringAsFixed(1);

/// [over] / [under] with [digits] decimals; empty when either is missing or
/// [under] is 0.
String _ratio(double? over, double? under, int digits) =>
    over == null || under == null || under == 0
    ? ''
    : (over / under).toStringAsFixed(digits);
