import '../../tool/device/src/report.dart';
import 'fixtures.dart';

const kEpoch0 = 1795226960000;
const kWallSeconds = 600;
const kEpoch1 = kEpoch0 + kWallSeconds * 1000;

/// The phone's local clock at t0 and t1. The report never compares `local`
/// with `epoch_ms`, so these are chosen to span the real unplugged window of
/// `batterystats_history_anchored.txt` (11-21 12:17:54.666 to 11-22
/// 09:55:24.736) rather than the 600 s of `epoch_ms`.
const kLocal0 = '2026-11-21 12:00:00';
const kLocal1 = '2026-11-22 10:03:00';

/// `time.txt` as `snapshot.sh` writes it.
String timeTxt({
  required int epochMs,
  required String uptimeS,
  String? local,
}) =>
    'epoch_ms=$epochMs\nuptime_s=$uptimeS\n'
    '${local == null ? '' : 'local=$local\n'}';

/// `battery.txt` of the fixture with its `Charge counter` and `level` set.
String batteryTxt({required int chargeCounter, required int level}) =>
    fixture('battery.txt')
        .replaceFirst(
          'Charge counter: 5010642',
          'Charge counter: $chargeCounter',
        )
        .replaceFirst('  level: 90', '  level: $level');

/// The t0 snapshot of a passing pair: playing for 20 s, AudioFlinger already
/// counting 2 underruns on the app's track (only differences matter).
Map<String, String> passingT0() => {
  'time.txt': timeTxt(epochMs: kEpoch0, uptimeS: '1000.00', local: kLocal0),
  'pid.txt': '$kPlayerPid\n',
  'proc_stat.txt': procStat(utime: 1000, stime: 500),
  'task_stat.txt': taskStats(),
  'audio_flinger.txt': activeAudioFlinger(underruns: 2),
  'fstat.txt': fstatLine(
    epochMs: kEpoch0 - 5000,
    playUs: 20000000,
    renderUs: 200000,
    frames: 960000,
  ),
  'services.txt': audioServiceServices(),
  'battery.txt': fixture('battery.txt'),
};

/// The t1 snapshot of a passing pair, 600 s later: 1 % render time, 2 % of a
/// core, every counter unchanged, no frame deficit, the 21.6 h unplugged
/// window of the real history after t0, and a charge counter 338.6 mAh and
/// 3 % lower than t0's.
Map<String, String> passingT1() => {
  'time.txt': timeTxt(epochMs: kEpoch1, uptimeS: '1600.00', local: kLocal1),
  'pid.txt': '$kPlayerPid\n',
  'proc_stat.txt': procStat(utime: 2000, stime: 700),
  'task_stat.txt': taskStats(extraTicks: {10630: 900, 10696: 300}),
  'audio_flinger.txt': activeAudioFlinger(underruns: 2),
  'fstat.txt': t1Fstat(),
  'services.txt': audioServiceServices(),
  'battery.txt': batteryTxt(chargeCounter: 4672042, level: 87),
  'batterystats_history.txt': fixture('batterystats_history_anchored.txt'),
};

/// [passingT1] with a render ratio of [pct] % and enough process CPU that
/// the CPU cross-check still holds.
Map<String, String> t1AtRenderPct(int pct, {int underruns = 0}) => passingT1()
  ..['fstat.txt'] = t1Fstat(
    renderUs: 200000 + kWallSeconds * pct * 10000,
    underruns: underruns,
  )
  ..['proc_stat.txt'] = procStat(utime: 1000 + kWallSeconds * pct, stime: 700);

/// A `dumpsys batterystats --history` made of [entries], each a history line
/// without its two leading spaces.
String historyOf(List<String> entries) => [
  'Battery History [Format: 2] (1% used, 41KB used of 4096KB, 17 strings '
      'using 1KB):',
  for (final entry in entries) '  $entry',
  '',
].join('\n');

/// The passing t1 `FSTAT` line, with any field overridden.
String t1Fstat({
  int epochMs = kEpoch1 - 5000,
  int rate = 48000,
  int playUs = 20000000 + kWallSeconds * 1000000,
  int renderUs = 200000 + kWallSeconds * 10000,
  int frames = 960000 + kWallSeconds * 48000,
  int underruns = 0,
  int starvedUs = 0,
  int overlaps = 0,
  int faults = 0,
}) => fstatLine(
  epochMs: epochMs,
  rate: rate,
  playUs: playUs,
  renderUs: renderUs,
  frames: frames,
  underruns: underruns,
  starvedUs: starvedUs,
  overlaps: overlaps,
  faults: faults,
);

Report reportOf(
  Map<String, String> t0,
  Map<String, String> t1, {
  bool battery = false,
  bool expectForeground = false,
}) => buildReport(
  Snapshot('t0', t0),
  Snapshot('t1', t1),
  ReportOptions(battery: battery, expectForeground: expectForeground),
);
