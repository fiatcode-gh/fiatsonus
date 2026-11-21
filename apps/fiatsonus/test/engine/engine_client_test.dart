import 'dart:async';

import 'package:fiatsonus/src/engine/engine_client.dart';
import 'package:fiatsonus/src/engine/engine_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_engine_entry.dart';

const _scape = 'waterfall';
const _fade = Duration(milliseconds: 5);
const _timeout = Duration(seconds: 20);

Future<IsolateEngineClient> _spawn(EngineEntryPoint entryPoint) =>
    IsolateEngineClient.spawn(
      sampleRate: 48000,
      seed: 7,
      tempDirPath: '/tmp',
      entryPoint: entryPoint,
    );

/// Records every event of a client and waits for conditions on them.
final class _Recorder {
  _Recorder(EngineClient client) {
    _sub = client.events.listen(
      (event) {
        events.add(event);
        _lastEventAt = DateTime.now();
        _check();
      },
      onDone: () {
        done = true;
        _check();
      },
    );
  }

  late final StreamSubscription<EngineEvent> _sub;
  final List<EngineEvent> events = [];
  bool done = false;
  DateTime _lastEventAt = DateTime.now();
  final List<(bool Function(), Completer<void>)> _waiters = [];

  List<bool> get states => [
    for (final e in events)
      if (e is EngineStateChanged) e.playing,
  ];

  List<EngineError> get errors => events.whereType<EngineError>().toList();

  List<EngineStatsEvent> get stats =>
      events.whereType<EngineStatsEvent>().toList();

  /// Completes once [condition] holds.
  Future<void> until(bool Function() condition) {
    if (condition()) return Future<void>.value();
    final completer = Completer<void>();
    _waiters.add((condition, completer));
    return completer.future.timeout(_timeout);
  }

  /// Completes once no event arrived for [quiet].
  Future<void> quiet(Duration quiet) async {
    while (true) {
      final left = quiet - DateTime.now().difference(_lastEventAt);
      if (left <= Duration.zero) return;
      await Future<void>.delayed(left);
    }
  }

  void _check() {
    _waiters.removeWhere((w) {
      if (!w.$1()) return false;
      w.$2.complete();
      return true;
    });
  }

  Future<void> cancel() => _sub.cancel();
}

void main() {
  test('spawn reports the ready event', () async {
    final client = await _spawn(fakeEngineMain);
    addTearDown(client.dispose);

    expect(client.sampleRate, 48000);
    expect(client.sinkId, 'fake');
  });

  test(
    'start then stop opens and closes the sink and reports frames',
    () async {
      final client = await _spawn(fakeEngineMain);
      addTearDown(client.dispose);
      final rec = _Recorder(client);
      addTearDown(rec.cancel);

      client.start(_scape, fade: _fade);
      await rec.until(() => rec.states.isNotEmpty);
      client.stop(_scape, fade: _fade);
      await rec.until(() => rec.states.length == 2);

      expect(rec.states, [true, false]);
      expect(rec.errors, isEmpty);
      expect(rec.stats.any((s) => s.stats.frames > 0), isTrue);
    },
  );

  test('100 fast start/stop pairs keep one pump loop', () async {
    final client = await _spawn(fakeEngineMain);
    addTearDown(client.dispose);
    final rec = _Recorder(client);
    addTearDown(rec.cancel);

    for (var i = 0; i < 100; i++) {
      client.start(_scape, fade: _fade);
      client.stop(_scape, fade: _fade);
    }
    await rec.until(() => rec.states.isNotEmpty && !rec.states.last);
    await rec.quiet(const Duration(seconds: 1));

    expect(rec.errors, isEmpty);
    final states = rec.states;
    for (var i = 0; i < states.length; i++) {
      expect(states[i], i.isEven, reason: 'state $i of $states');
    }
    expect(states.last, isFalse);
    expect(rec.stats.last.stats.overlaps, 0);
  });

  test('setParam with a known and an unknown id causes no error', () async {
    final client = await _spawn(fakeEngineMain);
    addTearDown(client.dispose);
    final rec = _Recorder(client);
    addTearDown(rec.cancel);

    client.setParam(_scape, 'height', 0.8);
    client.setParam('nowhere', 'height', 0.8);
    client.setParam(_scape, 'nothing', 0.8);
    client.start(_scape, fade: _fade);
    client.stop(_scape, fade: _fade);
    await rec.until(() => rec.states.length == 2);

    expect(rec.errors, isEmpty);
    expect(rec.states, [true, false]);
  });

  test(
    'a failing sink reports an error and the stopped state each time',
    () async {
      final client = await _spawn(failingEngineMain);
      addTearDown(client.dispose);
      final rec = _Recorder(client);
      addTearDown(rec.cancel);

      for (var round = 1; round <= 2; round++) {
        client.start(_scape, fade: _fade);
        await rec.until(() => rec.states.length == round);

        final tail = rec.events
            .where((e) => e is EngineError || e is EngineStateChanged)
            .toList();
        expect(tail, hasLength(2 * round));
        expect(tail[2 * round - 2], isA<EngineError>());
        expect(
          tail[2 * round - 1],
          isA<EngineStateChanged>().having((e) => e.playing, 'playing', false),
        );
      }
    },
  );

  test('dispose closes events', () async {
    final client = await _spawn(fakeEngineMain);
    final rec = _Recorder(client);

    await client.dispose();
    await rec.until(() => rec.done);

    expect(rec.done, isTrue);
  });
}
