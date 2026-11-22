/// The unplugged stretch of a `dumpsys batterystats --history` between two
/// snapshots. Stamps are the phone's local clock, held as UTC values so that
/// differences are plain arithmetic.
class UnpluggedWindow {
  const UnpluggedWindow({
    required this.start,
    required this.end,
    required this.startChargeMah,
    required this.endChargeMah,
    required this.startLevel,
    required this.endLevel,
  });

  final DateTime start;
  final DateTime end;
  final int startChargeMah;
  final int endChargeMah;
  final int startLevel;
  final int endLevel;

  int get mah => startChargeMah - endChargeMah;
  double get seconds => end.difference(start).inMicroseconds / 1e6;
  double get hours => seconds / 3600;
  double get mahPerHour => mah / hours;
  int get levelDrop => startLevel - endLevel;
}

/// The window found by [findUnpluggedWindow], or null, and the reasons the
/// history cannot be trusted for a battery measurement.
class BatteryHistory {
  const BatteryHistory(this.window, this.failures);

  final UnpluggedWindow? window;
  final List<String> failures;
}

/// How far a history line may lie after t1's local clock, and how long the
/// history may have been silent before it.
const _maxAheadSeconds = 120;
const _maxSilentSeconds = 600;

// `  MM-DD HH:MM:SS.mmm <rest>`; history lines carry no year.
final _entry = RegExp(r'^\s+(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d{3}) (.*)$');
final _level = RegExp(r'^(\d{3})(?:\s|$)');
final _plug = RegExp(r'(?:^|\s)plug=(\S+)');
final _charge = RegExp(r'(?:^|\s)charge=(\d+)');

/// The single unplugged window between [t0] and [t1], both the phone's local
/// clock as UTC values.
///
/// A line's year is the latest one that puts it no later than [t1] + 120 s.
/// The window starts at the first `plug=none` line stamped at or after [t0]
/// and ends at the next line whose `plug=` is not `none`; a restated
/// `plug=none` inside it changes nothing. Charge and level carry forward from
/// the last line that states them; each boundary line's own values count.
/// The last stamped line must lie within 600 s before [t1].
BatteryHistory findUnpluggedWindow(
  String history, {
  required DateTime t0,
  required DateTime t1,
}) {
  final limit = t1.add(const Duration(seconds: _maxAheadSeconds));
  final failures = <String>[];
  DateTime? last;
  int? level;
  int? charge;
  DateTime? start;
  DateTime? end;
  int? startCharge;
  int? endCharge;
  int? startLevel;
  int? endLevel;
  var moreWindows = false;

  for (final line in history.split('\n')) {
    final entry = _entry.firstMatch(line);
    if (entry == null) continue;
    final at = _resolveYear(entry, limit);
    if (at == null) continue;
    if (last == null || at.isAfter(last)) last = at;

    final rest = entry.group(7)!;
    final levelMatch = _level.firstMatch(rest);
    if (levelMatch == null) continue;
    level = int.parse(levelMatch.group(1)!);
    final chargeMatch = _charge.firstMatch(rest);
    if (chargeMatch != null) charge = int.parse(chargeMatch.group(1)!);
    final plug = _plug.firstMatch(rest)?.group(1);
    if (plug == null || at.isBefore(t0)) continue;

    if (start == null) {
      if (plug != 'none') continue;
      start = at;
      startCharge = charge;
      startLevel = level;
    } else if (end == null) {
      if (plug == 'none') continue;
      end = at;
      endCharge = charge;
      endLevel = level;
    } else if (plug == 'none') {
      moreWindows = true;
    }
  }

  if (last == null ||
      last.isBefore(t1.subtract(const Duration(seconds: _maxSilentSeconds)))) {
    failures.add('battery history is stale or on another clock');
  }
  if (start == null) {
    failures.add('no unplugged window after t0');
  } else if (end == null) {
    failures.add('the unplugged window has no end');
  } else if (moreWindows) {
    failures.add('more than one unplugged window between t0 and t1');
  }
  if (start == null || end == null || moreWindows) {
    return BatteryHistory(null, failures);
  }
  if (startCharge == null || endCharge == null) {
    failures.add('no charge= at or before the unplug in the battery history');
    return BatteryHistory(null, failures);
  }
  return BatteryHistory(
    UnpluggedWindow(
      start: start,
      end: end,
      startChargeMah: startCharge,
      endChargeMah: endCharge,
      startLevel: startLevel!,
      endLevel: endLevel!,
    ),
    failures,
  );
}

/// The stamp of [entry] in the latest year that puts it no later than
/// [limit]; null for a date no year has (such as 02-30).
DateTime? _resolveYear(RegExpMatch entry, DateTime limit) {
  final [month, day, hour, minute, second, milli] = [
    for (var g = 1; g <= 6; g++) int.parse(entry.group(g)!),
  ];
  // Four years back always reach a 02-29.
  for (var year = limit.year; year >= limit.year - 4; year--) {
    final at = DateTime.utc(year, month, day, hour, minute, second, milli);
    if (at.month != month || at.day != day) continue;
    if (!at.isAfter(limit)) return at;
  }
  return null;
}
