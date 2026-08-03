# Dilla — ENV layers + render path

**One engine. One DNA.** There are no style profiles or command aliases.
The style is `dilla.rb` itself. Optional ENV knobs only.

Sources of truth:

| Path | Role |
|------|------|
| `dilla.rb` | Engine: `DILLA_STYLE_DEFAULTS`, `DILLA_BEST_DEFAULTS`, stream tables, render, DISPATCH |
| `lib/theory_runtime.rb` | Bach + Dilla voicing operators (not styles) |
| `lib/groove_engine.rb` | Sparse pocket phrases + micro-timing |

There is no separate product wrapper — `RAILS/shared/app/services/shared/dilla_processor.rb`
shells straight out to this file with `RENDER_MODE=dilla` and `TRACK`/`PROGRESSION`
set from the requested style (see `Shared::DillaProcessor#run_script`).

Inspect after a path that records provenance:

```sh
ruby dilla.rb config-provenance
```

---

## ENV layer order

Lower layers only **soft-fill** (set if empty). Later **force** overwrites.

### Product one-shot (`Shared::DillaProcessor` → `ruby dilla.rb dilla <out> <bars>`)

```
1. process ENV overrides     DillaProcessor sets RENDER_MODE=dilla, TRACK/PROGRESSION, RAP_VOCAL, …
2. engine boot
3. apply_best_defaults!      soft: RENDER_MODE table → DILLA_BEST → optional DILLA_DEEP
4. apply_dilla_style!        soft STYLE DNA
5. render_dilla
```

### Stream (`ruby dilla.rb` / `ruby dilla.rb stream`)

```
1. apply_stream_listenability_defaults!
     apply_best_defaults!              soft best (+ deep if STREAM deep)
     STREAM_COMFORT soft default         unless STREAM_PUNCH=1 or STREAM_COMFORT=0
     STREAM_EXTRA_DEFAULTS             soft (SPEAK, kit gains, RAP_VOCAL, LUFS, …)
     STREAM_FAST or DILLA_DEEP         soft
     STREAM_SOUL_DEFAULTS              soft when STREAM_SOUL≠0 or comfort
     apply_dilla_style!(force:true)    force full STYLE DNA
     if comfort_mode?
       DILLA_COMFORT_DEFAULTS          force sofa mix (SPEAK excluded from wipe)
     else
       STREAM_CREATIVE_MAX             force kit/vox layer after style
2. stream_rotate_drums! + track order  progressions + DRUM_PRESET/POCKET_SET
3. play("dilla", bars) → render_dilla
```

**Comfort vs punch:** stream defaults to sofa when comfort is on. Opt out with
`STREAM_PUNCH=1` or `STREAM_COMFORT=0`. One-shot comfort: `DILLA_COMFORT=1`.

**`DILLA_RAW=1`:** skip `apply_best_defaults!` soft fills — operator ENV only.

---

## Table map

| Table | Verb | Role |
|-------|------|------|
| `RENDER_MODE_DEFAULTS` | soft | sketch/record/perform/long_soul/golden/**warp** |
| `DILLA_BEST_DEFAULTS` | soft | Baseline knobs aligned with STYLE (no soft-fill conflicts) |
| `DILLA_DEEP_DEFAULTS` | soft | Quality gates + pocket jitter when deep |
| `DILLA_STYLE_DEFAULTS` | fill/force | **Canonical dilla DNA** (the only style) |
| `DILLA_COMFORT_DEFAULTS` | force when comfort | Sofa: calmer mix, no SPEAK wipe of user SPEAK |
| `STREAM_EXTRA_DEFAULTS` | soft then force as creative max (punch) | Stream kit/vox/normalize |
| `STREAM_SOUL_DEFAULTS` / `STREAM_FAST_DEFAULTS` | soft | Soul vs fast tradeoffs |

### `RENDER_MODE=warp` (opt-in knob, not a style)

Turns on already-built creative knobs: spectral arp/stack, `ARP_IDM_BIAS`,
drum chops, `GROOVE_DNA=cosmogramma`, quartal voicing, dub_chamber chain.

### Operator knobs (common)

| ENV | Role |
|-----|------|
| `TRACK` / `PROGRESSION` | Progression id (e.g. `get_dis_money`, `neo_soul`) |
| `BARS` / `STREAM_BARS` | Length |
| `STREAM_COMFORT` / `STREAM_PUNCH` | Sofa vs kit-forward stream |
| `DILLA_COMFORT` | Sofa overlay on one-shot |
| `RENDER_MODE` | `dilla` (default) or `warp` / sketch modes |
| `POCKET_SET` | `neo_soul` (default), `classic`, `dusty`, `industrial` |
| `KICK_GAIN` / `DRUM_BUS_VOL` | Quiet kit bus (~0.68 / 0.95) |
| `CHOIR_VOX` / `CHOIR_VOX_GAIN` | Soft ooh/aah on chord tones (`1` / `0.28` default; soft-fails) |
| `VOCAL_CARVE` | Carve pads under rap stem (`1` when rap on) |
| `STREAM_CREATIVE` / `STREAM_PUNCH` | Opt-in wild layer (LA_BEAT/vinyl/hot LUFS) — **off** by default |
| `DILLA_SH_TIMEOUT` | Kill hung ffmpeg/fluidsynth (default 120s) |
| `THEORY_RUNTIME` / `THEORY_DILLA` / `THEORY_BACH` | Voicing operators |
| `PAD_VOICE` / `PAD_VOL` / `PAD_LAYERS` | Pad bed |
| `LEAD_ARP` / `HARMONY_LEAD` / `SCALE_LEAD` | Lead layers |
| `RAP_VOCAL` | Vocal slug or `0` |
| `SONITEX` / `ANALOG_CHAIN` | Master character |
| `STREAM_NORMALIZE` / `STREAM_LUFS` | Loudnorm target |
| `SPEAK` | TTS over beat (`0` product default) |
| `STREAM_DRUM_ROTATE` | Cycle drum preset/pocket each stream slot |
| `FLYLO_DRUM_OVERLAY` / `DRUM_CHOPS` / `FM_DRUMS` | Off by default (sparse soul kit) |
| `DILLA_RAW` | Skip best soft defaults |
| `GROOVE_ENGINE` / `POCKET_DNA` | Pocket humanize (default on) |

Full DNA is large (mix bus dB, harmonic stem weights). Prefer
`config-provenance` after a render over memorizing every key.

---

## One-shot render path

```sh
cd STUDIO/dilla
TRACK=get_dis_money PROGRESSION=get_dis_money ruby dilla.rb dilla /tmp/beat.wav 12
```

### 1. Engine CLI (`DISPATCH["dilla"]`)

1. Destination + bars
2. Best defaults (unless `DILLA_RAW`) + style DNA
3. `render_dilla(dest, bars)`

### 2. `render_dilla` (core)

```
require ffmpeg · cleanup · pick_render_seed!
ensure_drum_kit!
cfg = dilla_resolve_config
composition_session! if COMPOSITION=1
pick_synth_patches!
pads = dilla_progression(cfg)
arrange + beautify (harmony)
theory_runtime refine (Bach/Dilla operators)
events = dilla_schedule(...)   # sparse pocket + groove_engine
render_sample_bus_wav → drums
render_harmonic_wav:
  pads (stack_soul layers)
  + CHOIR_VOX chord-tone ooh/aah (soft)
  + tones / leads / pluck
sidechain amix → sonitex → analog → heuristics → loudnorm
```

### 3. Product attach (RAILS)

`Shared::DillaProcessor.render_to_file!` → engine → Active Storage.

---

## Stream rotation

- **Progressions:** full pack (priority first: `get_dis_money`, neo-soul, untitled, …)
- **Drums:** `STREAM_DRUM_ROTATION` — soulful kits only (`dilla_slight`, `mpc3000`, …)
- **No style sequence** — one DNA every slot; mix knobs only (`STREAM_COMFORT`, etc.)
- **Style DNA wins** after force; `STREAM_CREATIVE_MAX` only when `STREAM_CREATIVE=1` or `STREAM_PUNCH=1`

## Full playlist demo

```sh
cd STUDIO/dilla
SPEAK=0 ruby dilla.rb demo-all 12 demo.wav
# resume skips existing parts; DEMO_FORCE=1 re-renders all
# DEMO_TRACK_TIMEOUT=150 DEMO_ALBUM_NORM=1
```

---

## Provenance debugging

```sh
cd STUDIO/dilla
SPEAK=0 BARS=4 ruby -e '
  load "dilla.rb"
  apply_best_defaults!
  apply_dilla_style!(force: true)
  print_config_provenance
'
```

---

## Related files

| Path | Role |
|------|------|
| `dilla.rb` | Monolith + DISPATCH + ENV tables |
| `lib/producer_dna.rb` | Chords, timing DNA |
| `lib/groove_engine.rb` | Pocket phrases, Gaussian jitter, phrase drift |
| `lib/harmony_engine.rb` | Beautify / insight |
| `lib/theory_runtime.rb` | Bach + Dilla voicing refine |
| `lib/composition_engine.rb` | Form, performers |
| `lib/master_heuristics.rb` | Master FX + loss gates |
| `lib/music_gems.rb` | coltrane / head_music / midilib / wavefile |
| `README.md` | Usage summary |
