# platform-spike (unit 2): decisions

## Audio package probe

- Date 2026-11-23. Phone vivo I2219 (adb `10DF1Q03JJ000HK`), Android 16 / API 36, on USB, speaker, output 48000 Hz. Release build, `flutter build apk --release --dart-define=FIATSONUS_PROBE=true`, one APK holding all three sinks. Probe code: commit `2b290ae` (removed again after this record).
- Scenario, identical per sink, in the order soloud, pcm, mp:
  1. `FIATSONUS_PROBE_SINK=<sink> tool/device/screen_off_run.sh 10 build/device/probe/<sink>/run`: play, 10 min screen off, report, stop from the app, assert service, notification and wake lock gone.
  2. Play again, 10 s, snapshot, `Stall UI 2 s` (2 s busy loop in the root isolate), 8 s, snapshot: deltas.
  3. 10 s, snapshot, `Stall engine 1 s` (1 s busy loop in the engine isolate), 12 s, snapshot: deltas; then Stop and assert idle.

| | soloud (`flutter_soloud` 5.3.1) | pcm (`flutter_pcm_sound` 3.3.3) | mp (`mp_audio_stream` 0.3.0) |
|---|---|---|---|
| Demand mechanism, where it arrives | pull stream `onMoreDataIsNeeded` (`NativeCallable.listener`), in the engine isolate | `OnFeedSamples` on a `MethodChannel`, in the root isolate, relayed to the engine isolate over a `SendPort` | none; `Stopwatch` clock with `Future.delayed` in the engine isolate |
| G1 demand | pass | fail (root-isolate relay) | fail (timer) |
| G2 UI stall | pass | fail | pass (af by hand, see below) |
| G3 screen-off | pass (`PASS`, exit 0) | fail (`FAIL underruns 1 != 0`) | fail (`FAIL no output thread with a sample rate holds a track of pid 16522 in t1/audio_flinger.txt`; tool, see below) |
| G4 stop | pass | pass | pass |
| G5 liveness | pass | pass | pass |
| `CPU` line | `CPU MISS render_ratio_pct=17.19 limit_pct=5.00` | `CPU MISS render_ratio_pct=16.60 limit_pct=5.00` | `CPU MISS render_ratio_pct=17.34 limit_pct=5.00` |
| `render_ratio_pct` | 17.19 | 16.60 | 17.34 |
| `process_cpu_pct` | 19.38 | 32.69 | 24.19 |
| `max_render_us` | 16047 | 12043 | 14089 |
| `underruns` | 0 | 1 | 0 |
| `starved_us` | 0 | 0 | 0 |
| `af_underruns` | 0 | 0 | 0 reported; 0 by hand |
| `deficit_ms` | -26.2 | -0.5 | 0.2 |
| UI stall: underruns / starved_us / af_underruns | 0 / 0 / 0 | 5 / 0 / 87552 | 0 / 0 / 0 (by hand) |
| Engine stall: underruns / starved_us / af_underruns | 1 / 810666 / 0 | 2 / 0 / 39680 | 91 / 0 / 0 (by hand) |
| Native library (arm64-v8a) | `libflutter_soloud_plugin.so` 1 472 816 B | none (Java plugin) | `libmp_audio_stream.so` 334 440 B |
| Direct dependencies | 12 (`code_assets`, `ffi`, `flutter`, `hooks`, `http`, `logging`, `meta`, `native_toolchain_c`, `path`, `path_provider`, `plugin_platform_interface`, `web`) | 1 (`flutter`) | 3 (`ffi`, `flutter`, `web`) |
| Last release | 5.3.1 on 2026-11-18 (5.3.2 on 2026-11-22) | 3.3.3 on 2025-10-04 | 0.3.0 on 2026-09-27 |

Each step-2 and step-3 delta comes from a snapshot pair whose second `FSTAT` line was written after the stall had ended. Each UI stall shows up as the main thread's CPU in that window: `tcode.fiatsonus` used 12.73 % of 16.66 s for soloud, 16.43 % of 18.56 s for pcm and 16.40 % of 12.56 s for mp, about 2 s or more in each case.

**Verdict.** `flutter_soloud` passes G1 to G5, so this is outcome A and it stays the chosen package. Its render ratio misses the 5 % limit, like the ratios of the other two sinks, and that is reported on the `CPU` line, not gated here.

**Why the other two cannot meet the constraints (PLAN section 2).** `flutter_pcm_sound` signals demand only through a `MethodChannel`, which reaches the root isolate only. So the feed has to hop through the UI isolate, and a 2 s UI stall starves it (5 underruns, 87 552 AudioFlinger underruns). `mp_audio_stream` has no demand signal and no fill query (`push` and `stat` only), so it needs a timer. Both rows were measured in that non-compliant form.

**Lead of the soloud sink.** The `FLEAD` line at step 1's stop: `FLEAD sink=soloud ref_us=128000 jitter_us=0 underruns=0 starved_us=0`. The lead held 128 000 µs and its jitter measured 0 µs. Note: twice the measured jitter (0 µs) is below one chunk (2048 frames at 48 kHz, 42 666 µs). `LeadTracker`'s tolerance stays one chunk. After step 3's 1 s engine stall: `FLEAD sink=soloud ref_us=-682666 jitter_us=0 underruns=1 starved_us=810666`.

**What a sink failed to do, verbatim.**

- mp, first attempt (`build/device/probe/mp_attempt1/`): while the mp sink plays, `uiautomator dump` prints `ERROR: could not get idle state.`. It does so with the screen on and before any screen-off, and works again once playback is idle. `ui_tap.sh` then printed `ui_tap.sh: no node labelled 'Stop'` at step 1's stop, so `screen_off_run.sh` exited 2 before its stop assertions. The later `ui_tap.sh Play` matched a stale dump file and stopped playback instead of starting it, which broke steps 2 to 4. soloud and pcm were not affected.
- Workaround 1 (mp rerun, `build/device/probe/mp/`): the same scenario, with every tap sent as `adb shell input tap` at the centre of the button's bounds. The bounds came from an idle `uiautomator dump` of the same probe layout, taken right before the rerun (`coords play/stop=147,369 stall_ui=203,545 stall_engine=605,545`). Each tap was confirmed before moving on: Play and Stop by their `FSTATE phase=playing` and `FSTATE phase=idle` lines, the UI stall by the main thread's CPU in step 2, and the engine stall by the underruns in step 3. The sink was chosen with `ui_tap.sh "Sink mp"` before playback, as for the other sinks.
- Workaround 2: `report.dart` reads no track row of mp, because its row starts with the fast-track type `F1` and the parser accepts only a one-character type. So every mp report says `FAIL no output thread with a sample rate holds a track of pid 16522 in t1/audio_flinger.txt` and prints `af_underruns=0` without the track. `report.dart` was not changed. mp's AudioFlinger underruns were read by hand from the raw dumps: the `Underruns` cell is 0 in every snapshot, so every delta is 0. The track sits on `AudioOut_D`, at `Sample rate: 48000 Hz`. The rows:

```text
run/t0  F1      308    yes   16522/  10450    2337     282 A  0x000 00000005 00000003  48000  3   1  2   -34     0     0     0          -34      false 000F2AC0   1440    1440 f         0        0      false        false   51.00 t
run/t1  F1      308    yes   16522/  10450    2337     282 A  0x000 00000005 00000003  48000  3   1  2   -34     0     0     0          -34      false 01C78440   1440    1344 f         0        0      false        false   49.00 t
s2a     F1      309    yes   16522/  10450    2345     283 A  0x000 00000005 00000003  48000  3   1  2   -34     0     0     0          -34      false 0007D700   1440    1344 f         0        0      false        false   49.00 t
s2b     F1      309    yes   16522/  10450    2345     283 A  0x000 00000005 00000003  48000  3   1  2   -34     0     0     0          -34      false 00111300   1440    1344 f         0        0      false        false   49.00 t
s3a     F1      309    yes   16522/  10450    2345     283 A  0x000 00000005 00000003  48000  3   1  2   -34     0     0     0          -34      false 00197D00   1440    1344 f         0        0      false        false   49.00 t
s3b     F1      309    yes   16522/  10450    2345     283 A  0x000 00000005 00000003  48000  3   1  2   -34     0     0     0          -34      false 00242940   1440    1440 f         0        0      false        false   51.00 t
```

- mp's `underruns` counts `stat().exhaust`, which counts output callbacks, not starvation events. So the 1 s engine stall shows as 91. The clock then pushes faster than real time to catch up, and the ring buffer drops what does not fit. That is why the deficit stays near 0 (-0.7 ms) after the stall.
- Every sink built with the unmodified packages and the compileSdk override of PLAN 4.9, and every sink started.
