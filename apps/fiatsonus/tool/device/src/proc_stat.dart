/// One `/proc/<pid>/stat` or `/proc/<pid>/task/<tid>/stat` line.
class ProcStat {
  const ProcStat({
    required this.pid,
    required this.comm,
    required this.utime,
    required this.stime,
  });

  final int pid;
  final String comm;

  /// User and system CPU time in clock ticks (`CLK_TCK`, 100 on the phone).
  final int utime;
  final int stime;

  int get cpuTicks => utime + stime;
}

/// Parses one stat line. The comm field may hold spaces and `)`, so it runs
/// to the last `)` of the line.
ProcStat parseProcStat(String line) {
  final open = line.indexOf('(');
  final close = line.lastIndexOf(')');
  if (open < 0 || close < open) {
    throw FormatException('no "(comm)" field', line);
  }
  final pid = int.tryParse(line.substring(0, open).trim());
  // Fields after the comm start at field 3 (state); utime and stime are
  // fields 14 and 15.
  final rest = line.substring(close + 1).trim().split(RegExp(r'\s+'));
  final utime = rest.length > 12 ? int.tryParse(rest[11]) : null;
  final stime = rest.length > 12 ? int.tryParse(rest[12]) : null;
  if (pid == null || utime == null || stime == null) {
    throw FormatException('no pid, utime or stime', line);
  }
  return ProcStat(
    pid: pid,
    comm: line.substring(open + 1, close),
    utime: utime,
    stime: stime,
  );
}

/// Parses every non-empty line of [text] as a stat line.
List<ProcStat> parseProcStats(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty) parseProcStat(line),
];
