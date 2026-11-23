import 'package:flutter_test/flutter_test.dart';

import '../../tool/device/src/time_in_state.dart';
import 'fixtures.dart';

/// One thread's `time_in_state` as the phone prints it.
const _example = '''
cpu0
691200 100
806400 8
1804800 37
cpu4
691200 20
2208000 30
''';

void main() {
  test('one thread parses into clusters of kHz and ticks', () {
    expect(parseTimeInState(_example), {
      'cpu0': {691200: 100, 806400: 8, 1804800: 37},
      'cpu4': {691200: 20, 2208000: 30},
    });
  });

  test('blank lines are skipped', () {
    expect(parseTimeInState('\ncpu0\n\n691200 3\n\n'), {
      'cpu0': {691200: 3},
    });
  });

  test('tid= blocks parse per thread; an empty block is an empty thread', () {
    final threads = parseTaskTimeInState(fixture('task_time_in_state_t1.txt'));

    expect(threads.keys, [10630, 10696, 11251]);
    expect(threads[10696], {
      'cpu0': {691200: 7},
      'cpu4': {2208000: 1},
    });
    expect(threads[11251], isEmpty);
  });

  test('the delta subtracts per frequency; a new frequency counts from 0', () {
    final delta = timeInStateDelta(
      parseTimeInState(_example),
      parseTimeInState('$_example\ncpu7\n500000 4\n').map(
        (cluster, khz) => MapEntry(cluster, {
          for (final MapEntry(:key, :value) in khz.entries) key: value * 2,
        }),
      ),
    );

    expect(delta, {
      'cpu0': {691200: 100, 806400: 8, 1804800: 37},
      'cpu4': {691200: 20, 2208000: 30},
      'cpu7': {500000: 8},
    });
  });

  group('of one thread', () {
    final t = parseTimeInState(_example);

    test('totalTicks sums every counter', () {
      expect(totalTicks(t), 195);
    });

    test('clusterShare is the cluster\'s part of all ticks', () {
      expect(clusterShare(t, 'cpu0'), closeTo(145 / 195, 1e-12));
      expect(clusterShare(t, 'cpu4'), closeTo(50 / 195, 1e-12));
      expect(clusterShare(t, 'cpu9'), 0);
    });

    test('meanKhz is tick-weighted', () {
      expect(
        meanKhz(t, 'cpu4'),
        closeTo((691200 * 20 + 2208000 * 30) / 50, 1e-9),
      );
      expect(
        meanKhz(t, 'cpu0'),
        closeTo((691200 * 100 + 806400 * 8 + 1804800 * 37) / 145, 1e-9),
      );
    });

    test('meanKhz is 0 without ticks', () {
      expect(meanKhz(parseTimeInState('cpu0\n691200 0\n'), 'cpu0'), 0);
      expect(meanKhz(t, 'cpu9'), 0);
    });

    test('maxKhz is the highest listed frequency, also with zero ticks', () {
      expect(maxKhz(t, 'cpu4'), 2208000);
      expect(
        maxKhz(parseTimeInState('cpu4\n691200 9\n2208000 0\n'), 'cpu4'),
        2208000,
      );
    });

    test('a thread without ticks has no share', () {
      final idle = parseTimeInState('cpu0\n691200 0\n');
      expect(totalTicks(idle), 0);
      expect(clusterShare(idle, 'cpu0'), 0);
    });
  });

  group('throws a FormatException', () {
    test('when a counter went down', () {
      expect(
        () => timeInStateDelta(
          parseTimeInState('cpu0\n691200 10\n'),
          parseTimeInState('cpu0\n691200 9\n'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('cpu0 691200'),
          ),
        ),
      );
    });

    test('when a frequency disappeared', () {
      expect(
        () => timeInStateDelta(
          parseTimeInState('cpu0\n691200 10\n'),
          parseTimeInState('cpu0\n806400 10\n'),
        ),
        throwsFormatException,
      );
    });

    for (final (name, text) in [
      ('a malformed line', 'cpu0\n691200 x\n'),
      ('a counter before any cluster', '691200 10\n'),
      ('a cluster without a number', 'cpu\n691200 10\n'),
    ]) {
      test('on $name, naming the line', () {
        final bad = text
            .split('\n')
            .firstWhere((l) => l != 'cpu0' && l.isNotEmpty);
        expect(
          () => parseTimeInState(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(bad),
            ),
          ),
        );
      });
    }

    test('on a line before the first tid=', () {
      expect(
        () => parseTaskTimeInState('cpu0\ntid=1\ncpu0\n691200 1\n'),
        throwsFormatException,
      );
    });

    test('on a malformed line inside a tid= block', () {
      expect(
        () => parseTaskTimeInState('tid=1\ncpu0\nbogus\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('bogus'),
          ),
        ),
      );
    });
  });
}
