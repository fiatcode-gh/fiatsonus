import 'audio_flinger.dart';
import 'battery_history.dart';
import 'fstat.dart';
import 'proc_stat.dart';
import 'time_in_state.dart';

/// The files of one snapshot directory, by file name, and its label (`t0`
/// or `t1`) for messages.
class Snapshot {
  const Snapshot(this.label, this.files);

  final String label;
  final Map<String, String> files;
}

class ReportOptions {
  const ReportOptions({
    this.battery = false,
    this.expectForeground = false,
    this.maxRenderRatio = 0.05,
    this.minBatteryWindowSeconds = 3600,
  });

  final bool battery;
  final bool expectForeground;
  final double maxRenderRatio;
  final int minBatteryWindowSeconds;
}

class Report {
  const Report(this.results, this.cpu, this.failures);

  /// Result values by key, in output order.
  final Map<String, String> results;

  /// `CPU PASS …`, `CPU MISS …` or `CPU UNKNOWN`: the render ratio against
  /// its limit, reported apart from the functional verdict.
  final String cpu;
  final List<String> failures;

  /// The functional verdict; the CPU line does not decide it.
  bool get passed => failures.isEmpty;

  /// One `RESULT key=value` line per result, the CPU line, then `PASS` or
  /// `FAIL <reason>; <reason>…`.
  String format() => [
    for (final MapEntry(:key, :value) in results.entries) 'RESULT $key=$value',
    cpu,
    passed ? 'PASS' : 'FAIL ${failures.join('; ')}',
  ].join('\n');
}

Report buildReport(Snapshot t0, Snapshot t1, ReportOptions options) =>
    _ReportBuilder(t0, t1, options).build();

/// Seconds an `FSTAT` line may lag its snapshot before logcat is taken to
/// have lost lines or playback to have stopped.
const _maxFstatAgeSeconds = 30;

class _ReportBuilder {
  _ReportBuilder(this.t0, this.t1, this.options);

  final Snapshot t0;
  final Snapshot t1;
  final ReportOptions options;
  final results = <String, String>{};
  final failures = <String>[];

  /// The first thread of `top_threads`, the engine thread.
  ProcStat? _engineThread;

  Report build() {
    final time0 = _parse(t0, 'time.txt', _parseTime);
    final time1 = _parse(t1, 'time.txt', _parseTime);
    final pid0 = _pid(t0);
    final pid1 = _pid(t1);
    if (pid0 != null && pid1 != null && pid0 != pid1) {
      failures.add('pid changed: $pid0 at t0, $pid1 at t1');
    }

    double? wall;
    if (time0 != null && time1 != null) {
      wall = time1.uptimeS - time0.uptimeS;
      results['wall_s'] = wall.toStringAsFixed(3);
      if (wall <= 0) {
        failures.add('wall_s ${wall.toStringAsFixed(3)} <= 0');
        wall = null;
      }
    }

    final cpuPct = _cpu(wall);
    final f0 = _fstat(t0);
    final f1 = _fstat(t1);
    final renderPct = _fstatResults(f0, f1, wall);
    _residency(renderPct);
    _audioFlinger(pid0, pid1, f1);

    if (renderPct != null && cpuPct != null && cpuPct < 0.5 * renderPct) {
      failures.add(
        'process_cpu_pct ${cpuPct.toStringAsFixed(2)} < 0.5 × '
        'render_ratio_pct ${renderPct.toStringAsFixed(2)}',
      );
    }
    for (final (snapshot, time, fstat) in [(t0, time0, f0), (t1, time1, f1)]) {
      if (time == null || fstat == null) continue;
      final age = (time.epochMs - fstat.epochMs) / 1000;
      if (age > _maxFstatAgeSeconds) {
        failures.add(
          'FSTAT line of ${snapshot.label} is ${age.toStringAsFixed(1)} s '
          'older than the snapshot',
        );
      }
    }

    final foreground = _parse(t1, 'services.txt', _audioServiceInForeground);
    if (foreground != null) {
      results['foreground'] = '$foreground';
      if (options.expectForeground && !foreground) {
        failures.add('AudioService not in the foreground at t1');
      }
    }
    if (options.battery) _battery(time0, time1);
    return Report(results, _cpuLine(renderPct), failures);
  }

  String _cpuLine(double? renderPct) {
    if (renderPct == null) return 'CPU UNKNOWN';
    final limitPct = options.maxRenderRatio * 100;
    final verdict = renderPct < limitPct ? 'PASS' : 'MISS';
    return 'CPU $verdict render_ratio_pct=${renderPct.toStringAsFixed(2)} '
        'limit_pct=${limitPct.toStringAsFixed(2)}';
  }

  /// Parses [file] of [snapshot]; a missing file or a [FormatException] is a
  /// fail reason naming the file and yields null.
  T? _parse<T>(
    Snapshot snapshot,
    String file,
    T Function(String text) parse, {
    String unparsable = 'unparsable',
  }) {
    final text = snapshot.files[file];
    if (text == null) {
      failures.add('${snapshot.label}/$file missing');
      return null;
    }
    try {
      return parse(text);
    } on FormatException catch (e) {
      failures.add('$unparsable ${snapshot.label}/$file: ${e.message}');
      return null;
    }
  }

  int? _pid(Snapshot snapshot) {
    if (_isBlank(snapshot, 'pid.txt')) {
      failures.add('no pid in ${snapshot.label}/pid.txt');
      return null;
    }
    return _parse(
      snapshot,
      'pid.txt',
      (text) =>
          int.tryParse(text.trim()) ??
          (throw FormatException('not a pid', text)),
    );
  }

  bool _isBlank(Snapshot snapshot, String file) =>
      snapshot.files[file]?.trim().isEmpty ?? false;

  double? _cpu(double? wall) {
    final p0 = _parse(t0, 'proc_stat.txt', (t) => parseProcStat(t.trim()));
    final p1 = _parse(t1, 'proc_stat.txt', (t) => parseProcStat(t.trim()));
    final tasks0 = _parse(t0, 'task_stat.txt', parseProcStats);
    final tasks1 = _parse(t1, 'task_stat.txt', parseProcStats);
    if (wall == null) return null;

    // Ticks are 1/100 s; ticks / 100 / wall × 100 is percent of one core.
    double pct(int ticks) => ticks / wall;

    double? cpuPct;
    if (p0 != null && p1 != null) {
      cpuPct = pct(p1.cpuTicks - p0.cpuTicks);
      results['process_cpu_pct'] = cpuPct.toStringAsFixed(2);
    }
    if (tasks0 != null && tasks1 != null) {
      final before = {for (final t in tasks0) t.pid: t.cpuTicks};
      final deltas =
          [for (final t in tasks1) (t, t.cpuTicks - (before[t.pid] ?? 0))]
            ..sort((a, b) {
              final byTicks = b.$2.compareTo(a.$2);
              return byTicks != 0 ? byTicks : a.$1.pid.compareTo(b.$1.pid);
            });
      results['top_threads'] = deltas
          .take(5)
          .map((d) => '${d.$1.comm}:${pct(d.$2).toStringAsFixed(2)}')
          .join(',');
      _engineThread = deltas.firstOrNull?.$1;
    }
    return cpuPct;
  }

  /// The engine thread's cluster and frequency shares between t0 and t1,
  /// when both snapshots hold `task_time_in_state.txt` and the thread spent
  /// ticks; information only.
  void _residency(double? renderPct) {
    const file = 'task_time_in_state.txt';
    final engine = _engineThread;
    if (engine == null ||
        !t0.files.containsKey(file) ||
        !t1.files.containsKey(file)) {
      return;
    }
    final tis0 = _parse(t0, file, parseTaskTimeInState);
    final tis1 = _parse(t1, file, parseTaskTimeInState);
    final after = tis1?[engine.pid];
    if (tis0 == null || after == null) return;
    final TimeInState delta;
    try {
      delta = timeInStateDelta(tis0[engine.pid] ?? const {}, after);
    } on FormatException catch (e) {
      failures.add('unparsable t1/$file: tid ${engine.pid}: ${e.message}');
      return;
    }
    final total = totalTicks(delta);
    if (total == 0) return;

    final clusters = delta.keys;
    results['engine_thread'] = '${engine.comm}:${engine.pid}';
    results['engine_cluster_pct'] = clusters
        .map((c) => '$c:${(clusterShare(delta, c) * 100).toStringAsFixed(1)}')
        .join(',');
    results['engine_mean_khz'] = clusters
        .map((c) => '$c:${meanKhz(delta, c).round()}')
        .join(',');
    final frequencies =
        [
          for (final MapEntry(key: cluster, value: khz) in delta.entries)
            for (final MapEntry(key: freq, value: ticks) in khz.entries)
              if (ticks * 100 >= total) (cluster, freq, ticks),
        ]..sort((a, b) {
          final byTicks = b.$3.compareTo(a.$3);
          if (byTicks != 0) return byTicks;
          final byCluster = a.$1.compareTo(b.$1);
          return byCluster != 0 ? byCluster : a.$2.compareTo(b.$2);
        });
    results['engine_freq_pct'] = frequencies
        .take(8)
        .map(
          (f) => '${f.$1}@${f.$2}:${(f.$3 / total * 100).toStringAsFixed(1)}',
        )
        .join(',');
    if (renderPct == null) return;
    // Assumes speed proportional to frequency inside a cluster (PLAN D8).
    final scale = clusters
        .where((c) => clusterShare(delta, c) > 0)
        .fold(
          0.0,
          (sum, c) =>
              sum +
              clusterShare(delta, c) * meanKhz(delta, c) / maxKhz(delta, c),
        );
    results['render_ratio_at_max_freq_pct'] = (renderPct * scale)
        .toStringAsFixed(2);
  }

  Fstat? _fstat(Snapshot snapshot) {
    if (_isBlank(snapshot, 'fstat.txt')) {
      failures.add('no FSTAT line in ${snapshot.label}/fstat.txt');
      return null;
    }
    return _parse(snapshot, 'fstat.txt', (t) => parseFstat(t.trim()));
  }

  /// Records the `FSTAT` results and their fail reasons; returns
  /// `render_ratio_pct`.
  double? _fstatResults(Fstat? f0, Fstat? f1, double? wall) {
    if (f0 == null || f1 == null) return null;
    final playUs = f1.playUs - f0.playUs;
    if (playUs <= 0) {
      failures.add('play_us did not advance (difference $playUs)');
      return null;
    }
    final renderPct = (f1.renderUs - f0.renderUs) / playUs * 100;
    final audioS = (f1.frames - f0.frames) / f1.rate;
    final deficitMs = playUs / 1000 - audioS * 1000;
    results['render_ratio_pct'] = renderPct.toStringAsFixed(2);
    results['max_render_us'] = '${f1.maxRenderUs}';
    results['audio_s'] = audioS.toStringAsFixed(3);
    results['deficit_ms'] = deficitMs.toStringAsFixed(1);

    for (final (key, value) in [
      ('underruns', f1.underruns - f0.underruns),
      ('starved_us', f1.starvedUs - f0.starvedUs),
      ('overlaps', f1.overlaps - f0.overlaps),
      ('faults', f1.faults - f0.faults),
    ]) {
      results[key] = '$value';
      if (value != 0) failures.add('$key $value != 0');
    }
    if (wall != null) {
      final boundMs = 300 + 0.0002 * wall * 1000;
      if (deficitMs.abs() > boundMs) {
        failures.add(
          'deficit_ms ${deficitMs.toStringAsFixed(1)} exceeds '
          '${boundMs.toStringAsFixed(1)}',
        );
      }
    }
    return renderPct;
  }

  void _audioFlinger(int? pid0, int? pid1, Fstat? f1) {
    final af0 = _parse(t0, 'audio_flinger.txt', parseAudioFlinger);
    final af1 = _parse(t1, 'audio_flinger.txt', parseAudioFlinger);
    if (af0 != null && af1 != null && pid0 != null && pid1 != null) {
      final before = {
        for (final t in tracksOfPid(af0, pid0)) t.id: t.underruns,
      };
      final underruns = tracksOfPid(
        af1,
        pid1,
      ).fold(0, (sum, t) => sum + t.underruns - (before[t.id] ?? 0));
      results['af_underruns'] = '$underruns';
      if (underruns != 0) failures.add('af_underruns $underruns != 0');
    }

    if (f1 != null) results['engine_rate'] = '${f1.rate}';
    if (af1 == null || pid1 == null) return;
    final deviceRate = sampleRateOfPid(af1, pid1);
    if (deviceRate == null) {
      failures.add(
        'no output thread with a sample rate holds a track of pid $pid1 in '
        't1/audio_flinger.txt',
      );
      return;
    }
    results['device_rate'] = '$deviceRate';
    if (f1 != null && f1.rate != deviceRate) {
      failures.add('engine_rate ${f1.rate} != device_rate $deviceRate');
    }
  }

  void _battery(_Time? time0, _Time? time1) {
    final local0 = _local(t0, time0);
    final local1 = _local(t1, time1);
    final history = t1.files['batterystats_history.txt'];
    if (history == null) {
      failures.add('t1/batterystats_history.txt missing');
    } else if (local0 != null && local1 != null) {
      final found = findUnpluggedWindow(history, t0: local0, t1: local1);
      failures.addAll(found.failures);
      final window = found.window;
      if (window != null) {
        results['battery_window'] =
            '${_stamp(window.start)}..${_stamp(window.end)}';
        results['battery_mah'] = '${window.mah}';
        results['battery_hours'] = window.hours.toStringAsFixed(3);
        results['battery_mah_per_h'] = window.mahPerHour.toStringAsFixed(1);
        results['battery_level_drop'] = '${window.levelDrop}';
        final min = options.minBatteryWindowSeconds;
        if (window.seconds < min) {
          failures.add(
            'battery window ${window.seconds.toStringAsFixed(0)} s < $min s',
          );
        }
      }
    }

    final battery0 = _parse(t0, 'battery.txt', _parseBattery);
    final battery1 = _parse(t1, 'battery.txt', _parseBattery);
    if (battery0 != null && battery1 != null) {
      results['battery_counter_mah'] =
          ((battery0.chargeCounterUah - battery1.chargeCounterUah) / 1000)
              .toStringAsFixed(1);
      results['battery_counter_level_drop'] =
          '${battery0.level - battery1.level}';
    }
  }

  /// The phone's local clock of a snapshot; its absence is a fail reason.
  DateTime? _local(Snapshot snapshot, _Time? time) {
    if (time == null) return null;
    if (time.local == null) {
      failures.add('no local= in ${snapshot.label}/time.txt');
    }
    return time.local;
  }
}

/// A local stamp held as UTC, without the `Z`.
String _stamp(DateTime local) => local.toIso8601String().replaceFirst('Z', '');

class _Time {
  const _Time(this.epochMs, this.uptimeS, this.local);

  final int epochMs;
  final double uptimeS;

  /// The phone's local clock as a UTC value, when `time.txt` has `local=`.
  final DateTime? local;
}

final _localTime = RegExp(r'^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$');

_Time _parseTime(String text) {
  final values = <String, String>{
    for (final line in text.split('\n'))
      if (line.contains('='))
        line.substring(0, line.indexOf('=')).trim(): line
            .substring(line.indexOf('=') + 1)
            .trim(),
  };
  final epochMs = int.tryParse(values['epoch_ms'] ?? '');
  final uptimeS = double.tryParse(values['uptime_s'] ?? '');
  if (epochMs == null || uptimeS == null) {
    throw FormatException('no epoch_ms or uptime_s', text);
  }
  final local = _localTime.firstMatch(values['local'] ?? '');
  return _Time(
    epochMs,
    uptimeS,
    local == null
        ? null
        : DateTime.utc(
            int.parse(local.group(1)!),
            int.parse(local.group(2)!),
            int.parse(local.group(3)!),
            int.parse(local.group(4)!),
            int.parse(local.group(5)!),
            int.parse(local.group(6)!),
          ),
  );
}

final _chargeCounter = RegExp(
  r'^\s*Charge counter: (\d+)\s*$',
  multiLine: true,
);
final _batteryLevel = RegExp(r'^\s*level: (\d+)\s*$', multiLine: true);

/// `Charge counter` (µAh) and `level` (%) of `dumpsys battery`.
({int chargeCounterUah, int level}) _parseBattery(String text) {
  final counter = _chargeCounter.firstMatch(text);
  final level = _batteryLevel.firstMatch(text);
  if (counter == null) throw FormatException('no Charge counter', text);
  if (level == null) throw FormatException('no level', text);
  return (
    chargeCounterUah: int.parse(counter.group(1)!),
    level: int.parse(level.group(1)!),
  );
}

final _serviceRecord = RegExp(r'^\s*\* ServiceRecord\{');
final _audioService = RegExp(r'/\S*AudioService[\s}]');
final _foreground = RegExp(r'(?:^|\s)isForeground=true(?:\s|$)');

/// Whether a `ServiceRecord` of an `AudioService` class says
/// `isForeground=true`.
bool _audioServiceInForeground(String services) {
  var inAudioService = false;
  for (final line in services.split('\n')) {
    if (_serviceRecord.hasMatch(line)) {
      inAudioService = _audioService.hasMatch(line);
    } else if (RegExp(r'^ {0,2}\S').hasMatch(line)) {
      inAudioService = false;
    } else if (inAudioService && _foreground.hasMatch(line)) {
      return true;
    }
  }
  return false;
}
