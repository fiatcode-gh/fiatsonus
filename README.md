# fiatsonus

fiatsonus makes ambient soundscapes with code at play time: no recorded audio
and no network. Use it for anything: sleep, study, work, commute or focus.

## Status

Unit 1: the engine core and the waterfall soundscape, proven by offline
renders on desktop.

Unit 2 (platform-spike): the Android app plays the waterfall on a phone. The
engine runs in its own isolate and feeds `flutter_soloud`'s pull stream;
`audio_service` keeps playback going with the screen off as a foreground
service with a Stop notification; audio focus pauses and resumes it. A debug
screen has Play/Stop and the live counters. Measured on a vivo (Android 16):
one hour screen off with zero underruns, engine CPU 17.35 % of one core
(over the 5 % limit, so the record recommends a native core after profiling
the Dart engine on ARM), about 80 mAh/h for the whole phone. See
[docs/decisions/platform-spike.md](docs/decisions/platform-spike.md).

## Layout

- `packages/fiatsonus_engine`: the pure Dart engine.
- `apps/fiatsonus`: the Android app (package `dev.fiatcode.fiatsonus`):
  engine isolate, sink, playback service, debug screen, and the device tools
  under `tool/device/`.
- `docs/`: the design reference and the decision records.

## Checks

From the repository root:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
(cd packages/fiatsonus_engine && dart test -x soak)
(cd apps/fiatsonus && tool/test.sh)
```

`tool/test.sh` runs the app's host tests. `flutter_soloud`'s build hook needs
a clang, so the script puts the newest Android NDK's clang on PATH when none
exists. Do not call `flutter test` directly for the app, and start the app's
Dart tools as `dart tool/…/x.dart`, not `dart run`, for the same reason.

`dart test -t soak` in `packages/fiatsonus_engine` runs the engine's long-run
checks.

## Device

From `apps/fiatsonus`, with one phone on adb. Installs need a touch on the
phone (Play's install check); the scripts print `TOUCH THE PHONE NOW` and
retry once a minute for up to 30 minutes. Performance numbers count only
from release builds.

- `tool/device/install.sh [--profile]`: builds the release (or profile) APK,
  installs it and grants the notification permission.
- `tool/device/drive.sh integration_test/<file>.dart`: runs one on-device test
  in profile mode and keeps the app installed.
- `tool/device/play.sh`: starts the app and taps Play.
- `tool/device/ui_tap.sh <label>`: taps the on-screen node with that label.
- `tool/device/snapshot.sh <dir>`: writes one snapshot (stats, CPU, cores,
  AudioFlinger, battery, services) for the report.
- `dart tool/device/report.dart --t0 <dir> --t1 <dir>`: turns two snapshots
  into `RESULT` lines, a `CPU` line and a `PASS`/`FAIL` verdict.
- `tool/device/screen_off_run.sh <minutes> <outdir>`: play, screen off,
  report, stop and check that the service is gone.
- `tool/device/soak_begin.sh <outdir>` and `tool/device/soak_end.sh <outdir>`:
  the two halves of the one-hour unplugged soak with the battery window.
- `tool/device/call_watch.sh <outdir>`: watches a long interruption pause and
  resume playback with the service in the foreground.
- `tool/device/transient_check.sh <outdir>`: causes short focus losses with
  the screen off and checks pause, resume and the foreground service.
- `tool/device/notification_stop.sh <outdir>`: stops from the notification and
  checks the service and the notification are gone.
- `tool/device/stop_loop.sh <outdir> <n> <inapp|notif>`: repeats play and stop
  and counts leftover notifications, services and wake locks.
- `tool/device/foreground_watch.sh <outdir> [command]`: samples the service's
  foreground state and the notification's flag while a command runs.
- `integration_test/sink_smoke_test.dart`: the engine isolate plays the
  waterfall through the soloud sink.
- `integration_test/playback_flow_test.dart`: the app plays the waterfall
  through the foreground service.
- `integration_test/play_stop_stress_test.dart`: 100 fast play/stop taps, then
  ten quick replays after stop.

## Tools

All from `packages/fiatsonus_engine`:

```sh
dart run tool/render.dart --scape waterfall --seed 42 --secs 120 --param height=0.8
dart run tool/listening_set.dart
mkdir -p build && dart compile exe tool/bench.dart -o build/bench && build/bench --min-factor 150
dart compile exe tool/digest.dart -o build/digest && build/digest > build/digests.txt && build/digest --check build/digests.txt
dart compile exe tool/stage_bench.dart -o build/stage_bench && build/stage_bench
dart test -t soak
```

- `render.dart` writes one soundscape to a 16-bit WAV file under `out/`.
- `listening_set.dart` renders the listening set (defaults, each param at 0
  and 1, sweeps, a 10-minute file) and a `README.txt` with the sign-off
  questions to `out/listening/<scape>/`.
- `bench` measures the realtime factor of the full engine path and fails
  below the given median. The number counts only on the AOT build
  (`dart compile exe`); under `dart run` it reports but refuses
  `--min-factor`.
- `digest` renders 28 scripted cases (sessions with param changes, gain
  steps and fades, 5-minute runs, voice stealing) and prints one FNV-1a 64
  hash per case. `--check <file>` renders and compares with a saved list,
  `--compare <a> <b>` compares two lists (desktop or phone logcat) without
  rendering; both exit 1 on any difference. Hashes are per platform.
- `stage_bench` times each stage of the engine path (full master, the whole
  soundscape, the bus, each layer solo, reverb, limiter) and prints the
  shares computed from the per-stage medians as `FBENCH` lines.
- `dart test -t soak` runs the long-run checks (8 simulated hours per rate).

`out/` and `build/` are not committed.

## Design

Recipes, interfaces and decisions live in
[docs/procedural-ambient-sound-engine-design.md](docs/procedural-ambient-sound-engine-design.md).

## License

MIT. See [LICENSE](LICENSE).
