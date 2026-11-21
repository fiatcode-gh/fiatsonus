import 'package:fiatsonus/src/engine/engine_protocol.dart';
import 'package:fiatsonus/src/engine/engine_stats.dart';
import 'package:flutter_test/flutter_test.dart';

const _stats = EngineStats(
  playMicros: 1,
  renderMicros: 2,
  maxRenderMicros: 3,
  frames: 4,
  underruns: 5,
  starvedMicros: 6,
  overlaps: 7,
  faults: 8,
  sessions: 9,
);

void main() {
  group('EngineCommand', () {
    test('start encodes id and fade in milliseconds', () {
      expect(
        EngineCommand.start('waterfall', const Duration(milliseconds: 2000)),
        ['start', 'waterfall', 2000],
      );
    });

    test('stop encodes id and fade in milliseconds', () {
      expect(
        EngineCommand.stop('waterfall', const Duration(milliseconds: 3000)),
        ['stop', 'waterfall', 3000],
      );
    });

    test('param encodes ids and value', () {
      expect(EngineCommand.param('waterfall', 'height', 0.25), [
        'param',
        'waterfall',
        'height',
        0.25,
      ]);
    });

    test('commands carry only String, int and double', () {
      final commands = [
        EngineCommand.start('a', const Duration(seconds: 1)),
        EngineCommand.stop('a', const Duration(seconds: 1)),
        EngineCommand.param('a', 'p', 1),
      ];
      for (final command in commands) {
        for (final field in command) {
          expect(
            field is String || field is int || field is double,
            isTrue,
            reason: '$field in $command',
          );
        }
      }
      expect(EngineCommand.param('a', 'p', 1)[3], isA<double>());
    });
  });

  group('EngineEvent', () {
    test('ready round-trips', () {
      final event = const EngineReady(sampleRate: 48000, sinkId: 'soloud');
      expect(event.encode(), ['ready', 48000, 'soloud']);
      final decoded = EngineEvent.decode(event.encode()) as EngineReady;
      expect(decoded.sampleRate, 48000);
      expect(decoded.sinkId, 'soloud');
    });

    test('state round-trips', () {
      for (final playing in [true, false]) {
        final event = EngineStateChanged(playing: playing);
        expect(event.encode(), ['state', playing]);
        final decoded = EngineEvent.decode(event.encode());
        expect((decoded as EngineStateChanged).playing, playing);
      }
    });

    test('stats round-trips', () {
      final event = const EngineStatsEvent(_stats);
      expect(event.encode(), ['stats', 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final decoded = EngineEvent.decode(event.encode()) as EngineStatsEvent;
      expect(decoded.stats, _stats);
    });

    test('error round-trips', () {
      final event = const EngineError('boom');
      expect(event.encode(), ['error', 'boom']);
      final decoded = EngineEvent.decode(event.encode()) as EngineError;
      expect(decoded.message, 'boom');
    });

    test('decode returns null for malformed messages', () {
      final malformed = <Object?>[
        null,
        'state',
        42,
        <Object>[],
        ['unknown', 1],
        ['ready', 48000],
        ['ready', 48000, 'soloud', 1],
        ['ready', '48000', 'soloud'],
        ['ready', 48000, 7],
        ['state'],
        ['state', 'true'],
        ['state', true, true],
        ['stats', 1, 2, 3, 4, 5, 6, 7, 8],
        ['stats', 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        ['stats', 1, 2, 3, 4, 5, 6, 7, 8, 9.0],
        ['error'],
        ['error', 1],
        [1, 'boom'],
      ];
      for (final raw in malformed) {
        expect(EngineEvent.decode(raw), isNull, reason: '$raw');
      }
    });
  });
}
