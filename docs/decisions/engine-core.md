# engine-core (unit 1): decisions

Unit 1 of fiatsonus: a pure-Dart procedural ambient sound engine plus the waterfall soundscape, proven offline on desktop. Work commits `a57eb0f..876eec6` on `feat/engine-core`.

The recipe and the engine's concrete numbers live in `docs/procedural-ambient-sound-engine-design.md` (see "Unit decisions: engine-core"). This record keeps only why, and what was rejected.

## Decisions and why

- **Engine first, platform later.** The pure-Dart core can be fully proven on desktop (offline renders, numeric checks, CPU benchmark). The Android playback questions (PCM plugin, background playback, real phone CPU) are unit 2.
- **Primitives on demand.** Only what the waterfall needs was built. `EventScheduler`, `Delay`, sine LFO, peaking and high-shelf filters wait for the soundscape that needs them, so their shape comes from a real use.
- **The master owns fades.** `Soundscape.stop`/`isSilent` from the original design moved to `Master`. One fade law (gain = u²) and one fault path for every soundscape, instead of each soundscape fading itself.
- **Own PRNG (xoshiro128\*\*), not `dart:math` `Random`.** Its sequence is not guaranteed stable across SDK versions, and determinism is a contract goal.
- **Determinism is claimed per platform and build mode only.** `sin`/`exp`/`pow` come from the platform maths library, so no golden audio hashes are committed; tests compare twin renders instead.
- **Zero allocation is proven on the AOT build** with the VM GC log over 8 simulated hours. JIT boxes doubles and collects garbage regardless, so JIT memory is not evidence. The soak ends with deliberate garbage to prove the log is live.
- **Click metric is relative** (largest jump over the RMS of recent jumps). Broadband noise has no fixed absolute jump limit; fades and param steps are additionally proven exactly against a twin render.
- **Loudness target −20 LUFS ±1** for the waterfall, ungated BS.1770. Set once; retuning changes the output trim, never the band.
- **Texture level raised from the design doc.** At the doc's "−30 dB per grain" the texture layer measured about 47 dB under the roar and was inaudible; it now sits about 14 LU under.

## Rejected alternatives

- Building every primitive in the design doc up front (YAGNI).
- A level-step click detector on short windows: it could not tell a 6 dB gain step from grain texture.
- A height-history twin test for the S8 reset: the filters converge within 45 ms, so it could never fail. A read-only `Waterfall.isQuiet` check proves the reset instead.
- Running the benchmark gate under JIT: JIT measured faster than AOT and would give a false pass.

## Traps

- **Benchmarks are load-sensitive.** A run beside a reviewer's builds measured 171×; idle, 240×. Measure on an idle machine.
- **Grain timing must be rate-free.** A pending gap stored in frames at the old rate stalled the cloud for minutes after a near-zero rate. Fixed in `876eec6`; later soundscapes with rates that sweep near zero rely on it.
- **A test that allocates into an unread field proves nothing:** the AOT compiler removes it. Allocation probes must read the value back.
- **Each soundscape needs its own S8 reset proof.** The master test only proves `reset()` is called.

## Open

- The 150× desktop target is a proxy for "< 5% of a low-end phone core"; unit 2 replaces it with a real phone measurement and decides Dart vs a native core.
- Parked review notes: a short-call steal test for `VoicePool`, duplicated CLI helpers in `tool/`, and two minor test-strength notes.
- Perception: a picture per soundscape in the app (unit 3) helps listeners match the sound, but the sound must hold up without it.
