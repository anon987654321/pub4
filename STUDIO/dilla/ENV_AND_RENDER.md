# Dilla — ENV layers + render path

**One DNA table, several renderers.** Command aliases (`comfort`, `camel`, `warp`)
are gone — those are ENV overlays on `RENDER_MODE=dilla`. Genre *renderers*
(`techno`, `hate`, `industrial`, `analog`, `loose_pocket`) are real DISPATCH
keys with their own arrangement. Optional ENV knobs only; `config-provenance`
after a render beats memorizing the table.

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
| `TRACK` / `PROGRESSION` | Progression id (e.g. `pedal_e_descent`, `neo_soul`) |
| `BARS` / `STREAM_BARS` | Length |
| `STREAM_COMFORT` / `STREAM_PUNCH` | Sofa vs kit-forward stream |
| `DILLA_COMFORT` | Sofa overlay on one-shot |
| `RENDER_MODE` | `dilla` (default) or `warp` / sketch modes |
| `POCKET_SET` | `neo_soul` (default), `classic`, `dusty`, `industrial` |
| `KICK_GAIN` / `DRUM_BUS_VOL` | Kit bus (`0.88` / `0.95` in `DILLA_STYLE_DEFAULTS`) |
| `CHOIR_VOX` / `CHOIR_VOX_GAIN` | Soft ooh/aah (`0` / `0.16` default; `CHOIR_VOX=1` re-enables) |
| `STREAM_CREATIVE` / `STREAM_PUNCH` | Opt-in wild layer (LA_BEAT/vinyl/hot LUFS) — **off** by default |
| `DILLA_SH_TIMEOUT` | Kill hung ffmpeg/fluidsynth (default 120s) |
| `DILLA_FS_DRY` | Fluidsynth with its own chorus/reverb off — **off** by default; costs 12.6 dB of pad side-channel |
| `THEORY_RUNTIME` / `THEORY_DILLA` / `THEORY_BACH` | Voicing operators |
| `PAD_VOICE` / `PAD_VOL` / `PAD_LAYERS` | Pad bed |
| `LEAD_ARP` / `HARMONY_LEAD` / `SCALE_LEAD` | Lead layers |
| `RAP_VOCAL` | Vocal slug or `0` |
| `SONITEX` / `ANALOG_CHAIN` | Master character |
| `STREAM_NORMALIZE` / `STREAM_LUFS` | Loudnorm target |
| `SPEAK` | TTS over beat (`0` product default) |
| `STREAM_DRUM_ROTATE` | Cycle drum preset/pocket each stream slot |
| `WONKY_DRUM_OVERLAY` / `DRUM_CHOPS` | Off by default (sparse soul kit) |
| `FM_DRUMS` | On (`1`) — FM kit is the default replacement |
| `DILLA_RAW` | Skip best soft defaults |
| `GROOVE_ENGINE` / `POCKET_DNA` | Pocket humanize (default on) |
| `GROOVE_FEEL` | `boom_bap` (**default**), `dilla_drag`, `camel` — the microtiming table |
| `LA_BEAT_PROGRESSION` | LA-beat arranger — **off**; see the Camel warning below |
| `MASTER_SMOOTH_DB` / `MASTER_SMOOTH_HZ` | De-harsher: 2 dB out at 3200 Hz by default |
| `HARM_PRESENCE_DB` / `DRUM_PRESENCE_DB` | Presence boosts, +1.6 and +1.5 — same band the de-harsher cuts |
| `RENDER_SEED` | Pins the whole render. Drawn and recorded when unset — see Provenance |
| `DEMO_TRACKS` | Explicit comma-separated order; beats every other rule in `demo_all_order` |
| `RENDER_BEAUTY_MIN` | Harmony floor before a render is kept (55–78 across profiles) |

Three of these are worth stating outright because each one is a documented
capability that is off, or a default that surprises:

- **`GROOVE_FEEL` defaults to `boom_bap`**, so the Dilla microtiming this engine
  is named for is not applied unless asked. `dilla_drag` is the snare-behind
  table; `camel` drags further and pulls the hats early, which is what reads as
  broken rather than swung.
- **`LA_BEAT_PROGRESSION` is off on purpose**, and the reason is specific:
  forcing it on Camel injected random planing-style chords and made streams
  sound broken. It and the fugue arranger both rewrite the progression, so
  running both means two arrangers fighting over the same chords.
- **Presence is boosted twice and cut once.** `HARM_PRESENCE_DB` adds 1.6 dB
  and `DRUM_PRESENCE_DB` 1.5 dB around the presence band; `MASTER_SMOOTH_DB`
  takes 2 dB back out at 3.2 kHz. Net is still a boost into the band the comment
  at `master_smooth!` calls "where distortion and harshness actually live". If a
  render is rough on the ears, this arithmetic is the first place to look, not
  the tape stage.

Full DNA is large (mix bus dB, harmonic stem weights). Prefer
`config-provenance` after a render over memorizing every key.

## Switches, by what they touch

Sample handling:

| switch | what |
|---|---|
| `HARMONIC_KEEP=1` | transpose generated pads onto the loop's detected key |
| `HARMONIC_SHUFFLE=1` | order chords so the top voice traces one arc |
| `ORGANIC_VARY=1` | rebuild the bed as N differing passes — `-stream_loop` is bit-identical, and nothing acoustic is |
| `LOOP_CHOP_SLICES=8` | cut each pass into slices and rotate them; the loop becomes material rather than a part |
| `SAMPLE_LOOP_VARISPEED` | pitch follows tempo, as a record does (default on) |
| `SAMPLE_LOOP_SEMITONES` | pitch **without** changing tempo |
| `SAMPLE_FM=1` | audio-rate vibrato = real FM sidebands, floored at 700 Hz so chord tones are untouched |
| `SAMPLE_SCALE=1` | layer the loop at degrees of its own key |
| `LOOP_WOW_CENTS` | tape instability on the loop only, never the kit |
| `LOOP_DELAY_BEATS` | tempo-synced echo (1.5 = dotted-8th) |

Two loops as one instrument — `DILLA_XSAMPLE` names the partner:

| switch | what |
|---|---|
| `DILLA_XCONVOLVE=1` | one loop becomes the room the other plays in |
| `DILLA_XGATE=1` | one loop's harmony driven by the other's rhythm (`amultiply`, not a gate) |

Drums:

| switch | what |
|---|---|
| `DRUM_PRESET` | any drum preset key (`ruby -e` / `DRUM_PRESET=boom_bap`) |
| `NO_QUANTIZE=1` | quantise off entirely |
| `SWING_ROLE_SPREAD` | how far the per-voice lean spreads |
| `WONKY_DRUM_OVERLAY=1` | Camel dual-bus: sub at 55/110/180, top at 3.5k/6.5k/9k |
| `WONKY_TOP_DIRT` | phaser/flanger/crush on cymbals, kick untouched |
| `WONKY_HAT_DUCK` | duck the top bus by the kick bus |
| `DRUM_FIELD_LAYER` | room tone under the kit, ducked by it |

Movement and master. The analog stages are **on by default**. Every one of them
shipped built and set to `0`, so for a long time nothing this engine rendered had
ever been through them. Set a switch to `0` for that older, drier behaviour.

| switch | default | what |
|---|---|---|
| `BUS_ANALOG` | `0.3` | per-channel saturation plus small phase offsets, so buses don't sum coherently |
| `CONSOLE_STRIP` | `0.35` | per-channel desk model; L and R run one seed apart, which is the point |
| `TAPE_HYSTERESIS` | `0.25` | Jiles-Atherton, RK4 — path-dependent, unlike every other stage |
| `TAPE_BIAS` | `1.0` | 1 = original loop; lower = less bias, wider hysteresis (ChowTape) |
| `TAPE_LOSS_HZ` | `0` | spacing/loss lowpass into JA; 0 is off, 14000 is the analog start |
| `TAPE_WOW_MS` | `0.6` | Ornstein-Uhlenbeck flutter |
| `SONITEX_MIX` / `_DISTORTION` / `_VINYL` / `_TONE` / `_NOISE` / `_SAMPLING` | — | **No reader.** Setting these changes nothing; use `SONITEX` / `SONITEX_PRESET` |
| `MASTER_SMOOTH_DB` | `2.0` | takes 2 dB out of the presence band; the stage that answers "harsh" |
| `SMOOTH_ANALOG` | `1` | drop patches on metallic GM programs (chromatic percussion, 94, 98, 99, 103) |
| `MASTER_TILT_DB` | `0` | negative = darker; lows up as highs come down |
| `MONO_BASS_HZ` | — | sum below N to mono |
| `ORGANIC_BREATH` / `ORGANIC_SWELL` | `0` | correlated loudness+brightness; phrase swell |
| `DILLA_DROPOUT_EVERY` | — | silence just before every Nth downbeat |
| `DILLA_DRONE` / `DILLA_TAPE_STOP` | `0` | stretched bed; platter brake |

Arps and groove:

| switch | default | what |
|---|---|---|
| `NO_ARP` | `1` | held chords and melodic lead phrases; covers **three** separate arp paths |
| `GROOVE_FEEL` | `boom_bap` | `boom_bap` / `dilla_drag` / `camel` — per-voice tick offsets at 96 PPQ |
| `BASS_FEEL` | `1` | let the bass take the feel's offset instead of sitting on the grid |

`NO_ARP` reaches `pad_arp_mode`, `lead_true_arp_mode?` and `lead_events_scale_arp`.
It was added covering only the first, which meant pads went quiet and the leads
kept arpeggiating — and `STREAM_STYLE_SAFE` and `stream_iterate` both set
`LEAD_FORCE_ARP=1` per track, so the forced flag won every time.

Vocals (`RAP_VOCAL=<slug>`, `0` to disable):

| switch | what |
|---|---|
| `RAP_VOCAL_SNAP` | place sung lines on the grid instead of stretching |
| `RAP_VOCAL_LEAN_MS` | drag each line behind the beat, plus a fixed walk |
| `RAP_VOCAL_SWELL` | reverse pre-swell arriving on each line's downbeat |

Snapping exists because a freely-sung take has no tempo to stretch onto. Across
source BPMs 96–128 against a 92 beat, one take landed 31/20/19/18/25/14% of its
onsets on the grid against a ~20% random baseline — slowing it made alignment
*worse*. Placing lines instead took line starts to 87% on grid at a 5 ms median.

## One-shot render path

```sh
cd STUDIO/dilla
TRACK=pedal_e_descent PROGRESSION=pedal_e_descent ruby dilla.rb dilla /tmp/beat.wav 12
```

### 1. Engine CLI (`DISPATCH["dilla"]`)

1. Destination + bars
2. Best defaults (unless `DILLA_RAW`) + style DNA
3. `render_dilla(dest, bars)`

### The shape of a render

```
progression  ──►  theory refine  ──►  pads · bass · leads ──┐
                                                            │
sampled loop ──►  varispeed · chop · vary · EQ ─────────────┤
                                                            ├──►  bus analog
drum grid    ──►  microtiming · swing · dirt · duck ────────┘      (saturation
                                                                    per channel)
                                                                        │
        sonitex tape ──► analog chain ──► loudnorm ──► tape hysteresis
                                       ──► tilt ──► dropout ──► mono bass
```

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

## Stream rotation

- **Progressions:** full pack (priority first: `pedal_e_descent`, neo-soul, untitled, …)
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

## Provenance debugging

Every run writes a `<file>.dilla` beside each audio file it produced —
`lib/provenance.rb`, hooked at the CLI entry before anything reads a seed. It
carries the render seed, argv, the env knobs that change the output, the engine
commit, whether the working tree was clean, and a sha256.

```sh
ruby dilla.rb replay renders/beats/direction_v4.wav.dilla
# RENDER_SEED=1505395575 TRACK=circle_fifths_descent … ruby dilla.rb dilla …
```

`RENDER_SEED` is drawn and recorded when unset rather than left to chance. The
consequence is worth knowing: an unpinned render now runs through the *pinned*
code paths, so noise comes from `seed_for(tag)` rather than ffmpeg's `seed=-1`.
Two unpinned renders still differ from each other exactly as before; each is now
a draw that can be replayed instead of one that cannot. `DILLA_NO_PROVENANCE=1`
restores the old behaviour, seed and all.

Nothing before 2026-08-11 is reproducible. The 616 audio files in the tree at
that point, `su_tunnel_choir.wav` among them, have no recorded seed and cannot
be made again.

For the resolved ENV rather than the render:

```sh
cd STUDIO/dilla
SPEAK=0 BARS=4 ruby -e '
  load "dilla.rb"
  apply_best_defaults!
  apply_dilla_style!(force: true)
  print_config_provenance
'
```

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
