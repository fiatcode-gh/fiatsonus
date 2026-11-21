/// The first unplugged stretch of a `dumpsys batterystats --history`.
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

// `  MM-DD HH:MM:SS.mmm <rest>`; history lines carry no year.
final _entry = RegExp(r'^\s+(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d{3}) (.*)$');
final _time = RegExp(r'^TIME: (\d{4})-');
final _level = RegExp(r'^(\d{3})(?:\s|$)');
final _plug = RegExp(r'(?:^|\s)plug=(\S+)');
final _charge = RegExp(r'(?:^|\s)charge=(\d+)');

/// From the first `plug=none` line to the next line whose `plug=` is not
/// `none`. Charge and level carry forward from the last line that states
/// them; each boundary line's own values count.
UnpluggedWindow parseUnpluggedWindow(String history) {
  // The year comes from `TIME:` lines; a month that goes back means a new
  // year. 2000 (a leap year) stands in until a `TIME:` line is seen.
  var year = 2000;
  var month = 0;
  int? level;
  int? charge;
  DateTime? start;
  int? startCharge;
  int? startLevel;

  for (final line in history.split('\n')) {
    final entry = _entry.firstMatch(line);
    if (entry == null) continue;
    final rest = entry.group(7)!;
    final lineMonth = int.parse(entry.group(1)!);
    final time = _time.firstMatch(rest);
    if (time != null) {
      year = int.parse(time.group(1)!);
    } else if (lineMonth < month) {
      year++;
    }
    month = lineMonth;
    final levelMatch = _level.firstMatch(rest);
    if (levelMatch == null) continue;
    level = int.parse(levelMatch.group(1)!);
    final chargeMatch = _charge.firstMatch(rest);
    if (chargeMatch != null) charge = int.parse(chargeMatch.group(1)!);
    final plug = _plug.firstMatch(rest)?.group(1);
    if (plug == null || (start == null) != (plug == 'none')) continue;

    final at = DateTime.utc(
      year,
      lineMonth,
      int.parse(entry.group(2)!),
      int.parse(entry.group(3)!),
      int.parse(entry.group(4)!),
      int.parse(entry.group(5)!),
      int.parse(entry.group(6)!),
    );
    if (charge == null) {
      throw FormatException('no charge= at or before the line', line);
    }
    if (start == null) {
      start = at;
      startCharge = charge;
      startLevel = level;
    } else {
      return UnpluggedWindow(
        start: start,
        end: at,
        startChargeMah: startCharge!,
        endChargeMah: charge,
        startLevel: startLevel!,
        endLevel: level,
      );
    }
  }
  throw FormatException(
    start == null
        ? 'no plug=none line'
        : 'no plug= line other than none after the unplug',
  );
}

final _estimateUid = RegExp(r'^  UID (\S+): ([0-9.]+)');

/// The total of [uid]'s line under "Estimated power use" in
/// `dumpsys batterystats --charged <package>`, or null when it has none.
double? parseAppEstimateMah(String text, String uid) {
  var inEstimates = false;
  for (final line in text.split('\n')) {
    if (line.startsWith('  Estimated power use')) {
      inEstimates = true;
      continue;
    }
    if (!inEstimates) continue;
    final match = _estimateUid.firstMatch(line);
    if (match != null) {
      if (match.group(1) == uid) return double.parse(match.group(2)!);
    } else if (RegExp(r'^  \S').hasMatch(line)) {
      return null;
    }
  }
  return null;
}
