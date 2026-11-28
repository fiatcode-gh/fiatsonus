# engine-profiling (unit 2b): decisions

Unit 2b of fiatsonus: find where the engine's CPU (central processing unit) time goes on the phone, make it cheaper in Dart without changing one output sample, and settle the Dart-or-native question. Work commits `359bdbb` to `96c9e56` on `feat/engine-profiling`.

Every number below comes from a file named beside it. Paths are relative to `.flow/evidence/<head>/`, a local directory that is not committed. `H0` is the baseline head `96dfb83`; `HF` is the final head `96c9e56`. A value marked "derived" is arithmetic on the named numbers, not a tool output.

## Summary

The question: the waterfall used 17.35 % of one phone core in unit 2 (5.8 times realtime), against 240 times realtime on one desktop core in unit 1. Where does that time go, and can Dart get under the 5 % budget without changing the sound?

The answer:

1. About 2.3 times of the gap is the Dart code on an ARM big core at full speed against the desktop. Most of the rest is where Android runs the engine: on a little Cortex-A55 core at its lowest frequency, 691.2 MHz, for 96.6 % of the baseline run and 98.4 % of the final run.
2. Four byte-identical fixes made the engine 1.17 times as fast on the desktop and 1.06 times as fast on the phone bench, but the paced phone figure fell only from 17.31 % to 15.95 % over 10 minutes.
3. The user stopped the fix loop for diminishing returns with allowed ideas left; the two last instruction-count cuts each gained 0.055 points.

**Decision: a native core.** The final 10-minute run measured `render_ratio_pct=15.95`, which is not under 5 %, so the contract's rule gives the native-core decision (`96c9e56/phone-paced-10min/report.txt`).

## How it was measured

- **Phone.** The vivo I2219 of unit 2, Android 16. Its system on chip is an SM6450: cpu0–3 are Cortex-A55 cores (policy0, 691.2 to 1804.8 MHz in 8 steps), cpu4–7 are Cortex-A78 cores (policy4, 691.2 to 2208 MHz in 10 steps) (`96c9e56/burst-spike/facts/cpufreq.txt`). The app sets no thread affinity and no priority.
- **Desktop.** The engine's command-line tools compiled ahead-of-time (AOT) with `dart compile exe`, on one x64 core.
- **Builds on the phone.**
  - The normal release build of the app, for the paced runs.
  - The release build of the bench target (`--target=lib/bench_main.dart`, mode `measure`), for the stage timings and the phone digests.
  - The profile build of the bench target (mode `loop`) and the profile build of the app, for the CPU profiles only.
- **Bench target and stages.** `lib/bench_main.dart` is its own entry point, so `lib/main.dart` never imports it. It runs in a spawned isolate with no audio output. It first logs the 28 render digests, then times nine stages five times each, 60 s of audio per run:
  - `full`: `Master.render` on the waterfall, in 2048-frame calls;
  - `scape`: the waterfall alone; `bus`: the waterfall with no layer, so the distance filter, reverb, width and gain run on a silent bus;
  - `roar`, `body`, `spray`, `texture`: the waterfall with one layer;
  - `reverb` and `limiter`: each primitive alone.
- **Shares, by subtraction.** Each layer share is its stage minus `bus`. `reverb` is the reverb stage. `bus_other` is `bus` minus `reverb`. `master` is `full` minus `scape`. `unexplained` is `scape` minus `bus` minus the four layer shares. When `unexplained` exceeds 5 % of `full`, `bench_report.dart` prints `UNRELIABLE split` and the profile's function table decides. A share is marked `OUTLIER` when its phone-to-desktop ratio is at least 1.5 times the ratio of `full`.
- **Paced run.** `tool/device/screen_off_run.sh <minutes>` plays the waterfall, turns the screen off, takes two snapshots, prints the report, taps Stop and checks that the service, the notification and the wake lock are gone. `render_ratio_pct` is the engine's render wall time over the wall time, measured around `Master.render` only. 3-minute pairs judged the fix loop; the 10-minute run judges the contract.
- **Thread residency.** Each snapshot saves every thread's `time_in_state` (CPU time per cluster and frequency). The report prints the engine thread's cluster shares (`engine_cluster_pct`), its frequency shares (`engine_freq_pct`) and `render_ratio_at_max_freq_pct`, the ratio scaled as if each cluster had run at its top frequency.
- **CPU profile.** The Dart virtual machine (VM) service's CPU samples (`getCpuSamples`, the data the DevTools CPU profiler shows), captured headless over `adb forward`, one sample per 1000 µs. `cpu_top.txt` lists the 40 functions with the most exclusive samples. `inlined_top.txt` splits each sample's leaf by the functions the compiler inlined into it.
- **Digests.** 28 scripted renders, each hashed with FNV-1a 64 over every 16-bit output sample (section "Byte identity").

What each instrument cannot see:

- The bench runs where Android puts a busy foreground thread: on cpu4 at 2208 MHz for every stage (`96dfb83/breakdown.md`). The paced engine ran on cpu0 at 691.2 MHz. So the bench measures the code, and only the paced run measures what playback costs.
- The shares come from subtraction. They are not additive here: the `bus` stage runs on a silent bus, and the baseline's `unexplained` share was −12.2 % on the phone and −30.4 % on the desktop.
- `render_ratio_at_max_freq_pct` is an estimate. It assumes speed proportional to frequency inside a cluster.
- The profile build is not the release build. Its factors are recorded beside each profile and never compared with release numbers. The bench profile also holds the noise-table generation that the `loop` mode repeats before every 10-s run (`NoiseTable._channel`); that is a bench artefact, with 0 samples in the playback profile.

## Baseline

`H0` = `96dfb83`, captured on 2026-11-23. Its audio path equals `c6fa243`'s, the head that unit 2 measured. This audio-path guard printed nothing and exited 0 before and after the campaign:

```sh
git diff --stat --exit-code c6fa243 -- packages/fiatsonus_engine/lib/src/core packages/fiatsonus_engine/lib/src/master packages/fiatsonus_engine/lib/src/primitives packages/fiatsonus_engine/lib/src/soundscapes apps/fiatsonus/lib/main.dart apps/fiatsonus/lib/src/engine apps/fiatsonus/lib/src/sink apps/fiatsonus/lib/src/playback apps/fiatsonus/android
```

Desktop `bench`: `min=240.9 median=243.4 max=244.2` (`96dfb83/desktop/bench.txt`).

Stages, release builds (`96dfb83/breakdown.md`; the desktop factor of `full` is the median of the five `stage=full` runs in `96dfb83/desktop/stage_bench.txt`). Every phone stage ran on cpu4 at 2207–2208 MHz.

| Stage | Phone µs per audio second (min–max) | Phone factor | Desktop µs per audio second | Phone/desktop |
|---|---|---|---|---|
| full | 9574 (9516–9621) | 104.4 | 4124 (factor 242.5) | 2.3 |
| scape | 8182 (8066–8274) | 122.2 | 3363 | 2.4 |
| bus | 2011 (2008–2015) | 497.3 | 779 | 2.6 |
| roar | 3600 (3571–3708) | 277.8 | 1573 | 2.3 |
| body | 2938 (2921–3028) | 340.4 | 1167 | 2.5 |
| spray | 3350 (3324–3387) | 298.5 | 1692 | 2.0 |
| texture | 5491 (5487–5528) | 182.1 | 2520 | 2.2 |
| reverb | 1316 (1308–1328) | 759.9 | 528 | 2.5 |
| limiter | 253 (251–254) | 3952.6 | 127 | 2.0 |

Shares (`96dfb83/breakdown.md`). No row is marked `OUTLIER`. The file prints `UNRELIABLE split phone: unexplained -12.2 % of full` and the same for the desktop at −30.4 %, so these shares are context only.

| Share | Phone µs/s | Phone % | Desktop µs/s | Desktop % | Phone/desktop |
|---|---|---|---|---|---|
| roar | 1589 | 16.6 | 794 | 19.3 | 2.0 |
| body | 927 | 9.7 | 388 | 9.4 | 2.4 |
| spray | 1339 | 14.0 | 913 | 22.1 | 1.5 |
| texture | 3480 | 36.3 | 1741 | 42.2 | 2.0 |
| reverb | 1316 | 13.7 | 528 | 12.8 | 2.5 |
| bus_other | 695 | 7.3 | 251 | 6.1 | 2.8 |
| master | 1392 | 14.5 | 761 | 18.5 | 1.8 |
| unexplained | −1164 | −12.2 | −1252 | −30.4 | 0.9 |
| full | 9574 | 100.0 | 4124 | 100.0 | 2.3 |

The paced 10-minute run, normal release, screen off (`96dfb83/phone-paced-10min/report.txt`):

- `render_ratio_pct=17.31`, `process_cpu_pct=19.41`.
- `top_threads=DartWorker:17.42,AudioTrack:1.92,tcode.fiatsonus:0.06,binder:32582_2:0.00,Signal Catcher:0.00`.
- `max_render_us=12561`; `underruns=0`, `starved_us=0`, `af_underruns=0`, `deficit_ms=-26.4`; `foreground=true`; verdict `PASS` after `CPU MISS render_ratio_pct=17.31 limit_pct=5.00`.
- Engine thread: `engine_cluster_pct=cpu0:100.0,cpu4:0.0`, `engine_mean_khz=cpu0:719431`, `engine_freq_pct=cpu0@691200:96.6,cpu0@1804800:1.7`, `render_ratio_at_max_freq_pct=6.90`.
- 9 minutes after screen off: `mWakefulness=Asleep` (`96dfb83/phone-paced-10min/wakefulness.txt`).

The app-path figure is the engine thread's CPU minus the render ratio: 17.42 − 17.31 = 0.11 points (same file). It is under the plan's 1.00-point line, so the app path was not worked on.

The branch line of the baseline: `BRANCH engine=yes app=no placement=minor`. Placement is `minor` because `render_ratio_at_max_freq_pct=6.90` is not under 5.00.

Top 15 of the bench profile (`96dfb83/phone-profile-bench/profile/cpu_top.txt`, 27019 samples; profile-build factor of `full` min 16.8, median 97.7, max 103.4 over 578 runs, `96dfb83/phone-profile-bench/bench.txt`):

| Exclusive % | Inclusive % | Kind | Function |
|---|---|---|---|
| 18.7 | 30.0 | Dart | NoiseTable._channel (bench artefact) |
| 14.6 | 55.9 | Dart | Waterfall.render |
| 11.4 | 11.4 | Dart | Biquad.processStereo |
| 9.6 | 10.3 | Dart | Biquad.processMono |
| 8.7 | 8.7 | Dart | Reverb.process |
| 8.1 | 18.8 | Dart | VoicePool.render |
| 5.5 | 65.8 | Dart | Master._renderBlock |
| 4.7 | 4.7 | Dart | Envelope.process |
| 3.2 | 3.2 | Dart | Limiter.process |
| 3.0 | 3.1 | Dart | `Float32List` `fillRange` |
| 2.5 | 2.5 | Native | `libc.so+0xb29d8` |
| 1.9 | 1.9 | Dart | Rng.nextU32 |
| 0.8 | 66.6 | Dart | Master.render |
| 0.3 | 0.3 | Native | sin |
| 0.1 | 0.2 | Dart | VoicePool.spawn |

Top 15 of the playback profile, isolate `engineIsolateMain` (`96dfb83/phone-profile-playback/cpu_top.txt`, 4232 samples):

| Exclusive % | Inclusive % | Kind | Function |
|---|---|---|---|
| 24.4 | 84.0 | Dart | Waterfall.render |
| 16.0 | 16.0 | Dart | Biquad.processStereo |
| 14.9 | 28.2 | Dart | VoicePool.render |
| 11.2 | 11.2 | Dart | Reverb.process |
| 8.2 | 8.2 | Dart | Biquad.processMono |
| 7.4 | 95.1 | Dart | Master._renderBlock |
| 5.1 | 5.1 | Dart | Envelope.process |
| 4.9 | 5.0 | Dart | `Float32List` `fillRange` |
| 1.9 | 1.9 | Dart | Limiter.process |
| 1.2 | 96.3 | Dart | Master.render |
| 0.2 | 0.2 | Native | log |
| 0.2 | 30.3 | Dart | Waterfall._renderTexture |
| 0.1 | 0.4 | Dart | VoicePool.spawn |
| 0.1 | 0.1 | Dart | RangeError.checkValidRange |
| 0.1 | 0.1 | Native | pow |

The inlined split of the playback profile (`96dfb83/phone-profile-playback/inlined_top.txt`, leaf % of 4232 samples): `Biquad.processStereo` 15.9, `addRamp` 12.1 (inlined in `Waterfall.render`), `VoicePool.render` 10.7, `Reverb.process` 8.9, `Biquad.processMono` 8.2, `Waterfall.render` own 5.4, `Envelope.process` 5.1, `fillRange` 4.9 (from `clearBlock`), `Master._renderBlock` own 4.9, `NoiseTable.read` 4.4, `NoiseTable.readMono` 3.9, `NoiseTable.mix` 2.5, `Master._toInt16` 2.5.

## Where the gap came from

Unit 2 put the phone at 5.8 times realtime and the desktop at 240 times, about 42 times apart (`docs/decisions/platform-spike.md`). This unit splits that gap:

- **Dart's ARM code on a big core at full speed: 2.3 times.** The phone bench ran `full` on cpu4 (Cortex-A78) at 2208 MHz at factor 104.4, against 242.5 on the desktop (`96dfb83/breakdown.md`). No share stood out: every layer, reverb, bus and master share has a phone-to-desktop ratio between 1.5 and 2.8, and none is marked `OUTLIER`. So no single construct is far more expensive on ARM; the whole engine is.
- **Core type and frequency: the rest.** Playback ran the engine on cpu0 (Cortex-A55) for 100 % of its time and at 691.2 MHz for 96.6 % of it (`96dfb83/phone-paced-10min/report.txt`). At that place, 17.31 % is about 5.8 times realtime (derived: 100 / 17.31). The same 104.4 bench factor on the big core is about 18 times faster (derived: 104.4 / 5.8). The frequency part of that is estimated by `render_ratio_at_max_freq_pct=6.90`: at the little cluster's top frequency the ratio would be about 2.5 times lower (derived: 17.31 / 6.90). The remaining factor, about 7 times (derived: 18 / 2.5), is the in-order A55 core against the A78, together with everything else that differs between the bench and playback.

A likely reason for the place, read from the governor's behaviour and not measured: a thread that renders 42.7 ms of audio and then waits looks like a light periodic load, and such a load can sit on a little core at its lowest frequency.

The candidate hypotheses of the plan, checked against the profile and the ARM64 disassembly (`96dfb83/desktop/arm64/<Class.method>.txt`):

| Hypothesis | Held? | What showed it | Outcome |
|---|---|---|---|
| H1 `_toInt16`'s `round()` is a C call per sample | yes | two `blr x16` runtime leaf calls in `Master._renderBlock`; `Master._toInt16` 2.5 % leaf | removed in row 04; paced miss |
| H2 a bounds check per typed-list access | yes | 44 `b.hs` in `Waterfall.render` | removed from two loops in row 07; paced gain 0.055 points, a miss |
| H3 an interrupt check per loop iteration | yes | 15 in `Waterfall.render`, one per frame in each biquad loop | unrolled in rows 08 (miss) and 09 (kept) |
| H4 a float conversion (`fcvt`) per `Float32List` load and store | yes | 46 `fcvt` in `Waterfall.render` | no allowed idea: removing one changes samples |
| H5 `flushDenormal` compiles to several branches | yes | 40 `fcmp` in `Reverb.process`; `flushDenormal` and `_Double.abs` leaf samples from it | kept (row 05) |
| H6 the limiter's divisions and branches | small | `Limiter.process` 1.9 % playback, 3.2 % bench | not tried |
| H7 the texture's per-voice passes | yes, large | texture share 36.3 %; `VoicePool.render` 14.9 %, `Biquad.processMono` 8.2 %, `Envelope.process` 5.1 % | its noise read became a copy in row 06; the unrolls were not tried |
| H8 a wrap compare per sample in the noise reads | yes | `NoiseTable.read` 4.4 %, `readMono` 3.9 %, `mix` 2.5 % leaf | kept (row 06) |
| H9 the pass count in `Waterfall.render` | yes | `addRamp` 12.1 % leaf | one stereo ramp per layer, rows 01 and 01r: miss |
| H10 the master's guard, clamp and copy passes | small | `Master.render` 1.2 % | not tried |
| H11 the app path around the render | no | 0.11 points | not worked on |
| H12 per-grain maths | no | `log` 0.2 %, `pow` 0.1 %, `sin` 0.3 % (bench) | none |
| H13 placement and frequency | yes | cpu0 100 %, 691.2 MHz 96.6 %; estimate at the top frequency 6.90 % | measured, never set |
| H14 (new) generic `fillRange` for zero fills | yes | `fillRange` 4.9 % leaf, all from `clearBlock` | kept (row 02r) |

## What changed and why

One row per kept commit. Desktop `full` is the median factor of five `stage=full` runs; phone `full` is the median µs per audio second of the release bench; the paced ratio after is the mean of the two 3-minute runs at the new head. Each row's evidence is listed in the ledger row of the same iteration.

| Commit | Iteration and hypothesis | Class | Stage | Desktop `full` before → after | Phone `full` µs/s before → after | Paced ratio after |
|---|---|---|---|---|---|---|
| `b816c64` clear blocks with setRange from a zero block | 02r, H14: `clearBlock` runs the generic `fillRange` loop; a `setRange` from a shared zero block does the same zero fill as one block copy | A | texture | 242.5 (4124 µs/s) → 253.5 (3945) | 9574 → 9572 | 16.155 (16.18, 16.13; `b816c64/paced-3min`, `paced-3min-2`) |
| `9b609e6` flush denormals without abs() | 05, H5: `x.abs() < f` branches on the sign; `(x − f) · (x + f) < 0.0` gives the same double for every input with one rarely taken branch | B | reverb | 253.5 (3945) → 274.0 (3649) | 9572 → 9504; reverb stage −7.4 % | 16.265 (16.16, 16.37; `9b609e6/paced-3min`, `paced-3min-2`) |
| `e100da3` read noise tables in straight runs around the wrap | 06, H8: the noise reads test the table wrap on every frame; straight runs that end at the wrap remove the test, and the mono read becomes a `setRange` copy | A | texture | 274.0 (3649) → 286.7 (3488) | 9504 → 9185 | 15.970 (15.83, 16.11; `e100da3/paced-3min-r2`, `paced-3min-r2-2`) |
| `96c9e56` unroll the gain ramp by four frames | 09, H3: `addRamp` pays an interrupt check, a loop test and an increment per frame; four frames per iteration, same operations in the same order | A | roar | 286.7 (3488) → 291.8 (3427) | 9185 → 9027; roar stage −5.3 % | 16.015 (15.90, 16.13; `96c9e56/paced-3min`, `paced-3min-2`) |

Class A changes only the code's shape. Class B uses an exact identity, proven by its own edge-value tests. Class C skips work whose result is unused; no class-C idea was tried (the ledger names one, skipping a clear whose block is fully overwritten before it is read). Row 02r was kept on the paced path: candidate mean 16.165 against the `H0` pair's 16.945, a gain of 0.78 points (`96dfb83/iter-02r-clear-setrange/paced_judge.txt`). Rows 05, 06 and 09 were kept on the bench path.

## Tried and dropped

| Iteration | Hypothesis | Class | Numbers | Why dropped |
|---|---|---|---|---|
| 01 | H9: one stereo ramp per layer instead of two mono ramps | A | desktop `full` 4124 → 4042 µs/s; phone 9574 → 9505 (−0.7 %) | under the first rules the phone bench missed (under 2 %, no stage −5 %); judged again as 01r (`96dfb83/iter-01-ramp-stereo`) |
| 01r | the same, recreated after amendment 1 | A | desktop 4124 → 3993; phone 9574 → 9541; paced 16.54, 16.83, mean 16.685 against 16.945: gain 0.26 points | paced gain under 0.50 points (`96dfb83/iter-01r-ramp-stereo/paced_judge.txt`) |
| 02 | H14: `clearBlock` as `setRange` from a zero block | A | desktop 4124 → 3880 (−5.9 %); phone 9574 → 9717 (+1.5 %) | a phone bench gate that lay inside the bench's own noise (two runs of one APK: 9574 and 10027); judged again as 02r and kept (`96dfb83/iter-02-clear-setrange`) |
| 03 | `Biquad.processStereo`: interleave the left and right statements so the in-order A55 overlaps the two chains | A | desktop 3945 → 4057 (+2.8 %); phone 9572 → 9699; paced 16.14, 16.26, mean 16.200 against 16.155: −0.045 points | paced miss (`b816c64/iter-03-biquad-interleave`) |
| 04 | H1: round to 16 bits without the C `round` call | B | coding 1 made desktop `full` 4597 µs/s (+16.5 %) and never went to the phone; coding 2: desktop 3945 → 3866, phone 9572 → 9883 (+3.2 %); paced 16.26, 16.59, mean 16.425 against 16.155: −0.27 points | paced miss (`b816c64/iter-04-toint16-trunc`) |
| 07 | H2: length guards drop the bounds checks in `processStereo` and `addRamp` (loops 46 → 44 and 29 → 25 instructions per frame) | A | desktop 3488 → 3434; phone 9185 → 9677 (+5.4 %); paced 15.97, 15.86, mean 15.915 against 15.970: 0.055 points | paced miss (`e100da3/iter-07-length-guards/paced_judge.txt`) |
| 08 | H3: unroll the biquad loops by four frames (46 → 40.75 and 27 → 21.75 instructions per frame) | A | desktop 3488 → 3533 (+1.3 %); phone 9185 → 9591 (+4.4 %); paced 15.80, 16.03, mean 15.915 against 15.970: 0.055 points | paced miss (`e100da3/iter-08-biquad-unroll/paced_judge.txt`) |

Every dropped attempt matched both digest sets. None was committed.

## Sound-changing candidates, not tried

None was compiled. The loop did not stop for lack of byte-identical ideas: the user stopped it under rule 9(d), and the allowed ideas left are listed under "Decisions and why".

The forbidden ideas that the work named, each with the share it addresses:

- H4: every `Float32List` load and store is an `fcvt`, and removing one or merging two passes over a buffer changes samples. Share: not measured (it is spread over every loop).
- Moving or removing the denormal flushes of `Reverb.process`: `flushDenormal` 6.8 % leaf of the bench profile at `e100da3` (`e100da3/phone-profile-bench/profile/inlined_top.txt`).

Each one needs a recipe change through the design doc, in a later unit.

## Final

`HF` = `96c9e56`, captured on 2026-11-28 from a clean tree. Desktop `bench`: `min=275.5 median=279.7 max=281.6` (`96c9e56/host-gates/summary.txt`).

Stages, before (`96dfb83/breakdown.md`) and after (`96c9e56/breakdown.md`). Every phone stage still ran on cpu4 at 2202–2208 MHz.

| Stage | Phone µs/s before → after | Phone factor before → after | Desktop µs/s before → after | Phone/desktop before → after |
|---|---|---|---|---|
| full | 9574 → 9018 (8856–9118) | 104.4 → 110.9 | 4124 → 3518 (factor 242.5 → 284.3) | 2.3 → 2.6 |
| scape | 8182 → 7545 | 122.2 → 132.5 | 3363 → 2819 | 2.4 → 2.7 |
| bus | 2011 → 2009 | 497.3 → 497.8 | 779 → 710 | 2.6 → 2.8 |
| roar | 3600 → 3349 | 277.8 → 298.6 | 1573 → 1153 | 2.3 → 2.9 |
| body | 2938 → 2657 | 340.4 → 376.4 | 1167 → 951 | 2.5 → 2.8 |
| spray | 3350 → 2644 | 298.5 → 378.2 | 1692 → 952 | 2.0 → 2.8 |
| texture | 5491 → 4621 | 182.1 → 216.4 | 2520 → 1804 | 2.2 → 2.6 |
| reverb | 1316 → 1154 | 759.9 → 866.6 | 528 → 434 | 2.5 → 2.7 |
| limiter | 253 → 278 | 3952.6 → 3597.1 | 127 → 144 | 2.0 → 1.9 |

The speed-up of `full` is 1.06 on the phone and 1.17 on the desktop (`96c9e56/breakdown.md`, "vs base"). The desktop factor 284.3 is the median of `96c9e56/desktop/stage_bench.txt` (279.0, 281.4, 284.3, 284.7, 288.3).

Shares, µs/s with % of `full` in brackets. No row is marked `OUTLIER`. Unlike the baseline, `96c9e56/breakdown.md` prints no `UNRELIABLE split` line.

| Share | Phone before | Phone after | Desktop before | Desktop after | Phone/desktop after |
|---|---|---|---|---|---|
| roar | 1589 (16.6) | 1340 (14.9) | 794 (19.3) | 443 (12.6) | 3.0 |
| body | 927 (9.7) | 648 (7.2) | 388 (9.4) | 241 (6.9) | 2.7 |
| spray | 1339 (14.0) | 635 (7.0) | 913 (22.1) | 242 (6.9) | 2.6 |
| texture | 3480 (36.3) | 2612 (29.0) | 1741 (42.2) | 1094 (31.1) | 2.4 |
| reverb | 1316 (13.7) | 1154 (12.8) | 528 (12.8) | 434 (12.3) | 2.7 |
| bus_other | 695 (7.3) | 855 (9.5) | 251 (6.1) | 276 (7.8) | 3.1 |
| master | 1392 (14.5) | 1473 (16.3) | 761 (18.5) | 699 (19.9) | 2.1 |
| unexplained | −1164 (−12.2) | 301 (3.3) | −1252 (−30.4) | 89 (2.5) | 3.4 |
| full | 9574 (100.0) | 9018 (100.0) | 4124 (100.0) | 3518 (100.0) | 2.6 |

Top 15 of the bench profile, before and after (`96dfb83/phone-profile-bench/profile/cpu_top.txt`, 27019 samples; `96c9e56/phone-profile-bench/profile/cpu_top.txt`, 27107 samples). Exclusive % in brackets. The profile-build factor of `full` after: min 17.2, median 108.7, max 116.5 over 632 runs (`96c9e56/phone-profile-bench/bench.txt`).

| Rank | Before | After |
|---|---|---|
| 1 | NoiseTable._channel (18.7) | NoiseTable._channel (20.1) |
| 2 | Waterfall.render (14.6) | Biquad.processStereo (12.3) |
| 3 | Biquad.processStereo (11.4) | Biquad.processMono (10.1) |
| 4 | Biquad.processMono (9.6) | Reverb.process (9.1) |
| 5 | Reverb.process (8.7) | Master._renderBlock (6.4) |
| 6 | VoicePool.render (8.1) | addRamp (5.5) |
| 7 | Master._renderBlock (5.5) | VoicePool.render (5.1) |
| 8 | Envelope.process (4.7) | Envelope.process (4.9) |
| 9 | Limiter.process (3.2) | Waterfall.render (4.0) |
| 10 | `fillRange` (3.0) | Limiter.process (3.5) |
| 11 | `libc.so+0xb29d8` (2.5) | NoiseTable.read (3.0) |
| 12 | Rng.nextU32 (1.9) | `libc.so+0xb29d8` (2.7) |
| 13 | Master.render (0.8) | Rng.nextU32 (1.9) |
| 14 | sin (0.3) | NoiseTable.mix (1.4) |
| 15 | VoicePool.spawn (0.1) | NoiseTable.readMono (1.2) |

Top 15 of the playback profile, before and after (`96dfb83/phone-profile-playback/cpu_top.txt`, 4232 samples; `96c9e56/phone-profile-playback/cpu_top.txt`, 3877 samples). Exclusive % in brackets.

| Rank | Before | After |
|---|---|---|
| 1 | Waterfall.render (24.4) | Biquad.processStereo (15.5) |
| 2 | Biquad.processStereo (16.0) | VoicePool.render (13.1) |
| 3 | VoicePool.render (14.9) | Reverb.process (13.1) |
| 4 | Reverb.process (11.2) | addRamp (10.6) |
| 5 | Biquad.processMono (8.2) | Master._renderBlock (9.6) |
| 6 | Master._renderBlock (7.4) | Biquad.processMono (9.3) |
| 7 | Envelope.process (5.1) | Waterfall.render (6.7) |
| 8 | `fillRange` (4.9) | Envelope.process (5.6) |
| 9 | Limiter.process (1.9) | NoiseTable.read (5.4) |
| 10 | Master.render (1.2) | NoiseTable.mix (3.1) |
| 11 | log (0.2) | Limiter.process (1.6) |
| 12 | Waterfall._renderTexture (0.2) | Master.render (1.2) |
| 13 | VoicePool.spawn (0.1) | NoiseTable.readMono (1.0) |
| 14 | RangeError.checkValidRange (0.1) | Waterfall._renderTexture (0.3) |
| 15 | pow (0.1) | sin (0.2) |

After the fixes, `addRamp` and the noise reads have rows of their own: the compiler no longer inlines them into `Waterfall.render`. `fillRange` left the table. In the playback profile `Master.render` still holds 96.6 % of the samples inclusive, so the render path is still the whole cost.

The 10-minute run at `HF`: normal release, screen off, one run (`96c9e56/phone-paced-10min/report.txt` unless named otherwise). It passed functionally, so the rerun rule did not apply.

| Measure | Before (`96dfb83`) | After (`96c9e56`) |
|---|---|---|
| Wall time | 602.400 s | 602.470 s |
| `CPU` line | `CPU MISS render_ratio_pct=17.31 limit_pct=5.00` | `CPU MISS render_ratio_pct=15.95 limit_pct=5.00` |
| Engine CPU (`render_ratio_pct`) | 17.31 % | 15.95 % |
| Process CPU (`process_cpu_pct`) | 19.41 % | 18.30 % |
| Top threads | `DartWorker` 17.42 %, `AudioTrack` 1.92 %, `tcode.fiatsonus` 0.06 % | `DartWorker` 16.28 %, `AudioTrack` 1.94 %, `tcode.fiatsonus` 0.07 % |
| App-path figure (engine thread − render ratio) | 0.11 points | 0.33 points |
| `max_render_us` | 12561 | 15451 |
| `underruns` | 0 | 0 |
| Starved time (`starved_us`) | 0 | 0 |
| AudioFlinger underruns (`af_underruns`) | 0 | 0 |
| Frame deficit (`deficit_ms`) | −26.4 ms over 599.040 s of audio | −235.7 ms over 602.100 s of audio; bound 420.5 ms (derived: 300 ms + 0.0002 × 602.470 s) |
| `overlaps`, `faults` | 0, 0 | 0, 0 |
| Engine and device rate | 48000, 48000 | 48000, 48000 |
| Foreground at t1 | `true` | `true` |
| Engine thread cluster | cpu0 100.0 %, cpu4 0.0 % | cpu0 100.0 %, cpu4 0.0 % |
| Engine thread frequency | 691.2 MHz 96.6 %, 1804.8 MHz 1.7 %; mean 719.4 MHz | 691.2 MHz 98.4 %; mean 702.5 MHz |
| `render_ratio_at_max_freq_pct` | 6.90 | 6.21 |
| Wakefulness 9 minutes after screen off | `Asleep` | `Asleep` (`96c9e56/phone-paced-10min/wakefulness.txt`) |
| Verdict | `PASS` | `PASS` |
| Stop block | service and notification gone, wake lock released | `service and notification gone; wake lock released`, `paced exit=0` (`96c9e56/phone-paced-10min.log`); the notification file is empty |

The change is −1.36 points over 10 minutes. The user listened to the first minute at `HF`: "first minute is good, no cuts, no clicks". That gates nothing; the digests prove the sound.

## Byte identity

The 28 cases render the waterfall through the master in 2048-frame calls and hash every 16-bit output sample in order (FNV-1a 64). The `session` cases (24 seconds each) cover both rates, the seeds 1, 42 and 20261123 and four param sets (`default`; `low` with every param 0; `high` with every param 1; `mixed`). Each session plays a fade-in, moves all params at 6 s, steps the gain to 0.5 at 9 s, stops at 12 s and starts again at 13 s, stops with a 200 ms fade at 16 s, restarts at 17 s, drives the limiter with gain 4.0 at 20 s and stops with a 5 ms fade at 23 s. The `long` cases run 300 s of steady state, so the noise tables wrap. The `poolSteal` cases spawn 24 grains per block for 40 blocks to force voice stealing, and hash the voice pool's float output.

The final head's digests equal the baseline's on each platform:

- Desktop: `DIGEST MATCH cases=28` (`96c9e56/desktop/digest_check.txt`, `build/digest --check` against `96dfb83/desktop/digests.txt`). `96c9e56/desktop/digests.txt` is also `cmp`-equal to that file.
- Phone: `DIGEST MATCH cases=28` (`96c9e56/phone-bench-release/digest_check.txt`, `digest.dart --compare` of `96dfb83/phone-bench-release/digests.txt` with `96c9e56/phone-bench-release/digests.txt`).

Every one of the 28 hashes is the same in all four files (desktop and phone, `96dfb83` and `96c9e56`):

| Case | Frames | Desktop hash | Phone hash |
|---|---|---|---|
| session-r44100-s1-default | 1058400 | c0a98c0d2f7c2d18 | c0a98c0d2f7c2d18 |
| session-r44100-s1-low | 1058400 | 3c8626aec4549e8b | 3c8626aec4549e8b |
| session-r44100-s1-high | 1058400 | 15787223951ca7da | 15787223951ca7da |
| session-r44100-s1-mixed | 1058400 | 24a79469f0e15dab | 24a79469f0e15dab |
| session-r44100-s42-default | 1058400 | bd8241f04b47e130 | bd8241f04b47e130 |
| session-r44100-s42-low | 1058400 | d871ed1de2d868a4 | d871ed1de2d868a4 |
| session-r44100-s42-high | 1058400 | e35633f9ef25284a | e35633f9ef25284a |
| session-r44100-s42-mixed | 1058400 | 3bbe61e744ed05d6 | 3bbe61e744ed05d6 |
| session-r44100-s20261123-default | 1058400 | f6bafc14089ac9ec | f6bafc14089ac9ec |
| session-r44100-s20261123-low | 1058400 | 7c0f9efcff46a67f | 7c0f9efcff46a67f |
| session-r44100-s20261123-high | 1058400 | a137e24629d1b85e | a137e24629d1b85e |
| session-r44100-s20261123-mixed | 1058400 | 688397792759f01a | 688397792759f01a |
| session-r48000-s1-default | 1152000 | deb0d0ce3e270216 | deb0d0ce3e270216 |
| session-r48000-s1-low | 1152000 | 44786e0ab8d86574 | 44786e0ab8d86574 |
| session-r48000-s1-high | 1152000 | 82584252fc26de27 | 82584252fc26de27 |
| session-r48000-s1-mixed | 1152000 | bfe18d75a977faab | bfe18d75a977faab |
| session-r48000-s42-default | 1152000 | 26f3325b17e06a03 | 26f3325b17e06a03 |
| session-r48000-s42-low | 1152000 | 1b353b22926f408a | 1b353b22926f408a |
| session-r48000-s42-high | 1152000 | 811ededf741158e4 | 811ededf741158e4 |
| session-r48000-s42-mixed | 1152000 | 38f7b499cc544cbe | 38f7b499cc544cbe |
| session-r48000-s20261123-default | 1152000 | 0ee5d7dd7f3372a3 | 0ee5d7dd7f3372a3 |
| session-r48000-s20261123-low | 1152000 | 12c979fab18f2704 | 12c979fab18f2704 |
| session-r48000-s20261123-high | 1152000 | ce0dfd05e62bd3fc | ce0dfd05e62bd3fc |
| session-r48000-s20261123-mixed | 1152000 | 866006ac7b8bd5e2 | 866006ac7b8bd5e2 |
| long-r44100-s1-default | 13230000 | 58a32b85eb5559ec | 58a32b85eb5559ec |
| long-r48000-s1-default | 14400000 | de80db6c53f3bc20 | de80db6c53f3bc20 |
| poolSteal-r44100-s1-default | 10240 | e0061c757f0305ec | e0061c757f0305ec |
| poolSteal-r48000-s1-default | 10240 | 7e0ab9759c156eea | 7e0ab9759c156eea |

Desktop against phone: 0 of 28 cases differ (`96dfb83/desktop-vs-phone.txt`, `DIGEST MATCH cases=28`). That is an observation, and it gates nothing. It is not promised: `sin`, `cos`, `exp`, `log` and `pow` come from each platform's maths library, so a later toolchain or phone may differ. Byte identity is therefore claimed per platform, and no golden hash is committed as a test.

## Final gates

At `HF`, every host gate exited 0 (`96c9e56/host-gates/summary.txt`):

| Gate | Outcome |
|---|---|
| `flutter pub get` | `Got dependencies!` |
| `dart format --output=none --set-exit-if-changed .` | `Formatted 134 files (0 changed)` |
| `flutter analyze --fatal-infos` | `No issues found!` |
| engine `dart test -x soak` | `+413: All tests passed!` |
| engine `dart test -t soak` (8 simulated hours per rate) | `+2: All tests passed!` |
| app `tool/test.sh` | `+171: All tests passed!` |
| `build/bench --min-factor 150` | `min=275.5 median=279.7 max=281.6`, `PASS min-factor=150.0` |

The normal release build holds no bench code: `strings` on its `lib/arm64-v8a/libapp.so` finds `FBENCH` 0 times (`96c9e56/release-apk/strings-count.txt`). The release Android package (APK) is 52159228 bytes (`96c9e56/release-apk/apk-size.txt`), the same size as unit 2's.

## Dart or native

**Decision: a native core**, by the contract's rule. The final 10-minute run measured `render_ratio_pct=15.95`, which is not under 5.00 (`CPU MISS`, `96c9e56/phone-paced-10min/report.txt`). The miss is 10.95 points, 3.19 times the line.

What a native core must replace, by the final playback profile (`96c9e56/phone-profile-playback/cpu_top.txt`): the whole render path. `Master.render` holds 96.6 % of the engine isolate's samples inclusive. The largest exclusive costs are the biquads (`processStereo` 15.5 %, `processMono` 9.3 %), the voice pool (13.1 %), the reverb (13.1 %), the gain ramps (10.6 %), the master block (9.6 %), the waterfall's own loop (6.7 %), the envelopes (5.6 %) and the noise reads (5.4 % and 3.1 %). No one function holds most of the cost, so a partial port would not reach the budget.

What Dart could not remove without changing samples or the language's safety:

- one `fcvt` per `Float32List` load and store (H4), since every store is a rounding step;
- the bounds and interrupt checks everywhere: removing all of them needs unsafe VM pragmas, which this unit did not use. Where rows 07 and 08 cut them safely, together with 4–19 % of the instructions per frame in the hottest loops, each gained only 0.055 points;
- the place Android chose: a little core at 691.2 MHz for 98.4 % of the run.

The miss is a valid result of this unit, as the contract states. The branch line says `placement=minor`: even at the little cluster's top frequency the estimate is 6.21 %, not under 5 %. The raw ratio is measured at the frequency Android chose, and a native core would run at that frequency too.

**Burst rendering spike (task 06b).** Amendment 3, approved by the user on 2026-11-28, added a spike after the stop and before the final campaign: does rendering in long bursts lower the cost? It ran on the scratch branch `spike/burst-render`, cut from `96c9e56` and deleted afterwards; it was never merged or committed. The engine code was not touched. Each variant changed three lines: the chunk per `write`, the pull ring's size, and SoLoud's mix buffer kept at 2048 frames, so the output device path stayed the reference's.

- `v1s`: chunk 2048 → 48128 frames (1.0027 s), pull ring 8192 → 481280 frames.
- `v5s`: chunk 2048 → 240128 frames (5.0027 s), pull ring 8192 → 2401280 frames.

Two 3-minute runs per variant, normal release, screen off, against the `96c9e56` reference pair (evidence under `96c9e56/burst-spike/`; `stop_s` from `96c9e56/burst-spike/stop.txt`; charges from `96c9e56/burst-spike/energy/energy.txt`):

| | `render_ratio_pct` mean | `process_cpu_pct` mean | Engine thread cluster (run 1 / run 2) | Leading frequency share (run 1 / run 2) | Engine charge, mean milliamperes (mA) | Process charge, mean mA | Functional result | Ledger verdict |
|---|---|---|---|---|---|---|---|---|
| reference `96c9e56` (`paced-3min`, `paced-3min-2`) | 16.015 (15.90, 16.13) | 18.145 | cpu0 100.0 % / 100.0 % | cpu0 691.2 MHz 96.0 % / 97.9 % | 2.5845 | 2.8295 | both `PASS` | reference |
| `v1s` | 5.725 (5.82, 5.63) | 7.185 | cpu0 82.8 % / 80.7 %; cpu4 17.2 % / 19.3 % | cpu0 691.2 MHz 29.7 % / 32.2 % | 1.475 | 1.6535 (−41.6 %) | both `PASS`, exit 0; `stop_s` 5.051, 5.006 | ratio and energy down |
| `v5s` | 1.855 (1.85, 1.86) | 3.350 | cpu4 72.9 % / 72.1 % | cpu0 1804.8 MHz 24.2 % / 23.4 % | 1.291 | 1.5285 (−46.0 %) | both reports `PASS`; run 2 exit 1, Stop took longer than the script's 10 s idle wait; `stop_s` 11.048, 11.386; the late stop was clean | failed (the numbers alone: ratio and energy down) |

The charge is an estimate of active-core charge only. It multiplies each thread's time per cluster and frequency by the vendor's power profile, read with `dumpsys batterystats --power-profile`. That profile describes a 4+3+1 core layout, while the SM6450 is 4+4, so cpu0 is mapped to the profile's `cluster0` and cpu4 to its `cluster1` (`96c9e56/burst-spike/power_map.txt`). It has no idle-state or wakeup terms, which are the costs bursts mainly target. So it is not a battery measurement.

Other limits: the underrun tracker cannot see starvation at these chunk sizes in 3 minutes, so `underruns=0` is no evidence for a variant. The frame deficit and the AudioFlinger counter bound it instead: `deficit_ms` stayed between −3.0 and 5.5, and `af_underruns` was 0 in every run. With bursts, `max_render_us` is one chunk's render: up to 88.5 ms for a 1 s chunk and up to 321 ms for a 5 s chunk. After the Stop tap, the session took about 5 s (`v1s`) or 11 s (`v5s`) to reach idle. By code reading the fade sits behind the queued audio, so it is not heard. Nobody listened.

What it means for the next unit: burst rendering is a pipeline change (chunk size, queue depth, flush), and it applies to a Dart engine and a native one alike. The engine code, and so the instructions per sample, stay the same by construction. The process's CPU time still fell, from 3281–3282 ticks for the `96c9e56` reference pair to 1173–1302 (`v1s`) and 601–624 (`v5s`) over 3 minutes (`96c9e56/burst-spike/energy/energy.txt`). How that fall splits between core placement, frequency and per-wake costs such as cold caches was not measured; per-wake cost is an inference. Whether the next unit tries it before a native core or instead of one is that unit's design question: over 3 minutes the 1 s bursts measured 5.725 % and the 5 s bursts 1.855 %, against the final 10-minute 15.95 %, and no native core was measured.

The decision stands. The contract judges the final head's 10-minute run, and the spike never became the final head.

## Decisions and why

- **Measure where Android runs the engine, and never move it.** No thread affinity and no priority call was used, in the app or in the bench target. The paced run is the judge, because the bench runs elsewhere.
- **The bench target stays in the repository** behind `--target=lib/bench_main.dart`. `lib/main.dart` never imports it, so a normal build holds none of it (`strings` count 0).
- **Stages by subtraction on unchanged engine code.** No timing code entered `Master`, `Waterfall` or a primitive. When the split was unreliable, the profile decided.
- **Byte identity per platform.** Each fix had to match both the desktop and the phone digest sets of the baseline. Desktop-to-phone equality is recorded, not required.
- **Unsafe VM pragmas were not used.** `vm:unsafe:no-bounds-checks` and `vm:unsafe:no-interrupts` needed a plan amendment that the user never gave.
- **Two keep paths (amendments 1 and 2, 2026-11-23).** A fix was kept on the bench path (phone `full` at least 2 % better, or the targeted stage at least 5 % with `full` at most 1 % worse) or on the paced path (two 3-minute runs at least 0.50 points below the reference pair). Reason: the bench runs on the A78 at 2208 MHz, where these loops wait on floating-point latency, while playback runs on the A55 at 691.2 MHz. Two bench runs of one APK differed by 4.7 %.
- **A reference pair after each kept fix.** Two 3-minute runs from the clean committed head. The means (`<head>/paced-3min`, `paced-3min-2` unless named):

  | Head | Runs | Mean |
  |---|---|---|
  | `96dfb83` | 17.00, 16.89 (`96dfb83/paced-3min-ref`, `paced-3min-ref-2`) | 16.945 |
  | `b816c64` | 16.18, 16.13 | 16.155 |
  | `9b609e6` | 16.16, 16.37 | 16.265 |
  | `e100da3` | 15.83, 16.11 (`e100da3/paced-3min-r2`, `paced-3min-r2-2`) | 15.970 |
  | `96c9e56` | 15.90, 16.13 | 16.015 |

  Net: 16.945 → 16.015, −0.930 points (−5.5 %).
- **The user stopped the loop under rule 9(d) on 2026-11-28, reason "diminishing returns".** The loop ended at the clean head `96c9e56` after iteration 09, with no attempt in progress. The finding behind it: rows 07 and 08 cut 4–19 % of the instructions per frame in the hottest loops (07: `processStereo` 46 → 44, `addRamp` 29 → 25; 08: `processStereo` 46 → 40.75, `processMono` 27 → 21.75), and each gained 0.055 points on the paced judge (`PACED ref_mean=15.970 cand_mean=15.915`). Row 09 cut `addRamp` by 22 % (29 → 22.75 per frame), and its reference pair came out 0.045 points above `e100da3`'s. This was not a "no byte-identical gain left" stop.
- **Not tried (stopped).** The allowed ideas left, by rank of the bench profile at `e100da3` (exclusive %):
  - `Reverb.process` H2 and H3: length guards, unroll (8.6 %);
  - `Master._renderBlock` H10 and H2: the shape of the not-a-number (NaN) guard and the fade clamp (6.3 %);
  - `VoicePool.render` H3: unroll the pan mix (5.2 %; 39 → 34 instructions per frame in a scratch copy);
  - `Envelope.process` H3: unroll (4.7 %; 21 → 14.75);
  - `Limiter.process` H6 (3.5 %);
  - `Master.render` H10: `setRange` for the copy (1.2 %).
- **One commit per kept fix, none for a dropped attempt.** Each commit body names its hypothesis, evidence path and numbers. Erratum: the body of `b816c64` gives the desktop texture stage as "2456 -> 2399"; the baseline value is 2520 (`96dfb83/desktop/stage_bench.txt`), so it is 2520 → 2399.
- **The final head is the stop head.** The burst spike changed no committed file; the final campaign ran at `96c9e56` unchanged.

## Rejected alternatives

- A benchmark mode inside `lib/main.dart` behind a define: a dead branch in the app; the separate entry point keeps the normal build clean.
- Timing code inside the engine: it changes the code it measures.
- `simpleperf`: the profile APK's `libapp.so` has no symbol table, so it cannot name Dart functions. The VM's own sampler needs no symbols.
- The phone bench alone as the keep judge: rows 07 and 08 were 4–5 % worse on the bench and slightly better in playback, and row 02 was 1.5 % worse on the bench yet kept by the paced judge as 02r.
- H1 coding 1 (truncate, then correct by comparing the remainder): two data-dependent branches per sample made the desktop 16.5 % slower.
- Interleaving the biquad's left and right statements (row 03): no gain on the in-order core.
- Every sound-changing idea: merging passes, float intermediates, fused multiply-add, moving a denormal flush, block-rate values, re-derived maths calls. Each needs a recipe change through the design doc.
- Unsafe VM pragmas and thread affinity or priority: barred by the contract and the plan.

## Traps

- The bench and playback run in different places: the bench on cpu4 at 2208 MHz, playback on cpu0 at 691.2 MHz. A bench gain can be no paced gain, and the reverse.
- The phone bench varies by 4.7 % between two runs of one APK (`full` medians 9574 and 10027). A 1 % or 2 % bench line sits inside that noise.
- The subtraction split is not additive: the `bus` stage runs a silent bus. Read the profile when `UNRELIABLE split` is printed.
- In `loop` mode the bench profile is dominated by noise-table generation (`NoiseTable._channel`, about 20 %), which playback never pays.
- Inlined functions have no symbol and no profile row of their own. Use `inlined_top.txt` to split a function's samples, and expect a function to get its own row once a change stops the inlining (`addRamp`, the noise reads).
- A length guard and an unroll do not combine: in a scratch copy every unroll shape brought the bounds checks back.
- This phone sometimes drops the logcat lines of a fresh process. The first `e100da3` pair failed with `FAIL no FSTAT line in t0/fstat.txt` and was run again.
- An ignored scratch file under `packages/fiatsonus_engine/build/` failed `dart format` once. Keep `build/` free of stray Dart files.
- Desktop timings are load-sensitive: no build, test or second benchmark beside a desktop measurement. One desktop run sat at 117.0 beside the compile's tail load.
- At burst chunk sizes the underrun tracker is blind, and a 5 s chunk makes Stop take longer than `screen_off_run.sh`'s 10 s idle wait.

## Open

- **Burst rendering design, settled with the user on 2026-11-28 as points for the next unit:**
  - Adaptive lead: a short buffer of about 170 ms (today's 8192 frames) for 10–20 s after any param change, play, stop or focus event, and long bursts after that.
  - On a change, flush the queued audio and render fresh with a short crossfade. There is no state rollback: the soundscape has no audible timeline.
  - Fades take the same path.
  - flutter_soloud's flush support is unverified. `resetPullBufferStream` exists in 5.3.1 and clears the queued audio (read in source, not exercised). It also resets the counters behind `getPullBufferTimeRange`, which the sink's lead measure reads.
- **Battery drain over an hour is the real metric** beside `render_ratio_pct`. The spike's charge figure is an estimate that cannot see idle states or wakeups.
- No native core was measured.
- No low-end phone was measured. A slower phone would cost more.
- The allowed ideas under "Not tried (stopped)" remain untried.
- Desktop-to-phone digest equality held on this phone and toolchain only.
