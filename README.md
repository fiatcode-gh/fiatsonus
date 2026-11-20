# fiatsonus

fiatsonus makes ambient soundscapes with code at play time: no recorded audio
and no network. Use it for anything: sleep, study, work, commute or focus.

## Status

Unit 1: the engine core and the waterfall soundscape, desktop offline
rendering only. No app yet.

## Layout

- `packages/fiatsonus_engine`: the pure Dart engine.
- `docs/`: the design reference.
- `apps/fiatsonus`: the future Flutter app (not created yet).

## Checks

From the repository root:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
```

From `packages/fiatsonus_engine`:

```sh
dart test -x soak   # fast suite
dart test -t soak   # long-run checks
```

## Design

Recipes, interfaces and decisions live in
[docs/procedural-ambient-sound-engine-design.md](docs/procedural-ambient-sound-engine-design.md).

## License

MIT. See [LICENSE](LICENSE).
