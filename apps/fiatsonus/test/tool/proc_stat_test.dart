import 'package:flutter_test/flutter_test.dart';

import '../../tool/device/src/proc_stat.dart';
import 'fixtures.dart';

void main() {
  test('utime and stime of the captured system_server stat', () {
    final stat = parseProcStat(fixture('proc_stat.txt').trim());

    expect(stat.pid, 2883);
    expect(stat.comm, 'system_server');
    expect(stat.utime, 615442);
    expect(stat.stime, 412202);
    expect(stat.cpuTicks, 615442 + 412202);
  });

  test('a comm holding spaces and ")" runs to the last ")"', () {
    final stat = parseProcStat(
      '77 (a) b (c)) S 1 1 0 0 -1 4194560 10 0 0 0 31 7 0 0 20 0 1 0 5 0 0',
    );

    expect(stat.comm, 'a) b (c)');
    expect(stat.utime, 31);
    expect(stat.stime, 7);
  });

  test('every captured task line parses', () {
    final stats = parseProcStats(fixture('task_stat.txt'));

    expect(stats, hasLength(544));
    expect(stats.first.comm, 'VivoPivotZHP');
  });

  test('a truncated line is a parse error', () {
    expect(
      () => parseProcStat('77 (x) S 1 1 0'),
      throwsA(isA<FormatException>()),
    );
  });
}
