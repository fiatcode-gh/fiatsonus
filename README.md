# fiatsonus

fiatsonus makes ambient soundscapes with code at play time: no recorded audio
and no network. Use it for anything: sleep, study, work, commute or focus.

## Status

Unit 1: the engine core and the waterfall soundscape, desktop offline
rendering only. No app yet.

## Layout

- `packages/fiatsonus_engine`: the pure Dart engine.
- `docs/`: the design reference.
- `apps/fiatsonus`: the Android app (engine host only so far).

## Checks

From the repository root:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
```

From `packages/fiatsonus_engine`:

```sh
dart test -x soak   # fast suite
dart test -t soak   # long-run checks
```

From `apps/fiatsonus`:

```sh
tool/test.sh        # host tests; puts an NDK clang on PATH when none exists
```

## Tools

All from `packages/fiatsonus_engine`:

```sh
dart run tool/render.dart --scape waterfall --seed 42 --secs 120 --param height=0.8
dart run tool/listening_set.dart
mkdir -p build && dart compile exe tool/bench.dart -o build/bench && build/bench --min-factor 150
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
- `dart test -t soak` runs the long-run checks (8 simulated hours per rate).

`out/` and `build/` are not committed.

## Design

Recipes, interfaces and decisions live in
[docs/procedural-ambient-sound-engine-design.md](docs/procedural-ambient-sound-engine-design.md).

## License

MIT. See [LICENSE](LICENSE).
