import 'dart:typed_data';

import 'package:fiatsonus/src/engine/device_sink.dart';
import 'package:fiatsonus/src/engine/engine_host.dart';
import 'package:fiatsonus/src/engine/engine_protocol.dart';
import 'package:fiatsonus/src/engine/engine_stats.dart';
import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_device_sink.dart';

const _rate = 16000;
const _seed = 7;
const _scape = 'waterfall';

typedef _Script = Map<int, List<List<Object>>>;

/// An [EngineHost] on a [FakeDeviceSink] that records every event.
final class _Rig {
  _Rig() {
    host = EngineHost(
      sampleRate: _rate,
      seed: _seed,
      sink: sink,
      emit: (event) {
        events.add(event);
        framesAtEvent.add(sink.framesWritten);
      },
      log: (line) {
        logs.add(line);
        framesAtLog.add(sink.framesWritten);
      },
    );
  }

  final FakeDeviceSink sink = FakeDeviceSink();
  late final EngineHost host;
  final List<List<Object>> events = [];
  final List<int> framesAtEvent = [];
  final List<String> logs = [];
  final List<int> framesAtLog = [];

  /// Injects the commands of [script] after the chunk of each index.
  void play(_Script script) {
    sink.onWrite = (index) {
      for (final command in script[index] ?? const <List<Object>>[]) {
        host.handle(command);
      }
    };
  }

  List<EngineEvent> get decoded => [
    for (final e in events) EngineEvent.decode(e)!,
  ];

  List<bool> get states => [
    for (final e in decoded)
      if (e is EngineStateChanged) e.playing,
  ];

  List<EngineStats> get stats => [
    for (final e in decoded)
      if (e is EngineStatsEvent) e.stats,
  ];

  List<List<Object>> get nonStats => [
    for (final e in events)
      if (e[0] != 'stats') e,
  ];
}

Master _twinMaster() {
  final master = Master(sampleRate: _rate, seed: _seed);
  for (final id in soundscapeIds) {
    master.add(createSoundscape(id)!);
  }
  return master;
}

void _apply(Master master, List<Object> command) {
  switch (command) {
    case ['start', final String id, final int ms]:
      master.start(id, fade: Duration(milliseconds: ms));
    case ['stop', final String id, final int ms]:
      master.stop(id, fade: Duration(milliseconds: ms));
    case ['param', final String id, final String param, final double value]:
      master.setParam(id, param, value);
    default:
      fail('unexpected command $command');
  }
}

/// Renders [writes] again on a fresh [Master] given [initial] first and the
/// commands of [script] after the same chunks, and compares every sample.
/// [between] runs on the twin after the chunk of its key, after [script].
void _expectTwin(
  List<Int16List> writes, {
  required List<List<Object>> initial,
  required _Script script,
  Map<int, void Function(Master twin)> between = const {},
}) {
  final twin = _twinMaster();
  for (final command in initial) {
    _apply(twin, command);
  }
  for (var k = 0; k < writes.length; k++) {
    final written = writes[k];
    final expected = Int16List(written.length);
    twin.render(expected, written.length ~/ 2);
    for (var i = 0; i < written.length; i++) {
      if (written[i] != expected[i]) {
        fail(
          'chunk $k sample $i: wrote ${written[i]}, twin ${expected[i]} '
          '(${writes.length} chunks)',
        );
      }
    }
    for (final command in script[k] ?? const <List<Object>>[]) {
      _apply(twin, command);
    }
    between[k]?.call(twin);
  }
}

bool _allZero(Int16List chunk) => chunk.every((s) => s == 0);

bool _anyNonZero(Iterable<Int16List> chunks) => chunks.any((c) => !_allZero(c));

int _logFrames(String line) =>
    int.parse(RegExp(r' frames=(\d+) ').firstMatch(line)!.group(1)!);

void main() {
  final start = EngineCommand.start(_scape, kPlayFade);
  final stop = EngineCommand.stop(_scape, kStopFade);

  test('start opens the sink once and audio flows', () async {
    final rig = _Rig()
      ..play({
        8: [stop],
      });
    rig.host.handle(start);
    await rig.host.settled;

    expect(rig.sink.startCount, 1);
    expect(rig.sink.sampleRate, _rate);
    expect(rig.sink.channels, 2);
    expect(rig.events.first, ['state', true]);
    expect(rig.sink.writes.first.length, kChunkFrames * 2);
    expect(_anyNonZero(rig.sink.writes.take(8)), isTrue);
  });

  test('stop fades out, flushes half a second of zeros, then closes', () async {
    final rig = _Rig()
      ..play({
        10: [stop],
      });
    rig.host.handle(start);
    await rig.host.settled;

    final writes = rig.sink.writes;
    final firstZero = writes.indexWhere(_allZero, 11);
    expect(firstZero, greaterThan(10));
    expect(_anyNonZero(writes.skip(firstZero)), isFalse);

    var trailingZeroFrames = 0;
    outer:
    for (final chunk in writes.reversed) {
      for (var i = chunk.length - 2; i >= 0; i -= 2) {
        if (chunk[i] != 0 || chunk[i + 1] != 0) break outer;
        trailingZeroFrames++;
      }
    }
    expect(trailingZeroFrames, greaterThanOrEqualTo(_rate ~/ 2));

    expect(rig.sink.stopCount, 1);
    expect(rig.sink.calls.last, 'stop');
    expect(rig.states, [true, false]);
    expect(rig.events.last, ['state', false]);
  });

  test('S6: 100 alternating commands render like a twin master', () async {
    final script = <int, List<List<Object>>>{};
    var x = 12345;
    var index = 2;
    for (var i = 0; i < 100; i++) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      index += 1 + x % 12;
      script[index] = [if (i.isEven) stop else start];
    }
    script[index + 4] = [stop];

    final rig = _Rig()..play(script);
    rig.host.handle(start);
    await rig.host.settled;

    _expectTwin(rig.sink.writes, initial: [start], script: script);
    expect(rig.sink.startCount, 1);
    expect(rig.sink.stopCount, 1);
    expect(rig.stats.last.overlaps, 0);
    expect(rig.states, [true, false]);
  });

  test('start during the fade-out keeps the same session', () async {
    final rig = _Rig()
      ..play({
        5: [stop],
        10: [start],
        15: [stop],
      });
    rig.host.handle(start);
    await rig.host.settled;

    expect(rig.sink.calls.first, 'start');
    expect(rig.sink.calls.last, 'stop');
    expect(rig.sink.startCount, 1);
    expect(rig.sink.stopCount, 1);
    expect(rig.states, [true, false]);
    expect(rig.stats.last.sessions, 1);
  });

  test('start after a full stop opens a second session', () async {
    final rig = _Rig()
      ..play({
        3: [stop],
      });
    rig.host.handle(start);
    await rig.host.settled;
    final firstSession = rig.sink.writes.length;

    rig.play({
      firstSession + 3: [stop],
    });
    rig.host.handle(start);
    await rig.host.settled;

    expect(rig.sink.startCount, 2);
    expect(rig.sink.stopCount, 2);
    expect(rig.states, [true, false, true, false]);
    expect(rig.stats.last.sessions, 2);
  });

  test('param reaches the soundscape', () async {
    final script = <int, List<List<Object>>>{
      5: [EngineCommand.param(_scape, 'height', 0.95)],
      20: [stop],
    };
    final rig = _Rig()..play(script);
    rig.host.handle(start);
    await rig.host.settled;

    _expectTwin(rig.sink.writes, initial: [start], script: script);

    final withoutParam = _twinMaster()..start(_scape, fade: kPlayFade);
    final probe = Int16List(kChunkFrames * 2);
    var differs = false;
    for (var k = 0; k < 20 && !differs; k++) {
      withoutParam.render(probe, kChunkFrames);
      differs = k > 5 && !_listEquals(probe, rig.sink.writes[k]);
    }
    expect(differs, isTrue, reason: 'the param changed nothing audible');
  });

  test('malformed messages and unknown ids do nothing', () async {
    final rig = _Rig();
    final malformed = <Object?>[
      null,
      'start',
      42,
      <Object>[],
      ['start'],
      [_scape, 'start', 2000],
      ['start', _scape],
      ['start', _scape, '2000'],
      ['start', _scape, 2000.0],
      ['start', 1, 2000],
      ['start', _scape, 2000, 1],
      ['stop', _scape],
      ['param', _scape, 'height'],
      ['param', _scape, 'height', '0.5'],
      ['param', _scape, 1, 0.5],
      ['bogus', _scape, 2000],
      ['ready', _rate, 'fake'],
      ['start', 'nope', 2000],
      ['stop', 'nope', 3000],
      ['param', 'nope', 'height', 0.5],
    ];
    for (final message in malformed) {
      rig.host.handle(message);
    }
    await rig.host.settled;
    await Future<void>(() {});

    expect(rig.events, isEmpty);
    expect(rig.sink.calls, isEmpty);
  });

  test(
    'a failing write reports, closes the sink and silences the master',
    () async {
      final rig = _Rig()..sink.failAtWrite = 3;
      rig.host.handle(start);
      await rig.host.settled;

      expect(rig.nonStats.map((e) => e[0]), ['state', 'error', 'state']);
      expect(rig.nonStats.first, ['state', true]);
      expect(rig.nonStats[1][1], isA<String>());
      expect(rig.nonStats.last, ['state', false]);
      expect(rig.sink.calls, [
        'start',
        'write',
        'write',
        'write',
        'write',
        'stop',
      ]);

      final script = <int, List<List<Object>>>{
        9: [stop],
      };
      rig.play(script);
      rig.host.handle(start);
      await rig.host.settled;

      expect(rig.sink.startCount, 2);
      expect(rig.sink.stopCount, 2);
      expect(_anyNonZero(rig.sink.writes.skip(4)), isTrue);
      expect(rig.states, [true, false, true, false]);
      _expectTwin(
        rig.sink.writes,
        initial: [start],
        script: script,
        between: {
          3: (twin) {
            twin.stop(_scape, fade: const Duration(milliseconds: 5));
            final discard = Int16List(kChunkFrames * 2);
            while (!twin.isSilent) {
              twin.render(discard, kChunkFrames);
            }
            _apply(twin, start);
          },
        },
      );
    },
  );

  test(
    'stats every second of audio and at session end; logs every 10 s',
    () async {
      final rig = _Rig()
        ..play({
          100: [stop],
        });
      rig.host.handle(start);
      await rig.host.settled;

      var previous = 0;
      for (var i = 0; i < rig.events.length; i++) {
        final event = EngineEvent.decode(rig.events[i]);
        if (event is! EngineStatsEvent) continue;
        expect(event.stats.frames, rig.framesAtEvent[i]);
        expect(event.stats.frames - previous, lessThanOrEqualTo(_rate));
        previous = event.stats.frames;
      }
      expect(rig.stats.length, greaterThan(100 * kChunkFrames ~/ _rate));
      expect(rig.stats.last.frames, rig.sink.framesWritten);
      expect(rig.decoded[rig.decoded.length - 2], isA<EngineStatsEvent>());

      expect(rig.logs.length, greaterThanOrEqualTo(2));
      var previousLog = 0;
      for (var i = 0; i < rig.logs.length; i++) {
        expect(rig.logs[i], startsWith('FSTAT v=1 sink=fake rate=$_rate '));
        final frames = _logFrames(rig.logs[i]);
        expect(frames, rig.framesAtLog[i]);
        expect(frames - previousLog, lessThanOrEqualTo(10 * _rate));
        previousLog = frames;
      }
      expect(_logFrames(rig.logs.last), rig.sink.framesWritten);
      expect(
        rig.logs.last,
        rig.stats.last.logLine(sinkId: 'fake', sampleRate: _rate),
      );
    },
  );

  test('sink underruns accumulate across sessions', () async {
    final rig = _Rig();
    rig.sink.onWrite = (index) {
      if (index == 1) {
        rig.sink
          ..underruns = 2
          ..starvedMicros = 1000;
      }
      if (index == 2) rig.host.handle(stop);
    };
    rig.host.handle(start);
    await rig.host.settled;
    expect(rig.stats.last.underruns, 2);
    expect(rig.stats.last.starvedMicros, 1000);

    final second = rig.sink.writes.length;
    rig.sink.onWrite = (index) {
      if (index == second + 1) {
        rig.sink
          ..underruns = 3
          ..starvedMicros = 500;
      }
      if (index == second + 2) rig.host.handle(stop);
    };
    rig.host.handle(start);
    await rig.host.settled;

    expect(rig.stats.last.underruns, 5);
    expect(rig.stats.last.starvedMicros, 1500);
    expect(rig.stats.last.sessions, 2);
  });

  test('start and stop honour their fades', () async {
    final fastIn = EngineCommand.start(
      _scape,
      const Duration(milliseconds: 300),
    );
    final slowOut = EngineCommand.stop(
      _scape,
      const Duration(milliseconds: 5000),
    );
    final script = <int, List<List<Object>>>{
      6: [slowOut],
    };
    final rig = _Rig()..play(script);
    rig.host.handle(fastIn);
    await rig.host.settled;

    _expectTwin(rig.sink.writes, initial: [fastIn], script: script);
    final fadeOutFrames = (rig.sink.writes.length - 7) * kChunkFrames;
    expect(fadeOutFrames, greaterThan(5 * _rate));
  });
}

bool _listEquals(Int16List a, Int16List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
