import 'package:fiatsonus/src/engine/engine_protocol.dart';
import 'package:fiatsonus/src/engine/engine_stats.dart';
import 'package:fiatsonus/src/playback/playback_handler.dart';
import 'package:fiatsonus/src/ui/debug_screen.dart';
import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_audio_focus.dart';
import '../support/fake_engine_client.dart';

const _scape = 'waterfall';

final class _Rig {
  _Rig() : engine = FakeEngineClient(), focus = FakeAudioFocus() {
    handler = PlaybackHandler(
      engine: engine,
      focus: focus,
      requestNotificationPermission: () async {},
      soundscapeId: _scape,
      title: 'Waterfall',
      log: (_) {},
    );
  }

  final FakeEngineClient engine;
  final FakeAudioFocus focus;
  late final PlaybackHandler handler;

  final List<ParamSpec> params = createSoundscape(_scape)!.params;

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: DebugScreen(
        handler: handler,
        params: params,
        sampleRate: 48000,
        sinkId: 'soloud',
      ),
    ),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

String _buttonLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('playStop')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('one slider per param at its default, with its label', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pumpScreen(tester);

    expect(rig.params.map((p) => p.id), [
      'height',
      'spray',
      'width',
      'distance',
    ]);
    expect(find.byType(Slider), findsNWidgets(rig.params.length));
    for (final spec in rig.params) {
      final slider = tester.widget<Slider>(find.byKey(Key('param-${spec.id}')));
      expect(slider.value, spec.defaultValue);
      expect(slider.min, 0);
      expect(slider.max, 1);
      expect(find.text(spec.label), findsOneWidget);
    }
  });

  testWidgets('dragging a slider sends that param', (tester) async {
    final rig = _Rig();
    await rig.pumpScreen(tester);

    await tester.drag(
      find.byKey(const Key('param-spray')),
      const Offset(120, 0),
    );
    await tester.pump();

    expect(rig.engine.params, isNotEmpty);
    for (final (scape, id, value) in rig.engine.params) {
      expect(scape, _scape);
      expect(id, 'spray');
      expect(value, inInclusiveRange(0, 1));
    }
    expect(rig.engine.params.last.$3, greaterThan(0.4));
    final slider = tester.widget<Slider>(find.byKey(const Key('param-spray')));
    expect(slider.value, rig.engine.params.last.$3);
  });

  testWidgets('play/stop follows the phase', (tester) async {
    final rig = _Rig();
    await rig.pumpScreen(tester);
    expect(_buttonLabel(tester), 'Play');
    expect(_text(tester, 'phase'), 'idle');

    await tester.tap(find.byKey(const Key('playStop')));
    await tester.pump();
    expect(rig.engine.ops, ['start']);
    expect(_buttonLabel(tester), 'Stop');
    expect(_text(tester, 'phase'), 'playing');

    rig.engine.push(const EngineStateChanged(playing: true));
    await tester.pump();
    await tester.tap(find.byKey(const Key('playStop')));
    await tester.pump();
    expect(rig.engine.ops, ['start', 'stop']);
    expect(_text(tester, 'phase'), 'stopping');
    expect(_buttonLabel(tester), 'Play');

    rig.engine.push(const EngineStateChanged(playing: false));
    await tester.pump();
    expect(_text(tester, 'phase'), 'idle');
    expect(_buttonLabel(tester), 'Play');
  });

  testWidgets('a stats event updates the readout', (tester) async {
    final rig = _Rig();
    await rig.pumpScreen(tester);
    expect(_text(tester, 'stats'), '—');

    rig.engine.push(
      const EngineStatsEvent(
        EngineStats(
          playMicros: 1000000,
          renderMicros: 123456,
          maxRenderMicros: 900,
          frames: 48000,
          underruns: 3,
          starvedMicros: 4500,
          overlaps: 0,
          faults: 1,
          sessions: 1,
        ),
      ),
    );
    await tester.pump();

    final stats = _text(tester, 'stats');
    expect(stats, contains('soloud'));
    expect(stats, contains('48000'));
    expect(stats, contains('12.35 %'));
    expect(stats, contains('underruns: 3'));
    expect(stats, contains('starved: 4.5 ms'));
    expect(stats, contains('frames: 48000'));
  });

  testWidgets('lastError is shown when set', (tester) async {
    final rig = _Rig();
    await rig.pumpScreen(tester);
    expect(find.byKey(const Key('error')), findsNothing);

    rig.engine.push(const EngineError('sink failed'));
    await tester.pump();

    expect(_text(tester, 'error'), 'sink failed');
  });
}
