# Procedural Ambient Sound Engine — Design Contract

Living recipe reference for fiatsonus. Imported 2026-11-20 from the original design contract. It changes only together with the code it describes.

## Purpose and scope

The app makes ambient sounds with code only: no recorded audio files. It is for any use: sleep, study, work, commute, focus. One shared engine produces five soundscapes (stream, waterfall, distant city, night forest, ocean), plus the parked rain soundscape. This document is the contract between the design and the code. A coding agent should be able to build the engine and each soundscape from it.

**Goals**

- Every sound is generated live from random numbers, filters, and envelopes.
- Every layer has live controls with smooth changes (no clicks, no jumps).
- No audible loop, even after 8 hours.
- App audio size close to zero. The only stored data is code and presets.
- Low battery use, so the app can play for hours on a phone.
- Deterministic output for tests: the same seed gives the same audio.

**Non-goals (for version 1)**

- Birds, human voices, and other sounds that code imitates badly (see the prototype findings).
- Full HRTF (head-related transfer function) binaural rendering. Simple stereo placement is enough for version 1.
- Recorded samples. A hybrid mode with short one-shot samples is a later option, not part of this contract.

**Terms**

| Term | Meaning |
| --- | --- |
| Bed | A continuous layer, such as filtered noise that never stops |
| Grain | A very short sound event (1–200 ms), such as one drop or one bubble |
| Event | A longer one-off sound (1–15 s), such as a car passing or a wave |
| Layer | One part of a soundscape, made from beds, grains, or events |
| Soundscape | A full scene made of several layers, with user controls |
| Param | A user control, always a number from 0 to 1 |

## Engine architecture

The engine is a pure DSP (digital signal processing) core with no Flutter dependency. It renders float samples into buffers. A thin platform layer sends those buffers to the speaker. This keeps the core testable on a desktop without a phone.

```text
Platform layer (Flutter)
  UI sliders  --setParam()-->  Engine (runs in a separate isolate)
                                 |
  AudioSink  <-- Int16 PCM --  Master: sum -> limiter -> float-to-int16
                                 |
                               Soundscape[] (each with its own gain)
                                 |
                               Layer[] (beds, grain clouds, event schedulers)
                                 |
                               Primitives (noise tables, filters, envelopes,
                                           modulators, panner, reverb, voice pool)
```

Rules for the layers:

1. **Primitives** know nothing about soundscapes. Each primitive is a small class with a `process` method that works on a block of samples.
2. **Layers** combine primitives. A layer owns its own random number generator, seeded from the soundscape seed.
3. **Soundscapes** own layers and map user params (0 to 1) to internal layer values. All the "recipe" numbers in this document live here.
4. **The master** mixes soundscapes, applies one limiter, and converts to 16-bit integers.
5. **The audio sink** is an interface. The engine never calls a plugin directly, so the backend can change later.

The engine renders in blocks of 256 frames. Grain and event start times are scheduled with sample accuracy inside a block. Timers (`setTimeout`, `Timer`) are never used to schedule sounds. The prototype used timers and that is fine in a browser demo, but timers drift and bunch up on a phone.

## Engine primitives contract

Every soundscape is built only from these primitives. Add a new primitive only when a soundscape cannot be built without it.

| Primitive | What it does | Contract |
| --- | --- | --- |
| `NoiseTable` | Pre-generated stereo noise: white, pink, brown | Generated once at startup from a seed. Length 4–6 s. Left and right channels are independent (decorrelated). Readers start at a random offset and loop. |
| `Biquad` | Low-pass, high-pass, band-pass, peaking, high-shelf filter | Standard biquad (RBJ cookbook formulas). Frequency and Q can change per block, smoothed. Frequency clamped to 20 Hz – 0.45 × sample rate. Q clamped to 0.1–50. |
| `Envelope` | Volume shape over time | Segments of linear or exponential ramps. Exponential ramps never start or end at exactly 0 (use 0.0001). |
| `Smoother` | Moves a value toward a target | One-pole smoothing, time constant set per param (default 200 ms). Every user param goes through one. |
| `Modulator` | Slow change over time | Two kinds: sine LFO (low-frequency oscillator), and random walk. Depth is always relative to the base value (see safety rules). |
| `GrainCloud` | Fires many short grains | Poisson timing: gap = −ln(random) / rate. Each grain gets random values inside the ranges the layer gives it. |
| `EventScheduler` | Fires longer events | Random gap between a min and a max. Events may overlap. |
| `Voice` / `VoicePool` | Plays one grain or event | Fixed pool, allocated at startup. No memory allocation in the audio loop. When full, steal the quietest voice. |
| `Panner` | Places a sound left to right | Equal-power stereo pan, −1 to +1. Distance = volume drop + low-pass + more reverb send. |
| `Reverb` | Outdoor space | Cheap algorithmic reverb (for example a small feedback delay network). One shared instance per soundscape, fed by send levels. |
| `Limiter` | Stops clipping | On the master only. Ceiling −1 dBFS (decibels relative to full scale). Soft knee. |
| `Delay` | Echo taps | Used for thunder and valley echoes. Max delay 4 s. |

**Noise colors used in this document**

- **White:** equal energy at all frequencies. Bright hiss.
- **Pink:** energy falls 3 dB per octave. Balanced, "natural" noise.
- **Brown:** energy falls 6 dB per octave. Deep rumble. The prototype used `last = (last + 0.02 × white) / 1.02`, then × 3.5 for level.

**Grain recipes shared across soundscapes**

- **Noise burst:** a noise reader → one or two biquads → envelope (attack 0.8–2 ms, exponential decay). This is the building block for drops, splashes, crackles, and ticks.
- **Bubble:** a noise burst through a narrow band-pass (Q 12–35), with the band-pass frequency rising ×1.03–1.25 over the grain. Never use a pure sine wave for a bubble above about 1.5 kHz: it sounds like a bird chirp.

## Soundscape and parameter interface

Each soundscape implements one interface. The UI only sees param specs and calls `setParam`.

```dart
final class ParamSpec {
  final String id;
  final String label;
  final double defaultValue;
  final Duration smoothing;
  const ParamSpec(this.id, this.label, this.defaultValue,
      {this.smoothing = const Duration(milliseconds: 200)});
}

abstract interface class Soundscape {
  String get id;
  List<ParamSpec> get params;
  void prepare(int sampleRate, int seed, NoiseBank noise);   // called once; may allocate
  void setParam(String id, double value);                    // stores a target only; clamp 0..1; NaN and unknown id ignored
  void render(Float32List left, Float32List right, int frames); // ADDS; 1 <= frames <= kBlockFrames; no allocation; no throw
  void reset();                          // S8: zero filter and reverb memory, silence voices; no allocation
  int get activeVoices;
}

abstract interface class AudioSink {
  Future<void> start({required int sampleRate, required int channels});
  Future<void> write(Int16List interleaved);   // interleaved 16-bit samples
  Future<void> stop();
}
```

**Rules**

- A param maps to internal values only inside the soundscape. Use a curve where it helps, for example `rate = 3 + pow(p, 1.5) * 80`.
- Every mapping is written as a table in that soundscape's section of this document. When code and document disagree, fix one of them in the same change.
- Start and stop always fade (default 2 s in, 3 s out). Never cut audio at a non-zero sample. The master owns the fades; a soundscape never fades itself.
- Messages from the UI isolate to the engine isolate are only `['start', soundscapeId, fadeMs]`, `['stop', soundscapeId, fadeMs]` and `['param', soundscapeId, paramId, value]`. No closures, no objects.
- Mixing several soundscapes (for example rain + wind) is done by the master. Soundscapes do not know about each other.

## Safety rules

Each rule below comes from a real bug or a bad sound found in the rain prototype. They apply to every soundscape.

| # | Rule | Why (prototype finding) |
| --- | --- | --- |
| S1 | Clamp every computed value before it reaches a filter, envelope, or gain: time, frequency, Q, gain, pan. | Thunder went silent. A power function got a negative base, returned NaN (not a number), and the audio call threw. |
| S2 | Never raise a value that can go negative to a fractional power. Clamp the base to 0..1 first. | Same thunder bug. |
| S3 | A modulator's depth is a fraction of the base value it modulates, never a fixed amount. | Rain faded in and out at low levels. A fixed-depth LFO was larger than the rain level itself. |
| S4 | Check every layer at default settings and at each slider's minimum. A global filter must not hide a whole layer. | Drops were inaudible. A "window" low-pass at 1 kHz plus distance fade removed nearly all of them. |
| S5 | Distance fade must stay gentle: full volume up to about 3 m, and no less than about 30% at the farthest source. | Same drops bug: far drops fell to about 14% volume. |
| S6 | Scheduling loops carry a session id. A loop stops when its id is not the current one. | Fast pause/play doubled the drip loops. |
| S7 | Every envelope ends at a value of 0 before its voice stops. | A voice stopping mid-sound makes a click. |
| S8 | After rendering each block, check the master for NaN or infinity. If found: replace the block with silence, reset all filter states, and log it. | One bad filter state can poison all later output. |
| S9 | Flush denormals (tiny numbers near zero) in filter states to 0. | Denormals can make the CPU (central processing unit) many times slower on some devices. |

**Sound-quality rules from the prototype**

- **No pure sine sweeps for water.** A sine that sweeps up sounds like a bird chirp. Use narrow-band noise (the bubble grain).
- **No resonant band-pass on impact sounds.** A resonant filter on a drop sounds like a tap on a tent or fabric.
- **No instant, bright attacks for soft impacts.** Attack under 1 ms plus energy above 5 kHz sounds like glass. Use 1.5–2 ms attack and a top frequency of 1.5–3.5 kHz.
- **Randomize every event, but inside a type.** Thunder only sounded varied once it had distinct types (distant rumble, close crack, rolling, multi-strike, echo) with random values inside each type. Pure randomness sounded "the same each time".
- **Fixed source positions sound more real than random positions.** Drips at fixed spots with their own rhythm were a strong realism cue.

## Performance budget

These are starting targets, not measured numbers. Measure on a low-end Android phone early and adjust.

| Item | Target |
| --- | --- |
| Sample rate | 44,100 Hz or 48,000 Hz, stereo. Pick whatever the device prefers. |
| Render block | 256 frames |
| Output buffer | 100–200 ms. Latency does not matter for ambient playback, except slider response. A big buffer saves battery and survives UI jank. |
| CPU per soundscape | Under 5% of one core on a low-end phone |
| Active voices per soundscape | 64 max (grains + events). Steal the quietest when full. |
| Filters per grain | 2 max |
| Memory allocation in the audio loop | None |
| Noise tables | Shared by all soundscapes. About 4–6 s each, stereo float. |
| Reverb | One per soundscape, cheap algorithm. No convolution with long impulses on mobile. |

**Cost tips**

- Grains are the main cost. Keep each grain to one noise reader, at most 2 biquads, and one envelope.
- Compute filter coefficients once per grain, not per sample. Only recompute per block when a value is moving.
- Group far, quiet grains: send them through one shared low-pass instead of one low-pass each.
- The rain prototype used 14 HRTF panners for drops. On mobile, use the simple stereo panner plus a distance low-pass instead. Add HRTF only if testing shows it's worth the cost.

## Soundscape: stream / creek

A stream is a soft water bed plus many low, gurgling bubbles. The bubbles carry the realism. The bed only fills the gaps between them. Difficulty: medium. It reuses the rain drop and bubble grains.

**Layers**

| Layer | Recipe | Notes |
| --- | --- | --- |
| Bed | Pink noise → band-pass 600–2,500 Hz (Q 0.5–0.8) → low-pass 4 kHz. Band-pass center follows a random walk (±20%, 0.05–0.2 Hz). Gain follows two random walks (depth 10% and 6% of base). | Keep it quiet. Too loud and it becomes a waterfall. |
| Gurgle | Bubble grains. Band-pass center 250–1,800 Hz, Q 8–25. Sweep up ×1.1–1.6 over 10–60 ms. Rate 20–200 per second. | Main layer. Lower and longer bubbles = bigger stream. |
| Clusters | Every 0.5–3 s, a burst of 3–12 bubbles within 50–200 ms at one spot. | Water passing a rock. Gives rhythm. |
| Splashes | Noise bursts, band-pass 1–6 kHz, Q 0.7–1.5, 20–80 ms. Rate 0.5–3 per second. | From the rain "water drop" recipe, but longer. |
| Placement | 6–10 fixed spots along a line 2–6 m in front, from pan −0.9 to +0.9. Each spot has its own bubble pitch range (±15%) and activity level. | Fixed spots make the stream feel like a real place (see safety rules). |

**Params**

| Param | Default | Maps to |
| --- | --- | --- |
| Flow | 0.5 | Gurgle rate 20→200 per second (curve p^1.5). Bed level. Cluster rate. |
| Size | 0.4 | Small brook → river. Bubble center range shifts down (×1.4 → ×0.6). Bubble length longer. Bed band-pass lower. |
| Rockiness | 0.4 | Splash rate and cluster size. |
| Distance | 0.3 | Master low-pass 12 kHz → 2.5 kHz. Reverb send 0.1 → 0.5. Level 0 → −9 dB. |

**Acceptance**

- [ ] No single bubble sounds like a bird or a whistle at any setting.
- [ ] At Flow 0.1 you hear separate bubbles. At Flow 1.0 they blend into a busy flow.
- [ ] Moving Size from 0 to 1 sounds like a brook turning into a river, not a pitch shift.
- [ ] With headphones you can point to where the stream is loud and where it is quiet.

## Soundscape: waterfall

A waterfall is a thick, steady roar with a deep body and fine spray. It's the easiest soundscape: mostly beds. The one risk is that it sounds like plain static, so it needs a dense texture layer. Difficulty: easy.

**Layers**

| Layer | Recipe | Notes |
| --- | --- | --- |
| Roar | Pink + white noise (70/30) → high-pass 80 Hz → low-pass 6–10 kHz (Height). Gain 1.0. Very slow random walk on level (depth 4% of base, 0.02–0.05 Hz). | Main layer. Very stable. |
| Body | Brown noise → low-pass 250–120 Hz (Height). Gain 1.0 × body level. | The "weight" of falling water. Scales with height. |
| Spray | White noise → high-pass 4 kHz. Gain 1.0 × Spray. Random walk on level (depth 15%, 0.1–0.4 Hz). | Gusts of mist. Off at Spray 0. |
| Texture | Dense noise-burst grains from white noise: band-pass 800–4,000 Hz (log-uniform), Q 0.7–1.2, 5–30 ms (attack 1.5–2 ms, exponential decay), 100–400 per second, level 0.6–1.0, pan −0.9 to +0.9. Texture gain 1.4. | Stops the roar from sounding like static. Spread wide. |
| Distance stage | Whole mix → low-pass (Distance) → reverb send (RT60 1.6 s, damping 4 kHz, wet 0.5) → level. | One low-pass and one reverb for the soundscape. |
| Output | Output trim 0.78 → width (mid/side). | The trim sets −20 LUFS at default params. |
| Placement | Roar, body and spray use decorrelated left and right noise (independent channels) for width. Width control blends the whole output toward mono. | No moving sources. |

**Params**

| Param | Default | Maps to |
| --- | --- | --- |
| Height | 0.5 | Body level 0.3 + 0.7·h. Body low-pass 250 − 130·h Hz. Roar low-pass 6,000 + 4,000·h Hz. Texture rate 100 + 300·h per second. |
| Spray | 0.4 | Spray level = s (linear). 0 switches the layer off. |
| Width | 0.7 | Side signal × w: mono (0) to fully decorrelated (1). No loudness compensation. |
| Distance | 0.4 | Low-pass 12,000 × 0.125^d Hz (12 kHz → 1.5 kHz). Reverb send 0.1 + 0.5·d. Level −12·d dB. Texture a further −12·d dB, so it fades out faster than the roar. |

The doc's first texture level (about −30 dB under the roar per grain) measured about 47 dB under the roar as a layer and was inaudible; the gain above puts the texture about 14 LU under the roar at default params. Levels are tuned by listening and changed here and in the code together.

**Acceptance**

- [ ] At Distance 0, it does not sound like TV static or a fan.
- [ ] At Distance 1, it sounds like a waterfall heard across a valley.
- [ ] Changing Height sounds like a bigger fall, not just louder bass.

## Soundscape: distant city / traffic

A distant city is a low rumble with cars passing now and then. Distance is the key: far away, synthetic engines are hidden by the low-pass and reverb. Up close, they sound fake. So the Distance param has a floor. Difficulty: medium, with the highest risk of sounding synthetic.

**Layers**

| Layer | Recipe | Notes |
| --- | --- | --- |
| Rumble | Brown noise → low-pass 80–250 Hz. Random walk on level (depth 25%, 0.01–0.05 Hz) for "traffic waves". | Always on. |
| Hum | Pink noise → band-pass 200–800 Hz, Q 0.7. Low level. | City air, distant machines. |
| Car pass-by (event) | Tires: pink noise → band-pass 300–2,000 Hz. Engine: 2–3 oscillators at a base of 40–120 Hz plus harmonics, each with ±1% random pitch wobble, → low-pass 400–900 Hz, mixed under the tires. Envelope: a bell shape, 3–10 s. Pan sweeps from one side to the other. Pitch drops 3–8% at the midpoint (Doppler effect). | Tires carry most of the sound. Keep the engine quiet. |
| Motorbike (event) | Same as a car, engine base 80–200 Hz, louder engine, shorter (2–5 s). | Rare. Common in Indonesian cities. |
| Bus/truck (event) | Same as a car, engine base 30–60 Hz, longer (6–14 s), optional air-brake hiss (white noise → high-pass 2 kHz, 0.5–1.5 s). | Rare. |
| Horn (event) | Two tones 300–500 Hz, 0.2–0.6 s, heavy low-pass and reverb. | Off by default. Many listeners do not want horns in a background sound. |
| Placement | Two or three "roads" at fixed distances (20–150 m) and angles. Each event picks a road and a direction. | Fixed roads make the scene believable. |

**Params**

| Param | Default | Maps to |
| --- | --- | --- |
| Traffic | 0.4 | Event rate 1 per 30 s → 1 per 2 s. Rumble level. |
| Distance | 0.6 | Range 0.3–1.0 only (floor at 0.3). Master low-pass 3 kHz → 800 Hz. Reverb send. |
| Time of night | 0.5 | Late night = fewer events, more bikes than cars, quieter rumble. |
| Horns | 0 (off) | Toggle: 0 or 1 only. |

**Acceptance**

- [ ] At default settings, a listener says "city at night", not "synth".
- [ ] A single car pass-by has a clear approach, peak, and fade with a pitch drop.
- [ ] No two consecutive cars sound the same.

**Risk:** if the engine still sounds like a synth, drop the oscillators. Use tires plus a low-passed brown noise "engine" instead. A distant car is mostly tire noise anyway.

## Soundscape: night insects / forest

A night forest is a quiet air bed, leaves moving in the wind, and a few insects that each keep their own rhythm. Insects are tonal, so this is the one soundscape that uses oscillators as a main sound. Each insect is a fixed "individual" with its own pitch and tempo. Difficulty: medium.

**Layers**

| Layer | Recipe | Notes |
| --- | --- | --- |
| Air | Pink noise → low-pass 2 kHz. Very quiet. | Fills silence. |
| Leaves | White noise → band-pass 2–6 kHz, Q 0.5. Level follows a "wind" random walk (0.05–0.3 Hz). Add sparse rustle grains (noise bursts 3–7 kHz, 20–100 ms) when wind is high. | Wind drives leaves. |
| Crickets | 3–12 individuals. Each: a sine carrier at 3.5–5.5 kHz (fixed per individual, ±0.5% wobble) plus 10% band-passed noise around the carrier. Sound pattern: a chirp = 3–6 pulses of 10–25 ms, smooth (raised-cosine) edges. Chirp rate 1–3 per second, own tempo, ±5% jitter. | The noise part stops the "electronic beep" sound. |
| Katydids | 0–4 individuals. Noise → band-pass 6–9 kHz, Q 3–6, amplitude pulsed at 30–80 Hz in bursts of 0.3–1.5 s. | Buzzier, rarer. |
| Frogs (optional) | Each call: 2–4 pulses of a 300–800 Hz tone through a band-pass (formant), 30–80 ms each. Rate 1 per 3–15 s per frog. | Off by default. High risk of sounding fake. |
| Placement | Each individual has a fixed spot: pan −1 to +1, distance 2–20 m (volume and low-pass). | Fixed spots are the key realism cue. |

**Group behaviour**

- Insects sometimes go quiet for 2–10 s, then restart one by one. Each individual has a small chance per second to pause.
- Nearby individuals slowly drift toward the same tempo (±2% per minute). Real crickets often fall into sync.
- Cricket chirp rate goes up as temperature goes up. The Warmth param uses this.

**Params**

| Param | Default | Maps to |
| --- | --- | --- |
| Insects | 0.5 | Number of active individuals (crickets 3→12, katydids 0→4). |
| Warmth | 0.5 | Chirp rate ×0.6 → ×1.5. |
| Wind | 0.3 | Leaves level, rustle grain rate, wind random-walk speed. |
| Frogs | 0 (off) | Toggle. |

**Acceptance**

- [ ] No insect sounds like an alarm, a beep, or a phone tone.
- [ ] With headphones you can follow one cricket for a minute at a fixed spot.
- [ ] The scene never sounds like a loop: the pattern of pauses and restarts keeps changing.

**Excluded:** owls and night birds. Code-made birds sound like toys (see safety rules).

## Soundscape: ocean

The ocean is a series of overlapping wave events over a constant low swell. Each wave has three phases: build, break, and wash. The wave timing must never feel regular. Difficulty: easy to medium.

**Wave event (the core)**

| Phase | Length | Recipe |
| --- | --- | --- |
| Build | 1.5–4 s | Pink noise → low-pass rising from 300 Hz to 1.5 kHz. Level rises slowly (exponential-ish curve). |
| Break | 0.3–1 s | Broadband crash: pink + white noise, low-pass jumps to 3–8 kHz. Peak level. Brown-noise thump under it for big waves. |
| Wash | 3–7 s | Low-pass sweeps down from 6 kHz to 800 Hz while level fades. Foam: dense fizz grains (noise bursts 3–8 kHz, 2–10 ms, 200–800 per second) fading with the wash. |

Every wave picks new random values: size (0.4–1.0 × the Wave size param), phase lengths, filter targets, and pan center (±0.4). Foam grains spread wider than the wave (±0.9).

**Wave timing**

- The next wave starts 6–14 s after the previous start, scaled by Wave rhythm.
- Waves overlap: a new build can start during the previous wash.
- Waves come in sets: every 4–8 waves, 2–3 bigger waves in a row, then a calmer stretch. This is how real swell behaves and it prevents a regular "metronome" feel.

**Other layers**

| Layer | Recipe |
| --- | --- |
| Swell bed | Brown noise → low-pass 150 Hz. Constant, quiet. |
| Pebble drag (optional) | During the wash, dense click grains (noise burst 2–5 kHz, 1–4 ms, band-pass Q 1–2) at 100–500 per second. Pebble beach instead of sand. |
| Wind (optional) | Reuse the forest Leaves recipe without the leaves: band-passed noise on a wind random walk. |

**Params**

| Param | Default | Maps to |
| --- | --- | --- |
| Wave size | 0.5 | Wave size range, break level, thump chance. |
| Wave rhythm | 0.5 | Gap between waves ×1.4 (calm) → ×0.7 (busy). |
| Distance | 0.3 | Beach (0) to cliff top (1). Master low-pass 12 kHz → 1.5 kHz. Foam fades first. Reverb send. |
| Beach | 0 (sand) | 0 = sand, 1 = pebbles. Pebble drag level. |
| Wind | 0.2 | Wind layer level. |

**Acceptance**

- [ ] After 10 minutes, a listener cannot predict when the next wave will come.
- [ ] Each wave has an audible build, break, and wash.
- [ ] Foam fizz sounds like bubbles, not like radio static.

## Rain (parked)

Rain is parked. The prototype (v6, browser Web Audio) is the reference and is "good enough". This section records its final recipe so it can be ported to the engine later.

| Layer | Final prototype recipe |
| --- | --- |
| Main rain | White noise → high-pass 400 Hz → low-pass 1.5–10.5 kHz (Tone param). Plus brown noise at 25% for body. Gain modulated by two sine LFOs at 0.071 Hz and 0.023 Hz, depth 10% and 8% of base. |
| Ground drop | Noise burst: high-pass 150–350 Hz + low-pass 1.5–3.5 kHz, attack 1.5 ms, decay 6–18 ms. 35% chance of a low thump (low-pass 250–550 Hz, 15–35 ms). 10% chance of 1–2 tiny splatter grains. |
| Water drop | Low "plop": low-pass 600–1,600 Hz, Q 1–3, decay 12–30 ms. 30% chance of a bubble grain at 5–11 kHz, Q 12–30, sweep ×1.03–1.1. |
| Drop placement | 16 fixed spots, 1.5–9 m, all around. Distance fade starts at 3 m. |
| Gutter drips | Up to 4 fixed drips, 1.5–3.5 m. Own period 0.45–1.6 s, drifting ±3% per drip, ±15% jitter. 70% fall into puddles (plop + 55% bubble + small tail). |
| Thunder | Five types: distant rumble, close crack, rolling across the sky, multi-strike (2–4), echoing valley (2–4 echoes). 2–3 brown-noise rumble layers with falling low-pass, own pan paths. Crack + crackle bursts + sub thump for close strikes. |
| Params | Main rain, Tone, Drops, Gutter drips, Ground ↔ water, Thunder, Space (reverb). |

**Tried and dropped:** an indoor "through the window" mode. The idea is fine, but the first try hid the drops (safety rule S4). Revisit with a gentler window filter if wanted.

## Flutter platform notes

Flutter has no built-in way to play generated audio, so the app needs a plugin that accepts raw PCM (pulse-code modulation) samples. Unit 2 probed three on the phone (`flutter_soloud`, `flutter_pcm_sound`, `mp_audio_stream`) and chose `flutter_soloud` 5.3.1. The numbers and the reasons are in `docs/decisions/platform-spike.md`.

**What was built**

- The engine runs in one spawned Dart isolate, alive for the process. It owns the master, the sink pump and the sink, and uses no platform channel.
- The sink is `flutter_soloud`'s pull stream: its demand callback (`onMoreDataIsNeeded`) arrives in the engine isolate. The pump renders a chunk and awaits `write`, which waits for demand; no timer schedules audio. `flutter_pcm_sound` was rejected because its callback reaches only the UI isolate, so a UI stall starves it; `mp_audio_stream` has no demand signal and needs a timer.
- The master converts to 16-bit integers; the sink hands interleaved stereo to the stream.
- `audio_service` 0.18.19 runs the foreground service (`mediaPlayback`) with a Stop-only notification; `audio_session` 0.2.4 handles audio focus.
- The `AudioSink` interface still separates the engine from the plugin, so a native core can replace the Dart DSP without changing the recipes.
- Desktop Linux plays nothing; use the offline WAV renderer there.

**Checked in unit 2 (details in `docs/decisions/platform-spike.md`)**

- [x] Background playback with the screen off on Android: one hour screen off on a vivo (Android 16) through the foreground service, zero underruns. iOS is not built.
- [x] The feed in the background: the pull-stream callback kept the feed going with the screen off for the whole hour; the counters and the session's lead line show no gap.
- [x] CPU cost of the Dart DSP core: 17.35 % of one core on a mid-range phone in unit 2, and 15.95 % after unit 2b's byte-identical fixes; over the 5 % budget; a low-end phone was not measured.
- [x] Other PCM plugins: `flutter_pcm_sound` and `mp_audio_stream` were probed beside `flutter_soloud`; neither meets the constraints.

## Testing and acceptance

The engine core is pure Dart, so most testing runs offline on a desktop: render to a WAV file, check numbers, then listen. A soundscape is done when it passes every automatic check below plus its own acceptance list.

**Offline renderer**

A small command-line tool renders any soundscape with a seed, a duration, and param values to a WAV file. From `packages/fiatsonus_engine`: `dart run tool/render.dart --scape waterfall --seed 42 --secs 120 --param height=0.8` (options: `--rate`, `--sweep <param>`, `--out`). The same seed always gives the same file.

**Automatic checks (run on every soundscape and preset)**

| Check | Pass condition |
| --- | --- |
| No NaN or infinity | Zero bad samples in a 10-minute render |
| No clipping | Master peak ≤ −1 dBFS |
| Level | Long-term loudness within a target band per soundscape (set the band once, then keep it) |
| No DC offset | Mean of samples close to 0 (absolute value under 0.001) |
| No clicks on param changes | Sweep every param 0 → 1 → 0 over 30 s. The largest sample-to-sample jump stays under a threshold. |
| Edge values | Every param at 0 and at 1, alone and together: no NaN, no silence unless intended |
| Long run | Simulated 8 hours, rendered as fast as possible: voice count stays bounded, memory stays flat, no slow level drift |
| Determinism | Two renders with the same seed are identical, byte for byte |
| Pause/play stress | 100 fast start/stop cycles: no doubled schedulers (rule S6), no clicks |

**Listening checks**

- Listen with headphones and with a phone speaker. Many people listen on a phone speaker.
- Listen at low volume. Ambient sound is often played quietly, and bad textures stand out more there.
- Listen for 10 minutes without watching the screen. Note anything that repeats or sticks out.

**Done means**

- [ ] All automatic checks pass.
- [ ] The soundscape's own acceptance list passes.
- [ ] Its param mapping table in this document matches the code.

## Open questions

- [x] Which audio plugin? `flutter_soloud` (pull stream in the engine isolate); see `docs/decisions/platform-spike.md`.
- [x] Dart DSP or a native core? A native core: after unit 2b's profiling and fixes the Dart engine measured 15.95 % of one core on the phone, over the 5 % budget; see `docs/decisions/engine-profiling.md`.
- [x] Build order: engine primitives + waterfall first (unit 1), then ocean, stream, forest, city.
- [ ] Scene mixing: can users stack soundscapes (for example ocean + forest)? The master supports it. The UI needs a design.
- [ ] Timer and fade-out length.
- [ ] Presets: named param sets per soundscape (for example "Light drizzle", "Storm"), stored as small JSON files.
- [ ] Should the app also offer plain white, pink, and brown noise? They are nearly free, since the noise tables already exist.
- [ ] App name (working name: fiatsonus).
- [x] License: MIT.

## Unit decisions: engine-core (unit 1)

- Numbers: Float32List buffers, double arithmetic and filter state. Engine block 256 frames; block-rate values advance once per block, gains ramp per sample, filter coefficients change at block boundaries.
- Random numbers: an explicit xoshiro128** generator with 32-bit operations only, never dart:math Random. Seeds are derived per consumer from the master seed.
- Determinism: same build mode and platform, seed, params, sample rate and call sequence give byte-identical output, independent of how the caller chunks render calls. Bit identity across platforms is not promised, because sin, cos, exp, log and pow come from the platform maths library.
- Master: owns start/stop fades (gain = u², u linear), per-soundscape gain, summing, the S8 check, the limiter and Int16 conversion. A stopped soundscape is not rendered.
- S8: a block with NaN or infinity, or a soundscape that throws, becomes silence; every soundscape and the limiter are reset; playing soundscapes fade in again; a counter (faultBlocks) reports it. The master itself never logs.
- S6: the core has no timers and no scheduling loop outside render. The one asynchronous loop, the sink pump, carries a session id and stops when it is superseded.
- Limiter: stereo-linked, knee at 0.5, ceiling 0.8912 (just under −1 dBFS), instant attack, 150 ms release. Largest legal Int16 magnitude: 29203.
- Noise tables: white 4.37 s, pink 5.23 s, brown 5.81 s, stereo, each channel normalised to RMS 0.25 with zero mean; pink and brown are high-passed at 20 Hz; the loop seam is crossfaded over 100 ms. The brown coefficient is scaled by 44100 / sample rate. Different lengths keep layers from looping together.
- Biquad in this unit: low-pass, high-pass, band-pass. Peaking and high-shelf arrive with the first soundscape that needs them. Smoothing is done by the caller's Smoother; the biquad recomputes coefficients only when its inputs change.
- Voices: one noise reader, one biquad, one envelope, one pan per voice; 64 at most. A stolen voice fades out over 64 frames before the new grain starts, also when the caller renders in calls shorter than that.
- Grain timing: the wait for the next grain is kept as a rate-free random value and converted with the current rate, so a rate change takes effect at once, also after a rate near zero.
- Reverb: four-line feedback delay network (29.7, 37.1, 41.1, 43.7 ms), RT60 1.6 s, damping 4 kHz, mono send, stereo return.
- Not built in this unit: EventScheduler, Delay, sine LFO.
- Loudness measure for the Level check: ungated BS.1770 K-weighted stereo loudness (LUFS). Waterfall band: −21 to −19 LUFS at default params.
- Click check: the largest sample-to-sample jump divided by the RMS of the jumps in the 2048 samples before it must stay at or below 12. Fades and param steps are also proven exactly against a twin render.
- Long run: 8 simulated hours on the AOT build with the VM's GC log on. Pass: no garbage collection during the run, memory spread within 4 MiB, at most 64 voices, the loudness of the first 60 s of every ten-minute window within ±0.5 LU of the first window's.
- CPU: the benchmark reports the realtime factor on the AOT build. Unit 1 target: waterfall defaults at 48 kHz render at 150× realtime or faster on one desktop core.

## Unit decisions: platform-spike (unit 2)

- App: `apps/fiatsonus`, application id `dev.fiatcode.fiatsonus`, Android only. One `Isolate.spawn` engine isolate, spawned at app start with `[SendPort events, int sampleRate, int seed, String tempDirPath]`; it answers `['port', SendPort commands]`, then `ready`.
- Protocol (plain lists; malformed or unknown messages are ignored without an event):

| Direction | Message |
| --- | --- |
| UI → engine | `['start', soundscapeId, fadeMs]` |
| UI → engine | `['stop', soundscapeId, fadeMs]` |
| UI → engine | `['param', soundscapeId, paramId, value]` |
| engine → UI | `['ready', sampleRate, sinkId]` |
| engine → UI | `['state', playing]` (`true` when a session opens the sink, `false` after it closes it) |
| engine → UI | `['stats', playMicros, renderMicros, maxRenderMicros, frames, underruns, starvedMicros, overlaps, faults, sessions]` |
| engine → UI | `['error', message]` |

- Sizes: chunk 2048 frames; sink buffer 8192 frames (171 ms at 48 kHz, 186 ms at 44.1 kHz); `bufferTriggerPosition` 0.1.
- Fades: play 2000 ms, stop 3000 ms, interruption 200 ms; a sink failure stops every soundscape with a 5 ms fade.
- Drain: 500 ms of silence after the master is silent, then the sink closes.
- Sample rate: the device's output rate when it is 44100 or 48000 Hz, otherwise 48000 Hz. Seed: the current time in microseconds, masked to 31 bits.
- Sessions (S6 across isolates): every start appends one session to a single future chain with a generation number; a superseded session returns, so one pump loop runs at a time.
- Underruns: the lead (pull-buffer end minus voice position) is sampled at each demand; the maximum per block of 64 demands is compared with the reference set by the second block, and a drop of more than one chunk counts as one underrun.
- Statistics: a `stats` event every second of audio and at session end; a log line every 10 s of audio and at session end:

```text
FSTAT v=1 sink=<id> rate=<hz> play_us=<n> render_us=<n> max_render_us=<n> frames=<n> underruns=<n> starved_us=<n> overlaps=<n> faults=<n> sessions=<n>
FSTATE phase=<idle|playing|interrupted|stopping>
FLEAD sink=soloud ref_us=<n> jitter_us=<n> underruns=<n> starved_us=<n>      (once, when the sink stops)
```

- Engine CPU = `render_us / play_us`, render time measured from the pump's chunk start to the entry of `write`.
- Focus: `audio_session` with media/music attributes, gain type `gain`, pause when ducked. A transient loss stops the engine with the 200 ms fade and keeps `playing: true` with `processingState: buffering`; a gain resumes only from `interrupted`. A permanent loss, a notification stop and an in-app stop end with `playing: false` and idle together, the service leaves the foreground and focus is abandoned; only a tap in the app starts again. The finish step abandons focus except while a request is in flight, then the request's caller decides; a denied request is abandoned.
- Notification: Stop only; `pause` acts as stop. After idle the app polls its own notifications every 50 ms for at most 5 s and cancels notification 1124 once its foreground flag is gone.
- Measured (vivo, Android 16, release, screen off, speaker): engine CPU 17.35 % of one core, process CPU 19.71 %, zero underruns over 1 h 48 min, about 80 mAh/h for the whole phone with the screen off.

## Unit decisions: engine-profiling (unit 2b)

- Measured after the unit (vivo, Android 16, normal release, 10 minutes screen off): engine CPU 15.95 % of one core (17.31 % before), process CPU 18.30 %, zero underruns. The engine thread ran on a little core at 691.2 MHz for 98.4 % of the run. Decision: a native core; see `docs/decisions/engine-profiling.md`.
- A speed change must keep the digest set identical: `digest` renders 28 scripted cases, and their hashes at the new code must equal the baseline's on the desktop and on the phone. A change that alters one sample is a recipe change and goes through this document.
- Allowed fix classes: A, code shape only (safe pragmas, fields into locals, loop splits at a wrap point, unrolls that keep every floating-point operation and its order, `setRange` for pure copies and zero fills, length guards before a loop); B, exact identities, each with its own edge-value tests; C, skipped work whose result is unused bit for bit. Unsafe VM pragmas need the user's approval.
- Tools: `tool/digest.dart` (the 28 render hashes, `--check` and `--compare`), `tool/stage_bench.dart` (each stage's cost and the shares by subtraction), and the app's bench target, built with `--target=lib/bench_main.dart`, which runs both on the phone. A normal build holds none of the bench code.
