import '../../tool/device/src/report.dart';
import 'fixtures.dart';

const kEpoch0 = 1795226960000;
const kWallSeconds = 600;
const kEpoch1 = kEpoch0 + kWallSeconds * 1000;

/// The t0 snapshot of a passing pair: playing for 20 s, AudioFlinger already
/// counting 2 underruns on the app's track (only differences matter).
Map<String, String> passingT0() => {
  'time.txt': 'epoch_ms=$kEpoch0\nuptime_s=1000.00\n',
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
};

/// The t1 snapshot of a passing pair, 600 s later: 1 % render time, 2 % of a
/// core, every counter unchanged, no frame deficit, a 22 h unplugged window.
Map<String, String> passingT1() => {
  'time.txt': 'epoch_ms=$kEpoch1\nuptime_s=1600.00\n',
  'pid.txt': '$kPlayerPid\n',
  'proc_stat.txt': procStat(utime: 2000, stime: 700),
  'task_stat.txt': taskStats(extraTicks: {10630: 900, 10696: 300}),
  'audio_flinger.txt': activeAudioFlinger(underruns: 2),
  'fstat.txt': t1Fstat(),
  'services.txt': audioServiceServices(),
  'batterystats_history.txt': fixture('batterystats_history_unplug.txt'),
  'batterystats_app.txt': fixture('batterystats_app_chrome.txt'),
};

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
