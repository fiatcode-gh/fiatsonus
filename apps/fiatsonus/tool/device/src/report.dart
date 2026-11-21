import 'audio_flinger.dart';
import 'battery_history.dart';
import 'fstat.dart';
import 'proc_stat.dart';

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
  });

  final bool battery;
  final bool expectForeground;
  final double maxRenderRatio;
}

class Report {
  const Report(this.results, this.failures);

  /// Result values by key, in output order.
  final Map<String, String> results;
  final List<String> failures;

  bool get passed => failures.isEmpty;

  /// One `RESULT key=value` line per result, then `PASS` or
  /// `FAIL <reason>; <reason>…`.
  String format() => [
    for (final MapEntry(:key, :value) in results.entries) 'RESULT $key=$value',
    passed ? 'PASS' : 'FAIL ${failures.join('; ')}',
  ].join('\n');
}

Report buildReport(Snapshot t0, Snapshot t1, ReportOptions options) =>
    _ReportBuilder(t0, t1, options).build();

/// Seconds an `FSTAT` line may lag its snapshot before logcat is taken to
/// have lost lines or playback to have stopped.
const _maxFstatAgeSeconds = 30;
const _minBatteryWindowSeconds = 3600;

class _ReportBuilder {
  _ReportBuilder(this.t0, this.t1, this.options);

  final Snapshot t0;
  final Snapshot t1;
  final ReportOptions options;
  final results = <String, String>{};
  final failures = <String>[];

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
    if (options.battery) _battery(pid1);
    return Report(results, failures);
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
    }
    return cpuPct;
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

    final limitPct = options.maxRenderRatio * 100;
    if (renderPct >= limitPct) {
      failures.add(
        'render_ratio_pct ${renderPct.toStringAsFixed(2)} >= '
        '${limitPct.toStringAsFixed(2)}',
      );
    }
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

  void _battery(int? pid1) {
    final window = _parse(
      t1,
      'batterystats_history.txt',
      parseUnpluggedWindow,
      unparsable: 'no unplugged window in',
    );
    if (window != null) {
      results['battery_mah'] = '${window.mah}';
      results['battery_hours'] = window.hours.toStringAsFixed(3);
      results['battery_mah_per_h'] = window.mahPerHour.toStringAsFixed(1);
      results['battery_level_drop'] = '${window.levelDrop}';
      if (window.seconds < _minBatteryWindowSeconds) {
        failures.add(
          'battery window ${window.seconds.toStringAsFixed(0)} s < '
          '$_minBatteryWindowSeconds s',
        );
      }
    }
    final uid = pid1 == null ? null : _uidOf(t1.files['services.txt'], pid1);
    final estimate = _parse(
      t1,
      'batterystats_app.txt',
      (text) => uid == null ? null : parseAppEstimateMah(text, uid),
    );
    results['battery_app_estimate_mah'] = estimate == null
        ? 'n/a'
        : '$estimate';
  }
}

class _Time {
  const _Time(this.epochMs, this.uptimeS);

  final int epochMs;
  final double uptimeS;
}

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
  return _Time(epochMs, uptimeS);
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

/// The uid (`u0a105` form) of the `ProcessRecord` of [pid], if listed.
String? _uidOf(String? services, int pid) => services == null
    ? null
    : RegExp('ProcessRecord\\{[0-9a-f]+ $pid:[^/}]+/(\\S+?)\\}')
          .firstMatch(services)
          ?.group(1);
