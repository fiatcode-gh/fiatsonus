import 'package:material_ui/material_ui.dart';

import 'probe_entry.dart';

/// The probe build's first screen: one button per sink. The sink is chosen
/// once per process.
final class ProbePicker extends StatefulWidget {
  const ProbePicker({super.key, required this.onPick});

  final void Function(String sink) onPick;

  @override
  State<ProbePicker> createState() => _ProbePickerState();
}

final class _ProbePickerState extends State<ProbePicker> {
  bool _picked = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('fiatsonus probe')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final sink in probeEntryPoints.keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FilledButton(
              onPressed: _picked
                  ? null
                  : () {
                      setState(() => _picked = true);
                      widget.onPick(sink);
                    },
              child: Text('Sink $sink'),
            ),
          ),
      ],
    ),
  );
}
