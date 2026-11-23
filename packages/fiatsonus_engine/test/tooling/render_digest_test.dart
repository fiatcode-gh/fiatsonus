import 'dart:convert';

import 'package:fiatsonus_engine/profiling.dart';
import 'package:test/test.dart';

DigestCase _case(String name) => digestCases.firstWhere((c) => c.name == name);

void main() {
  group('fnv1a64Hex', () {
    test('matches the reference vectors', () {
      expect(fnv1a64Hex([]), 'cbf29ce484222325');
      expect(fnv1a64Hex([0x61]), 'af63dc4c8601ec8c');
      expect(fnv1a64Hex(utf8.encode('foobar')), '85944171f73967e8');
    });
  });

  group('digestCases', () {
    test('lists 28 unique names in the plan order', () {
      final expected = [
        for (final rate in [44100, 48000])
          for (final seed in [1, 42, 20261123])
            for (final set in ['default', 'low', 'high', 'mixed'])
              'session-r$rate-s$seed-$set',
        'long-r44100-s1-default',
        'long-r48000-s1-default',
        'poolSteal-r44100-s1-default',
        'poolSteal-r48000-s1-default',
      ];
      final names = digestCases.map((c) => c.name).toList();
      expect(names, expected);
      expect(names.toSet(), hasLength(28));
      for (final c in digestCases) {
        expect(digestParamSets.containsKey(c.paramSet), isTrue, reason: c.name);
      }
    });
  });

  group('renderDigest', () {
    final first = _case('session-r48000-s1-default');
    late DigestResult base;

    setUpAll(() => base = renderDigest(first));

    test('a session renders 24 s and repeats exactly', () {
      expect(base.name, first.name);
      expect(base.frames, 24 * 48000);
      expect(base.hash, matches(RegExp(r'^[0-9a-f]{16}$')));
      final again = renderDigest(first);
      expect(again.frames, base.frames);
      expect(again.hash, base.hash);
    });

    test('the hash does not depend on how calls are chunked', () {
      final chunked = renderDigest(
        first,
        chunks: [1, 255, 256, 257, 1000, 2048, 4096, 333],
      );
      expect(chunked.frames, base.frames);
      expect(chunked.hash, base.hash);
    });

    test('frames follow the rate', () {
      final r = renderDigest(_case('session-r44100-s1-default'));
      expect(r.frames, 24 * 44100);
    });

    test('a different seed changes the hash', () {
      expect(
        renderDigest(_case('session-r48000-s42-default')).hash,
        isNot(base.hash),
      );
    });

    test('a different param set changes the hash', () {
      expect(
        renderDigest(_case('session-r48000-s1-mixed')).hash,
        isNot(base.hash),
      );
    });

    test('poolSteal steals at both rates', () {
      for (final rate in [44100, 48000]) {
        final r = renderDigest(_case('poolSteal-r$rate-s1-default'));
        expect(r.frames, 40 * 256);
        expect(r.hash, matches(RegExp(r'^[0-9a-f]{16}$')));
      }
    });
  });

  group('DigestResult', () {
    const r = DigestResult(
      'session-r48000-s1-default',
      1152000,
      '0123456789abcdef',
    );

    test('line and parse round-trip', () {
      expect(
        r.line,
        'FDIGEST v=1 case=session-r48000-s1-default frames=1152000 '
        'hash=0123456789abcdef',
      );
      final p = DigestResult.parse(r.line)!;
      expect(p.name, r.name);
      expect(p.frames, r.frames);
      expect(p.hash, r.hash);
    });

    test('parse finds the line behind a logcat prefix', () {
      final p = DigestResult.parse(
        '11-23 10:00:00.000  1234  1250 I flutter : ${r.line}',
      )!;
      expect(p.line, r.line);
    });

    test('parse rejects other lines', () {
      expect(DigestResult.parse('FBENCH done'), isNull);
      expect(DigestResult.parse('FDIGEST v=1 case=x frames=1 hash=zz'), isNull);
    });
  });

  group('compareDigests', () {
    String text(Map<String, String> hashes) =>
        [for (final e in hashes.entries) DigestResult(e.key, 10, e.value).line]
            .join('\n');

    const a = '0000000000000001';
    const b = '0000000000000002';

    test('matching texts', () {
      final c = compareDigests(
        text({'x': a, 'y': b}),
        'I flutter : ${text({'y': b})}\n${text({'x': a})}\n',
      );
      expect(c.isMatch, isTrue);
      expect(c.matched, 2);
      expect(c.differing, isEmpty);
      expect(c.missing, isEmpty);
      expect(c.extra, isEmpty);
    });

    test('a differing hash', () {
      final c = compareDigests(text({'x': a, 'y': b}), text({'x': a, 'y': a}));
      expect(c.isMatch, isFalse);
      expect(c.matched, 1);
      expect(c.differing, ['y']);
    });

    test('a missing case', () {
      final c = compareDigests(text({'x': a, 'y': b}), text({'x': a}));
      expect(c.isMatch, isFalse);
      expect(c.missing, ['y']);
      expect(c.extra, isEmpty);
    });

    test('an extra case', () {
      final c = compareDigests(text({'x': a}), text({'x': a, 'z': b}));
      expect(c.isMatch, isFalse);
      expect(c.extra, ['z']);
      expect(c.missing, isEmpty);
    });

    test('a name twice in one text is a FormatException', () {
      final twice = '${text({'x': a})}\n${text({'x': b})}';
      expect(
        () => compareDigests(twice, text({'x': a})),
        throwsFormatException,
      );
      expect(
        () => compareDigests(text({'x': a}), twice),
        throwsFormatException,
      );
    });
  });
}
