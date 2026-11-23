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

- Since task 12 (`68df9cf`, `fix(tool): read fast tracks in the AudioFlinger track table`) the parser reads track types of any length, `F1` included; the probe's mp numbers above stay as they were read by hand.
- mp's `underruns` counts `stat().exhaust`, which counts output callbacks, not starvation events. So the 1 s engine stall shows as 91. The clock then pushes faster than real time to catch up, and the ring buffer drops what does not fit. That is why the deficit stays near 0 (-0.7 ms) after the stall.
- Every sink built with the unmodified packages and the compileSdk override of PLAN 4.9, and every sink started.

## Measured on the phone

The acceptance campaign ran at `db5fcae` on 2026-11-23. Every capsule passed. The capsules live in the local, uncommitted `.flow/evidence/db5fcae/`; the file named beside each number is relative to it. Some capsules share a directory: `interrupt-and-notification-stop/` holds `call-pause-resume` (`interrupt/`, `call_watch.out`) and `notification-stop` (`notif/`), and `transient-and-stop-loop/` holds `transient-resume` (`transient/`, `transient.log`) and `stop-loop` (`inapp/`, `notif/`, `inapp.log`, `notif.log`).

### The soak (`soak-1h`)

Conditions: vivo I2219, Android 16 / API 36 (the probe's phone), release build installed by `tool/device/install.sh`, phone speaker, media volume 6 of 15 as the user set it, Do Not Disturb on for the hour, the waterfall at default params, one sink session (`fstat.txt`: `sessions=1`). The app sets no thread affinity or priority.

**Deviation: the screen was on for 10 min 47 s of the battery window.** The battery history (`t1/batterystats_history.txt`) shows `+screen` at 10:41:58.516, right after the unplug at 10:41:58.461, and `-screen` at 10:52:45.495. Screen-off playback after the unplug ran 1 h 30 min 37 s (10:52:45 to the replug at 12:23:22). Accepted: every counter below is zero over the whole run, screen-on minutes included.

| Measure | Value | File |
|---|---|---|
| Wall time t0 to t1 | 6474.750 s (1 h 47 min 55 s; t0 10:35:28, t1 12:23:23) | `report.txt` (`wall_s`), `t0/time.txt`, `t1/time.txt` |
| `CPU` line | `CPU MISS render_ratio_pct=17.35 limit_pct=5.00` | `report.txt` |
| Engine CPU (`render_ratio_pct`) | 17.35 % | `report.txt` |
| Process CPU (`process_cpu_pct`) | 19.71 % | `report.txt` |
| Top threads | `DartWorker` 17.50 %, `AudioTrack` 2.03 %, `tcode.fiatsonus` 0.12 %, `1.raster` 0.04 %, `binder:32757_1` 0.01 % | `report.txt` (`top_threads`) |
| `max_render_us` | 20 977 µs, against a chunk of 2048 frames at 48 kHz (42 667 µs): 49 % of the chunk | `report.txt` |
| `underruns` | 0 | `report.txt` |
| `starved_us` | 0 | `report.txt` |
| AudioFlinger underruns (`af_underruns`) | 0 | `report.txt` |
| Frame deficit (`deficit_ms`) | -34.7 ms over 6469.632 s of audio (`audio_s`); bound 300 ms + 0.02 % of the wall time = 1595.0 ms (derived from `report.dart`'s rule) | `report.txt` |
| `overlaps`, `faults` | 0, 0 | `report.txt` |
| Lead of the whole session | `FLEAD sink=soloud ref_us=128000 jitter_us=0 underruns=0 starved_us=0` | `flead.txt` |
| Whole session, at the final stop | `FSTAT v=1 sink=soloud rate=48000 play_us=6690393576 render_us=1158010659 max_render_us=20977 frames=321146304 underruns=0 starved_us=0 overlaps=0 faults=0 sessions=1` (from Play to the final stop, so longer than t0 to t1) | `fstat.txt` |
| Engine and device sample rate | 48000 Hz, 48000 Hz | `report.txt` (`engine_rate`, `device_rate`) |
| Service in the foreground at t1 | yes | `report.txt` (`foreground=true`) |
| `battery_window` | 2026-11-23T10:41:58.461..2026-11-23T12:23:22.020 (1.690 h) | `report.txt` |
| Battery over the window | 147 mAh, 87.0 mAh/h, level drop 2 % | `report.txt` (`battery_mah`, `battery_mah_per_h`, `battery_level_drop`) |
| Counter cross-check | `battery_counter_mah=147.1`, `battery_counter_level_drop=2` (charge counter 4 869 185 to 4 722 047 µAh, level 90 to 88) | `report.txt`, `t0/battery.txt`, `t1/battery.txt` |
| Battery, screen off only (derived) | 120 mAh over 1.5047 h ≈ 79.8 mAh/h: `charge=4842` at 10:52:45.610 to `charge=4722` at 12:23:22.020 | derived by the verifier from `t1/batterystats_history.txt` |
| Functional verdict | `PASS` | `report.txt`, last line |
| Final-stop block | `PASS`; service and notification gone, wake lock released | `finalstop.log` |

The 87.0 mAh/h is an upper bound for screen-off playback: its window holds the 10 min 47 s with the screen on. The screen-off figure of about 80 mAh/h is the verifier's derivation from the history's `charge=` lines, not a report output.

Where the engine ran: the engine thread is the `DartWorker` with the largest CPU time, tid 607. Field 39 of its line in `task_stat.txt` and that core's frequency in `cpufreq.txt`:

| Snapshot | Core | Cluster | Current / maximum frequency | Files |
|---|---|---|---|---|
| t0 | cpu3 | little (cpu0–3) | 1 804 800 / 1 804 800 kHz | `t0/task_stat.txt` line 46, `t0/cpufreq.txt` |
| t1 | cpu4 | big (cpu4–7) | 2 208 000 / 2 208 000 kHz | `t1/task_stat.txt` line 44, `t1/cpufreq.txt` |

These are two snapshots, not an average of where the thread ran during the hour.

What the counters cannot see (PLAN 4.5): a lead drop of one chunk or less (2048 frames, 42.7 ms at 48 kHz) is not counted as an underrun and shows only as `jitter_us` on the `FLEAD` line, which reads 0 here. A session is not tracked during its first two blocks (128 demands, about 5.5 s) and its last unfinished block (up to 2.7 s). SoLoud fills its own gaps with silence, so AudioFlinger's count does not see them. The frame deficit may move by up to 1595.0 ms over this run before the report fails it.

Listening: the user listened for 2 minutes after Play and 2 minutes after the replug, and reported, after turning Do Not Disturb off, nothing abnormal at either end. Nobody listened through the hour.

### The other capsules

| Capsule | Result | File |
|---|---|---|
| `host-gates` | pub get, format, analyze, engine tests (376 passed), app tests (131 passed): every exit 0. Sink diff against the probe commit: 0 lines added and 10 removed in `apps/fiatsonus/lib/src/sink/lead_tracker.dart`, the waived `reset()` removal only | `host-gates/summary.txt`, `4-engine-test.log`, `5-app-test.log`, `7-numstat.log` |
| `release-manifest` | requested permissions: `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`, plus the app's own `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; no `INTERNET`. Release APK 52 159 228 bytes | `release-manifest/permissions.txt`, `apk-size.txt` |
| `stress-100` (profile build) | 100 fast taps, then ten quick replays: `All tests passed!`; last `FSTAT` `underruns=0 starved_us=0 overlaps=0 faults=0 sessions=12`; the foreground watch `RESULT samples=653 foreground=462 flagged=454 misses=0`, `PASS`; the repair logged `cancelling notification 1124 left after its service stopped` 3 times. The user heard no click and no doubled sound | `stress-100/console.txt`, `stress-100/run/misses.txt` |
| `permission-dialog`, Allow | before `granted=false` without `USER_SET`; after `granted=true` with the `USER_SET` flag; `notification=present`; playback started | `permission-dialog/allow/permission.txt` |
| `permission-dialog`, Deny | before `granted=false` without `USER_SET`; after `granted=false` with the `USER_SET` flag; playback started without the permission, the stop ended clean; `notification=present` (recorded, not judged: `dumpsys notification` lists it although the user denied) | `permission-dialog/deny/permission.txt` |
| `call-pause-resume` | A Clock countdown timer rang as the long interruption (contract amended 2026-11-23: no second phone). Focus owner on top of the stack `com.android.deskclock`, `GAIN_TRANSIENT`, `USAGE_ALARM`; the app's entry `loss: LOSS_TRANSIENT`. `FSTATE phase=interrupted` to `FSTATE phase=playing` 62.969 s; `PASS`. The user heard the sound pause and come back | `interrupt-and-notification-stop/interrupt/audio_focus.txt`, `call_watch.out` |
| `notification-stop` | after Stop from the notification: no notification of the app listed, the service record `startRequested=false` (bound only, by design) | `interrupt-and-notification-stop/notif/notification.txt` (empty), `notif/services.txt` line 34 |
| `transient-resume` | three focus losses with the screen off, each `interrupted` then `playing` again after about 1.2 s; `foreground kept (startForegroundCount=1)`, `mWakefulness=Asleep`, no errors; the report over the resumed playback `PASS` (`CPU MISS render_ratio_pct=16.96`), stop clean | `transient-and-stop-loop/transient.log`, `transient/report.txt` |
| `stop-loop` | see "Decisions and why" for its two last lines | `transient-and-stop-loop/inapp.log`, `notif.log` |

## What the numbers mean

- Engine CPU is the engine's render time over wall time, on whichever core and at whichever frequency Android chose; the app sets no affinity or priority. Over the soak it is 17.35 %, 3.47 times the 5 % limit (17.35 / 5). The contract's line "Engine CPU under 5 % of one core" is not met.
- The render ratio leaves out the native mixer thread (`AudioTrack`, 2.03 %) and the sink's FFI calls. The whole process used 19.71 % of one core (`process_cpu_pct`).
- Realtime factor on the phone: 100 / 17.35 = 5.8×. Unit 1 measured 240× on one idle desktop core (`docs/decisions/engine-core.md`), about 42 times as fast. The gap was not broken down into core speed, code generation and thread placement.
- The thread sat on a little core (cpu3, 1.8 GHz, at maximum) at t0 and on a big core (cpu4, 2.2 GHz, at maximum) at t1. The probe's 10-minute runs and the transient check measured 16.6 % to 17.3 % as well, so the figure holds across runs.
- The phone is mid-range. No low-end phone was measured, and a low-end phone would cost more.
- Battery is the phone's gross drain, not the app's share: screen off apart from the deviation above, speaker, volume 6 of 15, Do Not Disturb on. It comes from the unplugged window in the battery history, with the charge counter as a cross-check (147.1 mAh against the window's 147 mAh).
- "Zero audible gaps" over the hour rests on the counters (`underruns`, `starved_us`, the `FLEAD` line, AudioFlinger underruns, frame deficit) and on the listening at both ends. Nobody listened for the whole hour.

## Dart or native

**Recommendation: a native core.** Engine CPU measured 17.35 % of one core over the soak (`CPU MISS`, 3.47 times the 5 % limit), with zero underruns, so by the rule (5 % or more) the recommendation is a native core; this unit ends with the recommendation, not the core. The engine thread ran on cpu3 (little cluster, 1804.8 MHz, at its maximum) at t0 and on cpu4 (big cluster, 2208 MHz, at its maximum) at t1. Those are two snapshots, not an average: one of them found the thread on a big core at full speed while the hour's average stayed at 17.35 %, which points at the Dart engine's own cost on ARM, not only at core placement.

Next steps, in order:

1. Profile the Dart engine on ARM before building a native core. Unit 1's desktop factor (240×) and the phone's (5.8×) differ by far more than core speed explains, and the battery cost measured is modest (about 80 mAh/h for the whole phone with the screen off). A cause inside the Dart code would be cheaper to fix than a native core.
2. Then decide on the native core with that profile, before a second soundscape or stacking lands.

## Decisions and why

- **A spawned isolate, not a second `FlutterEngine`.** One `Isolate.spawn` isolate owns the engine, the pump and the sink for the life of the process; it needs no platform channel, and a second engine would add a second Flutter runtime for no gain.
- **The pull stream is the only callback that reaches the engine isolate.** `flutter_soloud`'s `onMoreDataIsNeeded` is a `NativeCallable.listener`, so demand arrives in the engine isolate without the UI isolate (probe G1, G2).
- **`write` waits for demand.** The pump renders a chunk and awaits `write`, which completes on the package's demand signal; that future is the only pacing, with no timer anywhere in `lib/`.
- **One session chain for S6.** Every start appends a session to one future chain with a generation number, so one pump loop runs at a time by construction, and a play during a fade-out fades back in inside the running loop.
- **500 ms of silence before closing the sink.** It flushes the fade tail, so the sink never stops while non-zero audio is unplayed.
- **`audio_service` with `androidStopForegroundOnPause: true`, and `playing` kept true through a transient loss.** `playing` turning false is `audio_service` 0.18.19's only signal for leaving the foreground and releasing its wake lock, so it turns false only together with idle; a transient loss shows `buffering` instead, and the service is never started again from the background.
- **`pause` is treated as `stop`.** On Android 17 a pause from the system media controls ends the interaction.
- **An own permission channel instead of `permission_handler`.** One `MethodChannel` in `MainActivity` asks for `POST_NOTIFICATIONS` once, before the first foreground start, and a refusal does not block playback (proven by the Deny round).
- **Lead tracking, because the package does not report starvation.** `LeadTracker` compares the pull buffer's end with the voice position per block of 64 demands; `onBuffering` says nothing about starvation.
- **A path-provider override** so the engine isolate needs no platform channel for `flutter_soloud`'s temporary directory.
- **The CPU verdict is kept apart from the functional one.** `report.dart` prints a `CPU` line and exits on the functional verdict only, so a CPU miss cannot hide a functional result, and a functional failure cannot hide behind a CPU pass.
- **The battery window is anchored to the run** (the first unplugged window after t0's local clock, checked for liveness), because adb cannot reset battery stats on this phone.
- **The app cancels its notification again after idle.** It polls its own active notifications every 50 ms for at most 5 s and cancels notification 1124 once the foreground-service flag is gone, because Android drops an app's cancel while the notification still has that flag, and `audio_service` clears the flag asynchronously. The `stop-loop` capsule's two last lines: `PASS mode=inapp stops=20 leftovers=0 services=0 wake_locks=0 repaired=5` and `PASS mode=notif stops=10 leftovers=0 services=0 wake_locks=0 repaired=0`. The leftover's absence rests on those 30 stops (5 of which needed the repair), not on a proof.
- **Focus has one owner at a time.** The finish step does not abandon focus while a request is in flight; `_begin` decides when the request returns (it starts playback, or abandons at idle), and a denied request is abandoned too.
- **The client answers for a dead engine isolate.** After the isolate's uncaught error, every `start` is answered with the error and the stopped state, so the handler always returns to idle; the isolate is not started again.
- **A permission request still pending when its activity lets go of the engine is answered there** (`false`, in `cleanUpFlutterEngine`), so the play that waits for it goes on.

## Rejected alternatives

- Relaying demand through the UI isolate (`flutter_pcm_sound`'s only shape): a UI stall starves the feed (probe G2).
- A clock-paced push (`mp_audio_stream`): a timer schedules audio, which unit 1's rule forbids.
- `flutter_soloud`'s realtime stream and its timer feeder: the same timer problem.
- A hand-written Kotlin service: `audio_service` already gives the foreground service, media session and notification.
- `playing: false` during a transient loss: the service would leave the foreground and could not be started again from the background.
- `stopForeground` through an own channel: the wake lock stays held.
- Reconfiguring `audio_service` before each stop.
- A fork of `audio_service`.
- An `audio_service` option for the leftover notification: none exists (`exitForegroundState` always detaches; `androidResumeOnClick` acts only in `onDestroy`, which never runs while the service is bound).
- Another call order in `PlaybackHandler` (`playing: false`, a wait, then idle): Dart cannot see the flag, so the wait is a guess and still races.
- `stopForeground(STOP_FOREGROUND_REMOVE)` from Kotlin before idle: `AudioService.instance` is package-private, so it needs a class in the plugin's package, close to a fork.
- A notification-listener callback: needs a permission the user must grant.
- Skipping the focus abandon when a replay is wanted: a stop and a third tap inside the same wait still end `request, abandon` and playing.
- Asking for focus again after the wait: focus is given up and taken again for nothing, and `_begin` would have to learn that an abandon was sent, which the phase does not show.
- Not finishing while a replay waits: a second place that must end a completed stop, to avoid a foreground bounce that a quick replay causes anyway.
- A lower `LeadTracker` tolerance: it changes `lib/src/sink/` and voids task 08's liveness proof.
- A process-wide pending permission result: it is never answered when no result comes, and a stale one would block the next request.

## Traps

- Host tests need a clang for `flutter_soloud`'s build hook: run them through `tool/test.sh`, which puts the NDK clang on PATH.
- Old plugins pinned to an old compileSdk need the compileSdk override in `android/build.gradle.kts`.
- A `bufferTriggerPosition` above 0.2 can stall the start of the pull stream.
- `onBuffering` does not report starvation, and the voice position keeps running during starvation.
- A `write` that completes without an event-queue turn starves the isolate's commands.
- Release builds need `keep.xml` and `android.r8.optimizedResourceShrinking=false`, or `audio_service` cannot find its icons and the foreground start throws.
- A stop that leaves `playing` true keeps the service, the notification and the wake lock.
- `dumpsys batterystats --reset` is refused for adb and still exits 0; the first unplugged window in the history is weeks old.
- Play rejects adb installs unless the phone was touched recently (or Play Protect scanning is off).
- `flutter drive` always installs, and uninstalls afterwards without `--keep-app-running`.
- This phone sometimes drops the logcat lines of a fresh process.
- An app's cancel of a notification that still has the foreground-service flag is dropped without an error.
- One clean stop proves nothing about a race that showed in 1 stop of 5.
- The 100-tap test never reaches idle; only the quick replays exercise the repair.
- `PlaybackNotification`'s id 1124 mirrors `audio_service`'s private `NOTIFICATION_ID` and must be rechecked on a plugin upgrade.
- `audio_session` 0.2.4 keeps a denied focus request and answers every later request `true` without asking Android until it is abandoned.
- A focus fake that completes in a microtask never interleaves with engine events, so a race test needs a gate.
- `pm grant` on every install hides the permission dialog from every device run.
- An uncaught error ends a spawned isolate while its `SendPort` still accepts messages.
- A `MethodChannel.Result` held by an activity is lost with that activity.
- On this vivo, the permission block's `EXIT` trap `pm grant` did not take effect after the Deny round (still `granted=false`); the verifier granted the permission by hand before the next capsule. Check the state after the block instead of trusting the trap.
- The soak's battery window starts at the unplug, and unplugging can turn the screen on: it stayed on for 10 min 47 s here. Check the history's `+screen`/`-screen` lines before reading the window as screen-off.

## Open

- A real phone call (telephony or VoIP) is unproven: the long interruption was a Clock countdown timer (`USAGE_ALARM`). The user plans a VoIP call test.
- Android 17 behaviour is unproven on a device.
- Voice counters beyond the tested hour are unproven.
- Headphone-unplug pause and headset resume are not built.
- `flutter_soloud` 5.3.1 was days old when chosen (5.3.2 followed on 2026-11-22).
- The final app name.
- An interruption that never ends keeps the service and its wake lock until the user stops.
- A permanent focus loss is proven by host tests only.
- How the CPU figure splits between core placement, core speed and the Dart code's own cost on ARM is not measured; the first next step above profiles it.
- A process started without `MainActivity` (a media button) has no `clear` handler, so the leftover notification can recur there.
- The notification repair gives up after 5 s; a flag still set then leaves the notification until the next stop.
- `call_watch.sh` passes on `FSTATE phase=playing` without checking that frames advance; the user's ears stood in.
- `lastError` is never cleared by a later successful play, so the debug screen keeps an old error text.
- `MeteredSink._stopwatchClock` duplicates `EngineHost._stopwatch`.
- The focus fix for a replay that overlaps a stop and the dead-engine answer are proven on the host only.
- The underrun counter keeps its one-chunk floor and its untracked start and end of each session.
- A dead engine isolate is not started again; Play shows the error until the app restarts.
- The Kotlin change that answers a permission request cut off by its activity has no automated test.
- The permission dialog's Allow and Deny were each shown once.
