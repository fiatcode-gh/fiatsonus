/// A thread's CPU time per cluster and frequency, as
/// `/proc/<pid>/task/<tid>/time_in_state` lists it: cluster (`cpu0`, `cpu4`)
/// to kHz to ticks of 1/100 s.
typedef TimeInState = Map<String, Map<int, int>>;

final _cluster = RegExp(r'^cpu\d+$');
final _counter = RegExp(r'^(\d+)\s+(\d+)$');
final _tid = RegExp(r'^tid=(\d+)$');

/// Parses one thread's `time_in_state`: `cpu<n>` headers, each followed by
/// `<kHz> <ticks>` lines. Blank lines are skipped.
TimeInState parseTimeInState(String text) {
  final result = <String, Map<int, int>>{};
  Map<int, int>? cluster;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (_cluster.hasMatch(line)) {
      cluster = result.putIfAbsent(line, () => {});
      continue;
    }
    final counter = _counter.firstMatch(line);
    if (counter == null || cluster == null) {
      throw FormatException('not a cluster or counter line: "$line"', text);
    }
    cluster[int.parse(counter.group(1)!)] = int.parse(counter.group(2)!);
  }
  return result;
}

/// Parses `tid=<n>` blocks, each followed by that thread's `time_in_state`,
/// as `snapshot.sh` writes `task_time_in_state.txt`. A block without lines
/// (a thread that exited before its file was read) is an empty thread.
Map<int, TimeInState> parseTaskTimeInState(String text) {
  final blocks = <int, List<String>>{};
  List<String>? block;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final tid = _tid.firstMatch(line);
    if (tid != null) {
      block = blocks[int.parse(tid.group(1)!)] = [];
    } else if (line.isNotEmpty) {
      if (block == null) {
        throw FormatException('line before the first tid=: "$line"', text);
      }
      block.add(line);
    }
  }
  return {
    for (final MapEntry(:key, :value) in blocks.entries)
      key: parseTimeInState(value.join('\n')),
  };
}

/// The ticks [after] added to [before], per cluster and frequency of
/// [after]; a frequency new in [after] counts from 0.
TimeInState timeInStateDelta(TimeInState before, TimeInState after) {
  for (final MapEntry(key: cluster, value: khz) in before.entries) {
    for (final MapEntry(key: freq, value: ticks) in khz.entries) {
      if (ticks > (after[cluster]?[freq] ?? 0)) {
        throw FormatException('counter $cluster $freq went down');
      }
    }
  }
  return {
    for (final MapEntry(key: cluster, value: khz) in after.entries)
      cluster: {
        for (final MapEntry(key: freq, value: ticks) in khz.entries)
          freq: ticks - (before[cluster]?[freq] ?? 0),
      },
  };
}

int totalTicks(TimeInState t) =>
    t.values.fold(0, (sum, khz) => sum + _ticks(khz));

/// The part of [t]'s ticks spent on [cluster], 0..1; 0 without ticks.
double clusterShare(TimeInState t, String cluster) {
  final total = totalTicks(t);
  return total == 0 ? 0 : _ticks(t[cluster] ?? const {}) / total;
}

/// The tick-weighted mean frequency on [cluster]; 0 without ticks.
double meanKhz(TimeInState t, String cluster) {
  final khz = t[cluster] ?? const {};
  final ticks = _ticks(khz);
  if (ticks == 0) return 0;
  return khz.entries.fold(0.0, (sum, e) => sum + e.key * e.value) / ticks;
}

/// The highest frequency listed for [cluster], with or without ticks; 0 when
/// the cluster is not listed.
int maxKhz(TimeInState t, String cluster) =>
    (t[cluster]?.keys ?? const <int>[]).fold(0, (m, f) => f > m ? f : m);

int _ticks(Map<int, int> khz) => khz.values.fold(0, (sum, t) => sum + t);
