import 'dart:io';

import 'package:fiatsonus_engine/offline.dart';
import 'package:test/test.dart';

const List<String> _waterfallFiles = [
  '01-defaults.wav',
  '02-height-0.wav',
  '03-height-1.wav',
  '04-spray-0.wav',
  '05-spray-1.wav',
  '06-width-0.wav',
  '07-width-1.wav',
  '08-distance-0.wav',
  '09-distance-1.wav',
  '10-sweep-height.wav',
  '11-sweep-spray.wav',
  '12-sweep-width.wav',
  '13-sweep-distance.wav',
  '14-defaults-long.wav',
];

const RenderSummary _summary = RenderSummary(
  frames: 1,
  peak: 11500,
  lufs: -19.93,
  faultBlocks: 0,
  endedSilent: true,
  elapsed: Duration(seconds: 1),
  sampleRate: 48000,
);

/// The `- [ ]` lines of the Acceptance list in the doc's waterfall section.
List<String> _docAcceptance() {
  final doc = File('../../docs/procedural-ambient-sound-engine-design.md')
      .readAsStringSync();
  final start = doc.indexOf('## Soundscape: waterfall');
  final next = doc.indexOf('\n## ', start + 1);
  final section = doc.substring(start, next < 0 ? doc.length : next);
  final acceptance = section.substring(section.indexOf('**Acceptance**'));
  return [
    for (final line in acceptance.split('\n'))
      if (line.startsWith('- [ ] ')) line.substring('- [ ] '.length).trim(),
  ];
}

void main() {
  group('listeningSet', () {
    test('waterfall gives 14 items in order with their jobs', () {
      final items = listeningSet('waterfall');
      expect([for (final i in items) i.fileName], _waterfallFiles);
      expect(
        [for (final i in items) i.job.seconds],
        [
          60,
          for (var i = 0; i < 8; i++) 30,
          for (var i = 0; i < 4; i++) 68,
          600,
        ],
      );
      for (final i in items) {
        expect(i.job.scapeId, 'waterfall');
        expect(i.job.sampleRate, 48000);
        expect(i.job.seed, 1);
      }
      ListeningItem named(String f) =>
          items.singleWhere((i) => i.fileName == f);
      expect(named('02-height-0.wav').job.params, {'height': 0.0});
      expect(named('02-height-0.wav').job.sweepParam, isNull);
      expect(named('09-distance-1.wav').job.params, {'distance': 1.0});
      expect(named('10-sweep-height.wav').job.sweepParam, 'height');
      expect(named('10-sweep-height.wav').job.params, isEmpty);
      for (final f in ['01-defaults.wav', '14-defaults-long.wav']) {
        expect(named(f).job.params, isEmpty);
        expect(named(f).job.sweepParam, isNull);
      }
    });

    test('longSeconds 0 leaves the long file out', () {
      final items = listeningSet('waterfall', longSeconds: 0);
      expect(items, hasLength(13));
      expect(items.last.fileName, '13-sweep-distance.wav');
    });

    test('bad arguments throw ArgumentError', () {
      expect(
        () => listeningSet('waterfall', longSeconds: 3),
        throwsArgumentError,
      );
      expect(
        () => listeningSet('waterfall', longSeconds: double.nan),
        throwsArgumentError,
      );
      expect(() => listeningSet('nope'), throwsArgumentError);
    });

    test('rate and seed reach every job', () {
      for (final i in listeningSet('waterfall', sampleRate: 44100, seed: 9)) {
        expect(i.job.sampleRate, 44100);
        expect(i.job.seed, 9);
      }
    });
  });

  group('listeningReadme', () {
    final items = listeningSet('waterfall');
    final readme = listeningReadme('waterfall', items, [
      for (final _ in items) _summary,
    ]);
    final lines = readme.split('\n');

    test('header, file lines and listening notes', () {
      expect(lines[0], 'fiatsonus listening set: waterfall');
      expect(lines[1], startsWith('Seed 1, 48000 Hz, 16-bit stereo.'));
      expect(
        lines.singleWhere((l) => l.startsWith('Files')),
        contains('height 0.5, spray 0.4, width 0.7, distance 0.4'),
      );
      for (final i in items) {
        final matching = lines.where(
          (l) =>
              l.contains(i.fileName) &&
              l.contains('-19.9 LUFS') &&
              l.contains('-9.1 dBFS'),
        );
        expect(matching, hasLength(1), reason: i.fileName);
      }
      expect(
        lines.singleWhere((l) => l.contains('600 s')),
        contains('14-defaults-long.wav'),
      );
      for (final note in [
        '  - With headphones, then on a phone speaker.',
        '  - At low volume: bad textures stand out more there.',
        '  - Play the long file without watching the screen. '
            'Note anything that repeats or sticks out.',
        '  [ ] No click or jump in any sweep file.',
        '  [ ] No audible repeat in the long file.',
      ]) {
        expect(lines, contains(note));
      }
    });

    test('file lines align', () {
      final fileLines = [
        for (final l in lines)
          if (RegExp(r'^  \d\d-').hasMatch(l)) l,
      ];
      expect(fileLines, hasLength(14));
      for (final col in ['LUFS', 'peak']) {
        expect(
          {for (final l in fileLines) l.indexOf(col)},
          hasLength(1),
          reason: col,
        );
      }
    });

    test('sign-off questions are the doc Acceptance list word for word', () {
      final questions = _docAcceptance();
      expect(questions, hasLength(3));
      for (final q in questions) {
        expect(readme, contains(q));
      }
      final start = lines.indexWhere((l) => l.startsWith('Sign-off:'));
      final end = lines.indexWhere((l) => l.startsWith('Also note'));
      expect(start, greaterThan(0));
      expect(
        lines.sublist(start + 1, end).where((l) => l.startsWith('  [ ] ')),
        hasLength(questions.length),
      );
    });

    test('every file name it mentions is an item', () {
      final names = {for (final i in items) i.fileName};
      final mentioned = RegExp(r'\d\d-[a-z0-9-]+\.wav')
          .allMatches(readme)
          .map((m) => m.group(0)!);
      expect(mentioned, isNotEmpty);
      for (final n in mentioned) {
        expect(names, contains(n));
      }
    });

    test('mismatched or empty lists throw ArgumentError', () {
      expect(
        () => listeningReadme('waterfall', items, [
          for (var i = 0; i < 13; i++) _summary,
        ]),
        throwsArgumentError,
      );
      expect(() => listeningReadme('waterfall', [], []), throwsArgumentError);
    });
  });
}
