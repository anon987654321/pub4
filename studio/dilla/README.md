# Dilla

Unified audio engine — one DNA: `dilla.rb`. Progressions, pocket drums, theory
runtime (Bach + J Dilla), analog/sonitex master. Helpers under `lib/`.
Tests: `MASTER/test/test_dilla.rb`.

## Entry points

- `studio/dilla/dilla.rb` — the engine, single entry point (`ruby dilla.rb help`)

There is no separate product wrapper anymore — it was folded into the engine
(`DILLA_BEST_DEFAULTS` / `DILLA_STYLE_DEFAULTS` soft-fill under `RENDER_MODE=dilla`
does what the old wrapper's `PRODUCT_ENV` table did).
Product path (brgen): `Shared::DillaProcessor` → engine → Active Storage.

**No styles. No command aliases.** Optional ENV knobs only
(`STREAM_COMFORT`, `RENDER_MODE=warp`, `THEORY_BACH=1`, …).

## Usage

```sh
cd studio/dilla

# Continuous stream (rotates progressions + drums)
ruby dilla.rb
SPEAK=1 ruby dilla.rb stream 16

# One-shot
ruby dilla.rb dilla out.wav 12
TRACK=neo_soul THEORY_BACH=1 ruby dilla.rb dilla out.wav 16
```

Product path (from RAILS, e.g. `Shared::DillaProcessor`) shells out the same
way, with `RENDER_MODE=dilla` and `TRACK`/`PROGRESSION` set from the record's
style — see `RAILS/shared/app/services/shared/dilla_processor.rb`.

## Theory runtime (Bach + Dilla as Ruby)

`lib/theory_runtime.rb` runs after harmony beautify (default on):

| Mode | When | What |
|------|------|------|
| **Dilla** | `THEORY_DILLA=1` (default) | Common-tone lock, slash/pedal bass bias |
| **Bach** | `THEORY_BACH=1` or baroque/bach tracks | Stepwise outer lead, soft parallel 5th/8ve fix |

Gems via `lib/music_gems.rb`: **coltrane**, **head_music**, **midilib**, **wavefile**
(`bundle install` in MASTER). Theory still runs without them (pure math fallback).

## What you get

| Layer | Behavior |
|---|---|
| **Harmony** | Curated progressions; stream rotates pack |
| **Theory** | Bach/Dilla runtime on pad voicings |
| **Pads** | `stack_soul` held; soft `CHOIR_VOX` ooh/aah on chord tones |
| **Drums** | Sparse neo-soul pocket phrases; sample kit (no dual FlyLo by default) |
| **Master** | `donuts_soul` + `broadcast` + loudnorm + heuristics |
| **Stream** | Progressions + drum preset rotation |

## Signal flow

```
progression → theory refine → pads + bass + leads
        │
sparse pocket kit (+ optional rap stem)
        │
 sidechain amix → sonitex → analog → heuristics → loudnorm
```

## Sampled loops

`TRACK_SAMPLE_LOOPS` holds the operator's own loops. Each carries its tempo and
its own low-end correction, because the loops differ and one global value is
wrong for whichever loop it was not tuned against.

| track | source | tempo | key | low end |
|---|---|---|---|---|
| `kembara_rindu` | 4-bar Ableton loop | 92 | C minor (0.71) | hp 90, −7 dB @ 90 |
| `semua_untuk_mu` | 0:36–0:46 | 96 | G minor (0.836) | flat |
| `dmaj_open` | first 4 bars | 114 | D major (0.697) | hp 60, −3 dB (provisional) |

Old ingest names (`four_seven`, `nightbus`) still resolve via
`TRACK_SAMPLE_LOOP_ALIASES`, including for layer-profile lookup.

**Getting a loop's boundaries right is a manual job.** Onset and energy
detection finds where something *changes*, which is not where a musical phrase
*starts* — it put `semua_untuk_mu` 22 seconds early, on the end of a spoken
intro. Given a boundary the analysis is reliable and will confirm or refute it
(key fit 0.27 for the detector's cut against 0.836 for the operator's). Asked to
find one, it is not.

Where two analyses disagree on tempo, loop the candidates and measure the seam:
a correct length rejoins itself quietly. On `dmaj_open`, 8.421s (114 BPM) rejoins
at −1.1 dB and 8.000s (120) at −8.6 dB, settling a disagreement between the
onset sweep and a self-similarity peak. Self-similarity finds the shortest thing
that repeats, which is not necessarily the bar.

## Shaping switches

Sample handling:

| switch | what |
|---|---|
| `HARMONIC_KEEP=1` | detect the loop's key, transpose the generated pads onto it |
| `HARMONIC_SHUFFLE=1` | order chords so the top voice traces one arc |
| `ORGANIC_VARY=1` | rebuild the bed as N passes, each differing slightly — `-stream_loop` is bit-identical and nothing acoustic is |
| `SAMPLE_FM=1` | audio-rate vibrato = real FM sidebands, floored at 700 Hz so chord tones are untouched |
| `SAMPLE_SCALE=1` | layer the loop at degrees of its own key |
| `SAMPLE_LOOP_HP`, `SAMPLE_LOOP_SUB_DB` | per-loop low-end clearing (defaults live in the table) |
| `LOOP_WOW_CENTS` | tape instability on the loop only, never the kit |
| `LOOP_DELAY_BEATS` | tempo-synced echo (1.5 = dotted-8th) |

Two loops as one instrument — `DILLA_XSAMPLE` names the partner:

| switch | what |
|---|---|
| `DILLA_XCONVOLVE=1` | one loop becomes the room the other plays in |
| `DILLA_XGATE=1` | one loop's harmony driven by the other's rhythm (`amultiply`, not a gate) |

Movement and master:

| switch | what |
|---|---|
| `ORGANIC_BREATH=1` | loudness and brightness from one control signal |
| `ORGANIC_SWELL=1` | phrase-length swell, applied post-master |
| `MONO_BASS_HZ` | sum below N to mono |
| `DILLA_DRONE=1` | stretched bed from the engine's own pad bus |
| `DILLA_TAPE_STOP=1` | platter brake; `_BEATS` means heard length, not source length |

Vocals (`RAP_VOCAL=<slug>`, `0` to disable):

| switch | what |
|---|---|
| `RAP_VOCAL_SNAP` | place sung lines on the grid instead of stretching — for takes with no steady pulse, where no `atempo` ratio can work |
| `RAP_VOCAL_LEAN_MS` | drag each line behind the beat by a base plus a fixed walk |
| `RAP_VOCAL_SWELL=1` | reverse pre-swell arriving on each line's downbeat |
| `RAP_VOCAL_RAW_SEAMS=1` | 3 ms seams, so chop tails collide |

## Controls that are not what they look like

Several env names read as if they do one thing and do another. Each of these
cost real debugging time:

- **`DRUM_VOL` does nothing in the main render.** It is read inside
  `build_harmony_loud`, a different path. Muting the drums with it measures
  identically to pushing it to 0.72. Use `DRUM_MIX_WEIGHT`, `DRUM_BUS_VOL`,
  `DRUM_BUS_GAIN`.
- **`KICK_GAIN` will not fix a loud low end** if the loop is making it. On
  `kembara_rindu`, muting the kick moved the 40–100 Hz band by 0.0 dB and
  muting the loop moved it by 4.0 dB. Reach for `SAMPLE_LOOP_HP` first.
- **Making room beats adding gain.** Most of a +9.2 dB drum improvement came
  from lowering `HARM_MIX_WEIGHT` and `SAMPLE_LOOP_WEIGHT`, not from raising
  the drums.
- **Track profiles override the command line by default.** `TRACK_LAYER_PROFILES`
  switches leads and textures off for some tracks; pinning them only works
  because `USER_PINNED_ENV` now lets a caller win.
- **`RAP_VOCAL=0` must be explicit.** `DILLA_STYLE_DEFAULTS` soft-fills it to a
  vocal slug, so omitting it puts a vocal on every render.
- **Measure with `STREAM_NORMALIZE=0`.** With normalisation on, removing a
  layer makes the rest *louder* and the measurement describes the normaliser.

## Gems

```sh
cd MASTER && bundle install
cd ../studio/dilla && bundle exec ruby dilla.rb debug
```

## Tests

```sh
cd MASTER && bundle exec ruby -Itest test/test_dilla.rb
```
