import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:material_ui/material_ui.dart';

import '../engine/engine_stats.dart';
import '../playback/playback_handler.dart';

/// The spike's only screen: play/stop, one slider per parameter and the
/// engine's counters.
final class DebugScreen extends StatefulWidget {
  const DebugScreen({
    super.key,
    required this.handler,
    required this.params,
    required this.sampleRate,
    required this.sinkId,
  });

  final PlaybackHandler handler;
  final List<ParamSpec> params;
  final int sampleRate;
  final String sinkId;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

final class _DebugScreenState extends State<DebugScreen> {
  late final Map<String, double> _values = {
    for (final spec in widget.params) spec.id: spec.defaultValue,
  };

  void _setParam(String id, double value) {
    setState(() => _values[id] = value);
    widget.handler.setParam(id, value);
  }

  @override
  Widget build(BuildContext context) {
    final handler = widget.handler;
    return Scaffold(
      appBar: AppBar(title: const Text('fiatsonus')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder(
            valueListenable: handler.phase,
            builder: (context, phase, _) => Row(
              children: [
                FilledButton(
                  key: const Key('playStop'),
                  onPressed: handler.toggle,
                  child: Text(_isOn(phase) ? 'Stop' : 'Play'),
                ),
                const SizedBox(width: 16),
                Text(phase.name, key: const Key('phase')),
              ],
            ),
          ),
          ValueListenableBuilder(
            valueListenable: handler.lastError,
            builder: (context, error, _) => error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error, key: const Key('error')),
                  ),
          ),
          const SizedBox(height: 16),
          for (final spec in widget.params) ...[
            Text(spec.label),
            Slider(
              key: Key('param-${spec.id}'),
              value: _values[spec.id]!,
              onChanged: (value) => _setParam(spec.id, value),
            ),
          ],
          const SizedBox(height: 16),
          ValueListenableBuilder(
            valueListenable: handler.stats,
            builder: (context, stats, _) => Text(
              stats == null ? '—' : _statsText(stats),
              key: const Key('stats'),
            ),
          ),
        ],
      ),
    );
  }

  String _statsText(EngineStats stats) => [
    'sink: ${widget.sinkId}',
    'rate: ${widget.sampleRate} Hz',
    'render: ${(stats.renderRatio * 100).toStringAsFixed(2)} %',
    'underruns: ${stats.underruns}',
    'starved: ${(stats.starvedMicros / 1000).toStringAsFixed(1)} ms',
    'overlaps: ${stats.overlaps}',
    'faults: ${stats.faults}',
    'frames: ${stats.frames}',
  ].join('\n');
}

bool _isOn(PlaybackPhase phase) =>
    phase == PlaybackPhase.playing || phase == PlaybackPhase.interrupted;
