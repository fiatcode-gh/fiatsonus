import 'package:flutter_test/flutter_test.dart';

import '../../tool/device/src/report.dart';
import 'fixtures.dart';
import 'snapshot_pair.dart';

void main() {
  test('a passing pair', () {
    final report = reportOf(
      passingT0(),
      passingT1(),
      battery: true,
      expectForeground: true,
    );

    expect(report.failures, isEmpty);
    expect(report.passed, isTrue);
    final r = report.results;
    expect(r['wall_s'], '600.000');
    expect(r['process_cpu_pct'], '2.00');
    expect(
      r['top_threads'],
      startsWith('VivoPivotZHP:1.50,FreezerManager_:0.50,'),
    );
    expect(r['top_threads']!.split(','), hasLength(5));
    expect(r['render_ratio_pct'], '1.00');
    expect(r['max_render_us'], '900');
    expect(r['audio_s'], '600.000');
    expect(r['deficit_ms'], '0.0');
    expect(r['underruns'], '0');
    expect(r['starved_us'], '0');
    expect(r['overlaps'], '0');
    expect(r['faults'], '0');
    expect(r['af_underruns'], '0');
    expect(r['engine_rate'], '48000');
    expect(r['device_rate'], '48000');
    expect(r['foreground'], 'true');
    expect(
      r['battery_window'],
      '2026-11-21T12:17:54.666..2026-11-22T09:55:24.736',
    );
    expect(r['battery_mah'], '340');
    expect(r['battery_hours'], '21.625');
    expect(r['battery_mah_per_h'], '15.7');
    expect(r['battery_level_drop'], '3');
    expect(r['battery_counter_mah'], '338.6');
    expect(r['battery_counter_level_drop'], '3');
  });

  test('the output is RESULT lines, one CPU line, then PASS', () {
    final lines = reportOf(passingT0(), passingT1()).format().split('\n');

    expect(lines.first, 'RESULT wall_s=600.000');
    expect(
      lines.sublist(0, lines.length - 2),
      everyElement(startsWith('RESULT ')),
    );
    expect(lines[lines.length - 2], startsWith('CPU '));
    expect(lines.last, 'PASS');
  });

  group('CPU line', () {
    test('a render ratio at 17 % passes functionally with CPU MISS', () {
      final report = reportOf(passingT0(), t1AtRenderPct(17));

      expect(report.failures, isEmpty);
      final lines = report.format().split('\n');
      expect(lines.sublist(lines.length - 2), [
        'CPU MISS render_ratio_pct=17.00 limit_pct=5.00',
        'PASS',
      ]);
    });

    test('a render ratio at 1 % is CPU PASS', () {
      final lines = reportOf(passingT0(), passingT1()).format().split('\n');

      expect(
        lines[lines.length - 2],
        'CPU PASS render_ratio_pct=1.00 limit_pct=5.00',
      );
    });

    test('a pair without an FSTAT line is CPU UNKNOWN and fails', () {
      final report = reportOf(passingT0(), passingT1()..['fstat.txt'] = '');

      final lines = report.format().split('\n');
      expect(lines[lines.length - 2], 'CPU UNKNOWN');
      expect(lines.last, startsWith('FAIL '));
    });
  });

  group('fails with one reason when', () {
    void expectOnly(
      Map<String, String> t1,
      String reason, {
      Map<String, String>? t0,
      bool battery = false,
      bool expectForeground = false,
    }) {
      final report = reportOf(
        t0 ?? passingT0(),
        t1,
        battery: battery,
        expectForeground: expectForeground,
      );
      expect(report.failures, [startsWith(reason)]);
      expect(report.passed, isFalse);
    }

    for (final (field, edit) in <(String, String Function())>[
      ('underruns 1', () => t1Fstat(underruns: 1)),
      ('starved_us 4000', () => t1Fstat(starvedUs: 4000)),
      ('overlaps 1', () => t1Fstat(overlaps: 1)),
      ('faults 2', () => t1Fstat(faults: 2)),
    ]) {
      test('$field is not 0', () {
        expectOnly(passingT1()..['fstat.txt'] = edit(), '$field != 0');
      });
    }

    test('AudioFlinger counted underruns', () {
      final t1 = passingT1()
        ..['audio_flinger.txt'] = activeAudioFlinger(underruns: 5);
      expectOnly(t1, 'af_underruns 3 != 0');
    });

    test('a track that is new at t1 counts from 0', () {
      final t0 = passingT0()
        ..['audio_flinger.txt'] = fixture('audio_flinger_idle.txt');
      expectOnly(t0: t0, passingT1(), 'af_underruns 2 != 0');
    });

    test('the frame deficit exceeds its bound', () {
      final t1 = passingT1()
        ..['fstat.txt'] = t1Fstat(
          frames: 960000 + kWallSeconds * 48000 - 24000,
        );
      expectOnly(t1, 'deficit_ms 500.0 exceeds 420.0');
    });

    test('the process used less CPU than half the render ratio', () {
      final t1 = passingT1()
        ..['proc_stat.txt'] = procStat(utime: 1050, stime: 550);
      expectOnly(t1, 'process_cpu_pct 0.17 < 0.5 × render_ratio_pct 1.00');
    });

    test('the engine rate is not the device rate', () {
      final t1 = passingT1()
        ..['fstat.txt'] = t1Fstat(
          rate: 44100,
          frames: 960000 + kWallSeconds * 44100,
        );
      expectOnly(t1, 'engine_rate 44100 != device_rate 48000');
    });

    test('the FSTAT line is more than 30 s old', () {
      final t1 = passingT1()..['fstat.txt'] = t1Fstat(epochMs: kEpoch1 - 31000);
      expectOnly(t1, 'FSTAT line of t1 is 31.0 s older than the snapshot');
    });

    test('the service is not in the foreground and that is expected', () {
      final t1 = passingT1()
        ..['services.txt'] = audioServiceServices(foreground: false);
      expectOnly(
        t1,
        'AudioService not in the foreground at t1',
        expectForeground: true,
      );
    });

    test('a value cannot be parsed', () {
      final t1 = passingT1()..['proc_stat.txt'] = '24608 (fiatsonus) S 1';
      expectOnly(t1, 'unparsable t1/proc_stat.txt');
    });

    test('a file is missing', () {
      final t0 = passingT0()..remove('time.txt');
      expectOnly(t0: t0, passingT1(), 't0/time.txt missing');
    });
  });

  test('the foreground is only a result without --expect-foreground', () {
    final t1 = passingT1()
      ..['services.txt'] = audioServiceServices(foreground: false);

    final report = reportOf(passingT0(), t1);

    expect(report.failures, isEmpty);
    expect(report.results['foreground'], 'false');
  });

  test('a different pid at t0 and t1', () {
    final t1 = passingT1()..['pid.txt'] = '${kPlayerPid + 1}\n';

    expect(
      reportOf(passingT0(), t1).failures,
      contains('pid changed: $kPlayerPid at t0, ${kPlayerPid + 1} at t1'),
    );
  });

  test('a missing pid', () {
    final t1 = passingT1()..['pid.txt'] = '';

    expect(
      reportOf(passingT0(), t1).failures,
      contains('no pid in t1/pid.txt'),
    );
  });

  test('a missing FSTAT line', () {
    final t1 = passingT1()..['fstat.txt'] = '';

    expect(
      reportOf(passingT0(), t1).failures,
      contains('no FSTAT line in t1/fstat.txt'),
    );
  });

  test('every reason is reported', () {
    final t1 = passingT1()
      ..['fstat.txt'] = t1Fstat(underruns: 1, faults: 1)
      ..['audio_flinger.txt'] = activeAudioFlinger(underruns: 3);

    final report = reportOf(passingT0(), t1);

    expect(report.failures, [
      'underruns 1 != 0',
      'faults 1 != 0',
      'af_underruns 1 != 0',
    ]);
    expect(
      report.format().split('\n').last,
      'FAIL underruns 1 != 0; faults 1 != 0; af_underruns 1 != 0',
    );
  });

  group('battery', () {
    final anchored = fixture('batterystats_history_anchored.txt');
    const windowEnd =
        '  11-22 09:55:24.736 087 plug=ac volt=4222 charge=4670 '
        '+wake_lock=u0a238:"QcrilOemhookMsgTunnel" +plugged\n';

    Report batteryReport({
      String? history,
      String local0 = kLocal0,
      String local1 = kLocal1,
    }) {
      final t0 = passingT0()
        ..['time.txt'] = timeTxt(
          epochMs: kEpoch0,
          uptimeS: '1000.00',
          local: local0,
        );
      final t1 = passingT1()
        ..['time.txt'] = timeTxt(
          epochMs: kEpoch1,
          uptimeS: '1600.00',
          local: local1,
        );
      if (history != null) t1['batterystats_history.txt'] = history;
      return reportOf(t0, t1, battery: true);
    }

    test('a window that ended before t0 is not reported', () {
      final report = batteryReport(
        history: fixture('batterystats_history_unplug.txt'),
        local0: '2026-11-21 10:00:00',
      );

      expect(report.failures, contains('no unplugged window after t0'));
      expect(report.results, isNot(contains('battery_mah')));
      expect(report.results, isNot(contains('battery_window')));
    });

    test('the window after t0 is reported, not an older one', () {
      final report = batteryReport(history: anchored);

      expect(report.failures, isEmpty);
      final r = report.results;
      expect(
        r['battery_window'],
        '2026-11-21T12:17:54.666..2026-11-22T09:55:24.736',
      );
      expect(r['battery_mah'], '340');
      expect(r['battery_hours'], '21.625');
      expect(r['battery_mah_per_h'], '15.7');
      expect(r['battery_level_drop'], '3');
    });

    test('a last history line more than 600 s before t1 is stale', () {
      // The last line of the history is 11-22 10:02:05.261.
      final stale = batteryReport(local1: '2026-11-22 10:12:06');
      final live = batteryReport(local1: '2026-11-22 10:12:05');

      expect(stale.failures, ['battery history is stale or on another clock']);
      expect(live.failures, isEmpty);
    });

    test('a second unplug after t0 fails', () {
      final report = batteryReport(
        history: anchored.replaceFirst(
          windowEnd,
          '$windowEnd  11-22 09:58:10.000 087 status=discharging plug=none '
          'volt=4324 -plugged -charging\n',
        ),
      );

      expect(report.failures, [
        'more than one unplugged window between t0 and t1',
      ]);
    });

    test('an unplug without a replug fails', () {
      final report = batteryReport(
        history: anchored.replaceFirst(windowEnd, ''),
      );

      expect(report.failures, ['the unplugged window has no end']);
      expect(report.results, isNot(contains('battery_mah')));
    });

    test('a restated plug=none inside the window changes nothing', () {
      final report = batteryReport(
        history: anchored.replaceFirst(
          '  11-21 23:20:02.883',
          '  11-21 20:00:00.000 090 status=discharging plug=none volt=4324 '
              '-plugged -charging\n  11-21 23:20:02.883',
        ),
      );

      expect(report.failures, isEmpty);
      expect(
        report.results['battery_window'],
        '2026-11-21T12:17:54.666..2026-11-22T09:55:24.736',
      );
      expect(report.results['battery_mah'], '340');
    });

    test('a history across the new year resolves against t1', () {
      final report = batteryReport(
        history: historyOf([
          '12-31 23:40:00.000 090 plug=ac volt=4222 charge=4670 +plugged',
          '12-31 23:55:00.000 090 status=discharging plug=none volt=4291 '
              '-plugged -charging',
          '01-01 00:30:00.000 089 charge=4600',
          '01-01 01:00:00.000 088 plug=usb volt=4084 charge=4550 +plugged',
          '01-01 01:04:00.000 088 stats=0:"dump"',
        ]),
        local0: '2026-12-31 23:50:00',
        local1: '2027-01-01 01:05:00',
      );

      expect(report.failures, isEmpty);
      expect(
        report.results['battery_window'],
        '2026-12-31T23:55:00.000..2027-01-01T01:00:00.000',
      );
      expect(report.results['battery_mah'], '120');
      expect(report.results['battery_level_drop'], '2');
    });

    test('the counter results come from battery.txt', () {
      final report = batteryReport(local1: '2026-11-22 11:00:00');

      expect(report.failures, ['battery history is stale or on another clock']);
      expect(report.results['battery_counter_mah'], '338.6');
      expect(report.results['battery_counter_level_drop'], '3');
    });

    test('a battery.txt without Charge counter fails naming the file', () {
      final t1 = passingT1()
        ..['battery.txt'] = fixture('battery.txt')
            .replaceFirst('  Charge counter: 5010642\n', '');

      final report = reportOf(passingT0(), t1, battery: true);

      expect(report.failures, [startsWith('unparsable t1/battery.txt')]);
      expect(report.results, isNot(contains('battery_counter_mah')));
    });

    test('a time.txt without local fails only under --battery', () {
      final t0 = passingT0()
        ..['time.txt'] = timeTxt(epochMs: kEpoch0, uptimeS: '1000.00');

      expect(reportOf(t0, passingT1(), battery: true).failures, [
        'no local= in t0/time.txt',
      ]);
      expect(reportOf(t0, passingT1()).failures, isEmpty);
    });
  });
}
