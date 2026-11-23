import '../engine/engine_client.dart';

/// Builds the audio package probe (task 08); thrown away after it.
const bool kProbe = bool.fromEnvironment('FIATSONUS_PROBE');

/// The engine client of a probe build, for the `Stall engine 1 s` button.
EngineClient? probeEngine;
