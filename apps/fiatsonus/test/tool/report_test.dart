import 'package:flutter_test/flutter_test.dart';

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
    expect(r['battery_mah'], '388');
    expect(r['battery_hours'], '22.133');
    expect(r['battery_mah_per_h'], '17.5');
    expect(r['battery_level_drop'], '6');
    expect(r['battery_app_estimate_mah'], 'n/a');
  });

  test('the app estimate is read for the uid of the app process', () {
    final t1 = passingT1()
      ..['services.txt'] = audioServiceServices(uid: 'u0a206');

    final report = reportOf(passingT0(), t1, battery: true);

    expect(report.results['battery_app_estimate_mah'], '23.2');
  });

  test('the output is one RESULT line per result, then PASS', () {
    final lines = reportOf(passingT0(), passingT1()).format().split('\n');

    expect(lines.first, 'RESULT wall_s=600.000');
    expect(
      lines.sublist(0, lines.length - 1),
      everyElement(startsWith('RESULT ')),
    );
    expect(lines.last, 'PASS');
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

    test('the render ratio reaches the limit', () {
      final t1 = passingT1()
        ..['fstat.txt'] = t1Fstat(renderUs: 200000 + kWallSeconds * 60000)
        ..['proc_stat.txt'] = procStat(utime: 3000, stime: 700);
      expectOnly(t1, 'render_ratio_pct 6.00 >= 5.00');
    });

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

    test('the history holds no unplugged window', () {
      final t1 = passingT1()
        ..['batterystats_history.txt'] = fixture('batterystats_history.txt');
      expectOnly(
        t1,
        'no unplugged window in t1/batterystats_history.txt',
        battery: true,
      );
    });

    test('the unplugged window is shorter than an hour', () {
      final t1 = passingT1()
        ..['batterystats_history.txt'] =
            fixture('batterystats_history_unplug.txt').replaceFirst(
              '10-22 08:40:38.615 078 plug=usb',
              '10-21 11:20:38.615 078 plug=usb',
            );
      expectOnly(t1, 'battery window 2878 s < 3600 s', battery: true);
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
}
