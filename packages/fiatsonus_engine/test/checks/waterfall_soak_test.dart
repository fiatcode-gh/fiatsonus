// Long run (PLAN 4.6, N11): the AOT-compiled soak tool renders 8 simulated
// hours per rate with the VM's GC log on. Run with `dart test -t soak`.
@Tags(['soak'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'soundscape_checks.dart';

const _hours = 8;
final _gcLine = RegExp('Scavenge|MarkSweep|MarkCompact');

void main() {
  late Directory tmp;
  late String exe;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('waterfall_soak_test');
    exe = '${tmp.path}/soak';
    final r = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'tool/soak.dart',
      '-o',
      exe,
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  for (final rate in checkRates) {
    test(
      '$rate Hz: $_hours hours steady, no GC, stable RSS and loudness',
      () async {
        final r = await Process.run(
          exe,
          ['--hours', '$_hours', '--rate', '$rate'],
          environment: {'DART_VM_OPTIONS': '--verbose_gc'},
        );
        final err = (r.stderr as String).split('\n');
        expect(r.exitCode, 0, reason: r.stderr as String);

        final begin = err.indexOf('SOAK-STEADY-BEGIN');
        final end = err.indexOf('SOAK-STEADY-END');
        final garbage = err.indexOf('SOAK-GARBAGE-DONE');
        expect(begin, greaterThanOrEqualTo(0), reason: 'begin marker');
        expect(end, greaterThan(begin), reason: 'end marker after begin');
        expect(garbage, greaterThan(end), reason: 'garbage marker after end');

        int gcLines(int from, int to) =>
            err.sublist(from + 1, to).where(_gcLine.hasMatch).length;
        final steadyGc = gcLines(begin, end);
        final garbageGc = gcLines(end, garbage);
        final summary = (r.stdout as String).trim().split('\n').single;
        // The measured values belong in the run's log, pass or fail.
        print('$summary\nGC lines: steady $steadyGc, garbage $garbageGc');
        expect(steadyGc, 0, reason: 'GC in the steady phase');
        expect(garbageGc, greaterThan(0), reason: 'GC log must be on');

        final json = jsonDecode(summary) as Map<String, Object?>;
        final rss = (json['rssBytes']! as List<Object?>).cast<int>();
        final lufs = (json['lufs']! as List<Object?>).cast<num>();
        expect(rss, hasLength(_hours * 6));
        expect(lufs, hasLength(_hours * 6));
        final rssSpread =
            rss.reduce((a, b) => a > b ? a : b) -
            rss.reduce((a, b) => a < b ? a : b);
        expect(rssSpread, lessThanOrEqualTo(4 * 1024 * 1024), reason: 'RSS');
        expect(json['maxVoices'], lessThanOrEqualTo(64));
        expect(json['peak'], lessThanOrEqualTo(maxLegalPeak));
        expect(json['faultBlocks'], 0);
        expect(lufs.first, inInclusiveRange(-21.0, -19.0));
        for (var i = 0; i < lufs.length; i++) {
          expect(lufs[i], closeTo(lufs.first, 0.5), reason: 'window $i');
        }
      },
    );
  }
}
