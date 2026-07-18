# Dilla Lab

Unified audio engine — synthesis, analog pads, vocal mixes, stem rack,
demux, MIDI electronium. One file (`dilla.rb`) by design; the former
`dilla_enhancements.rb` split was merged back in.

Two entry points:

- `MASTER/tools/dilla.rb` — the stable MASTER entrypoint
  (`generate --style dilla|flylo|baroque|neo-soul|jazz`), used by the chat
  router's "make a Dilla beat" path. Writes to `.master/media/` and calls
  the engine with the flag interface below.
- `MASTER/tools/dilla/dilla.rb` — the engine itself.
  `ruby dilla.rb help` is the full command reference.

## Command taxonomy

| Group | Commands |
|---|---|
| Render styles | `dilla`/`beat`, `camel`, `hiphop`, `slum`, `industrial`, `techno`, `analog`, `analog_liveset`, `loose_pocket`, `render` |
| Vocal mixes | `mix`, `v7`–`v11`, `rap-vocal` (`ingest` / `fit` / `list`) |
| Sample pipeline | `prepare`, `sample`, `source`, `separate`, `demux`, `learn`, `learn-flylo`, `clean` |
| Stem rack / live | `stems`, `liveset`, `live`, `stream`, `live_now`, `livestream` |
| Analysis | `scan`, `ears`, `verify`, `study`, `grade`, `chords`, `rhythm`, `melody`, `harmony`, `semantics`, `quality`, `debug`, `sweep`, `council` |
| MIDI | `electronium`/`midi` (uses `midilib` gem via `bundle install`) |
| Assets | `fetch-assets`, `use-external-kit` (opt-in; engine is pure-Ruby/ffmpeg by default) |

The dispatch table (`DISPATCH` at the bottom of `dilla.rb`) is the single
source of truth — `COMMANDS`, help, and the `debug` dump all derive from it.

---

## The current “full sound” (Camel stream)

This is the stack that aims at warm neo-soul pads + FlyLo kit + J Dilla
vocal chops + analog glue. **Treat the pad + filter path as the locked
character** unless you deliberately want a different aesthetic.

### One-shot commands

```sh
cd MASTER/tools/dilla

# Non-stop rotation (default — same as `ruby dilla.rb stream`)
ruby dilla.rb
# equivalent explicit:
#   DILLA_STREAM_LAUNCHED=1 STREAM_CONTINUOUS=1 STREAM_SOUL=1 RENDER_MODE=camel SPEAK=0 \
#     ruby dilla.rb stream 32

# One Camel render (same mix profile, not a loop)
ruby dilla.rb camel out.wav 32
# or: ruby dilla.rb dilla out.wav 32
# or: ruby dilla.rb out.wav 32
```

`STREAM_CONTINUOUS=1` wraps an outer `while true` supervisor so the stream
restarts on crash (Ctrl-C / exit 130 stops it). Between tracks, if `dilla.rb`
mtime changes, the process reloads itself.

### Signal flow (order matters)

```
pads + bass + lead stems (fluidsynth / native)
        │
        ▼
 harmonic bus (EQ, fade, HARM_BUS_VOL)
        │
drums (pocket kit + FlyLo Camel overlay, dual-bus merge)
        │
        ▼
 sidechain amix  [drums weight high · pads duck under kicks]
        │
        ▼
 Sonitex STX-1260 emulation  (SONITEX_PRESET)
        │
        ▼
 analog grade chain  (ANALOG_CHAIN)
        │
        ▼
 master (IR reverb optional, loudnorm/limiter)
        │
        ▼
 rap-vocal layer  (atempo + bar-phase fit, sidechain under chops)
        │
        ▼
 demo.wav  +  speakers (afplay / ffplay)
```

### Layers (what you should hear)

| Layer | How it is made | Key ENV / code |
|---|---|---|
| **Pads** | Chord progression → voiced pads (Rhodes/Prophet/blend), soft attack/release | `TRACK`, `VOICING`, `PAD_VOICE`, `PAD_ATTACK` / `PAD_RELEASE`, `lib/producer_dna.rb` profiles |
| **Bass** | Root / slash bass on harmonic bus (not doubled on drum bus) | `BASS_SLIDE`, slash bass when enabled |
| **Leads** | Scale-locked arp + chord-tone harmony lead + figure lead + optional xlead morph | `LEAD_ARP=1`, `HARMONY_LEAD=1`, `LEAD_MORPH=1`, `HARMONIC_*_WEIGHT` / `VOLUME` |
| **Drums** | Hybrid: Dilla pocket kicks/snares/hats **plus** FlyLo 16-step overlay (Camel grid) | `FLYLO_DRUM_OVERLAY=1`, `KICKS=1`, `FLYLO_KICK_GAIN`, `DRUM_BUS_GAIN`, `DRUM_MIX_WEIGHT` |
| **Vocals** | Catalog acapella (default `j_dilla`) fit to BPM/bars, mixed with duck/sidechain | `RAP_VOCAL=j_dilla`, `RAP_VOCAL_MIX`, `RAP_VOCAL_DUCK`, `project/learnings/vocals/` |
| **Master color** | STX-1260-style chain + NastyVCS-ish summing | `SONITEX=donuts_soul`, `ANALOG_CHAIN=summing_phasy` |

### Pad + filter chain (keep this)

Defaults under `RENDER_MODE=camel` / `CAMEL_MODE_DEFAULTS`:

1. **Harm bus** — stereo normalize, highpass, body EQ (~420 Hz), mid lift,
   controlled air, pad fade-in, outro fade (`build_harm_bus_filter`).
2. **Sidechain** — drums key the pad duck; mix weights favor the kit
   (`SIDECHAIN_DRUM_WEIGHT` / `SIDECHAIN_HARM_WEIGHT`).
3. **Sonitex `donuts_soul`** — warm crush + head-bump + light wow, **HF open
   enough for snares/leads** (~9 kHz). Do **not** use `donuts_warm` on stream
   if you want audible snare/lead air (that preset lowpasses ~2.2 kHz).
4. **Analog `summing_phasy`** — parallel compress, harmonic bloom, stereo width,
   Haas, multiband tone, tape sat, noise (console “Summing Phasy” / 75ips glue).

Preset tables live in `dilla.rb`: `SONITEX_STX1260`, `SONITEX_PRESETS`,
`ANALOG_CHAIN_VARIANTS` (including `:summing_phasy`).

### Harmony / progressions

- Soul stream rotates `STREAM_TRACKS` / `DillaLofiMachine::STREAM_ROTATION`
  (unpinned by default).
- Camel / LA-beat arrangement: variable chord lengths, chromatic mediant /
  functional / planing sections (`arrange_camel_beat_progression`,
  `arrange_la_beat_progression`).
- Lead arps follow chord scales (`lib/harmony_lead.rb` —
  major/minor/dorian/mixo/lydian heuristics).
- Optional gems: coltrane / head_music via `lib/music_gems.rb`.

### Drums (FlyLo Camel)

- Measured grid baked in: `FLYLO_CAMEL_DRUM_GRID` (86 BPM, syncopated kicks).
- Registered under `chromatic_mediant_drift` / `flylo_camel` in
  `BUILTIN_LEARNED_ENGINE`; optional override
  `project/learnings/flylo_drums/flylo_camel.json`.
- Re-learn: `ruby dilla.rb learn-flylo <url-or-path> [track] [apply] [shallow]`.
- Hybrid kit: pocket drums stay on unless `FLYLO_DRUMS_ONLY=1`.
- Overlay from bar 0 (`CAMEL_DRUM_ENTRY_BAR=0`).

### Vocals (J Dilla chops)

```sh
# Ingest (yt-dlp → demucs → catalog)
ruby dilla.rb rap-vocal ingest "J Dilla" "https://www.youtube.com/watch?v=..."

# List catalog
ruby dilla.rb rap-vocal list
```

- Catalog: `project/learnings/vocals/catalog.json`
- Stems: `project/learnings/vocals/<slug>/vocals.wav` (often gitignored as `*.wav`)
- Fit: atempo to track BPM + best bar-phase offset, then
  `mix_rap_vocal_layer!` (sidechain-ish duck of the bed under the vocal).

Default slug under Camel: **`j_dilla`**. Set `RAP_VOCAL=0` to disable.

### Stream outputs

| Output | Path | Notes |
|---|---|---|
| Latest track | `demo.wav` (next to engine / `DILLA_OUTPUT_DIR`) | WAV = no mp3 encode (faster). Override: `STREAM_DEMO=...` |
| Log | `stream.log` | tee from continuous supervisor |
| Iterate log | `stream_iterate.log` | beauty/mix nudges when `STREAM_ITERATE=1` |
| Scratch | `.cache/` | temps; safe to wipe |

### Useful ENV (Camel / stream)

| ENV | Role |
|---|---|
| `RENDER_MODE=camel` | Apply `CAMEL_MODE_DEFAULTS` + `RENDER_MODE_DEFAULTS[:camel]` |
| `STREAM_SOUL=1` | Soul form, LA-beat progressions, FlyLo overlay defaults |
| `STREAM_TRACK=...` | Pin one progression (omit for full rotation) |
| `STREAM_CONTINUOUS=1` | Outer restart loop |
| `SONITEX` / `SONITEX_PRESET` | `donuts_soul` (stream), `donuts_warm` (darker/dustier) |
| `ANALOG_CHAIN` | `summing_phasy`, `acetate`, `vinyl_hot`, … |
| `FLYLO_DRUM_OVERLAY` | `1` = Camel grid on kit |
| `FLYLO_DRUMS_ONLY` | `1` = mute pocket kit (FlyLo only) |
| `RAP_VOCAL` | slug or `0` |
| `SPEAK` | TTS overlay (`0` = off) |
| `DRUM_MIX_WEIGHT` / `HARM_MIX_WEIGHT` | Final amix balance when not sidechained |
| `SIDECHAIN_DRUM_WEIGHT` / `SIDECHAIN_HARM_WEIGHT` | Weights inside SC mix |
| `HARMONIC_PADS_*` / `HARMONIC_SCALE_LEAD_*` / `HARMONIC_LEAD_ARP_*` | Stem faders inside harmonic bus |

Code anchors: `CAMEL_MODE_DEFAULTS`, `apply_camel_profile!`, `build_harm_bus_filter`,
`build_drum_bus_filter`, `merge_flylo_dual_bus!`, `sonitex_tape_filters`,
`analog_emulation_filters`, `mix_rap_vocal_layer!`, `stream` / `play`.

---

## Tuning: flags or ENV

Every tuning ENV var has a `--flag=value` twin usable on any command
(`FLAG_ENV` in `dilla.rb`): `--track --progression --sonitex --analog-chain
--sidechain --bars --bpm --swing --voicing --kicks`. Flags set the same ENV
internally, so both interfaces stay equivalent.

```sh
ruby dilla.rb dilla beat.mp3 --track=timeless --sonitex=donuts_warm --bars=16
```

## Scratch and outputs

- Finished renders → the invoking directory, or `DILLA_OUTPUT_DIR`.
- Stream latest → `demo.wav` (see above).
- All caches/temp audio → `.cache/` next to the engine, or
  `DILLA_SCRATCH_DIR`. Safe to wipe **except** `progressions_log.txt`:
  generated progressions never repeat, so that log is the only record of
  what actually played. Legacy dotfile logs are auto-migrated in.

## External assets

`fetch-assets` caches CC0 soundfonts + a drum-kit repo under `~/.cache/`,
recording SHA256s (and the kit repo's HEAD) into `checksums.json` on first
fetch; later runs warn if upstream content drifted, since that changes how
renders sound. Delete a manifest entry to accept a new upstream version.

## Ruby gems (outsourced logic)

Harmony, MIDI, and WAV I/O delegate to community gems when `bundle install`
has been run in `MASTER/` (the `:dilla` Bundler group):

| Gem | Source | Used for |
|---|---|---|
| [coltrane](https://github.com/pedrozath/coltrane) | pedrozath/coltrane | Chord parsing, voicings, roman-numeral progression analysis |
| [midilib](https://github.com/jimm/midilib) | jimm/midilib | Electronium MIDI export |
| [wavefile](https://github.com/jstrait/wavefile) | jstrait/wavefile | Mono WAV sample load (ffmpeg fallback) |
| [head_music](https://github.com/roberthead/head_music) | roberthead/head_music | Pitch-class sets in `harmony` study |

Adapter: `lib/music_gems.rb` (`DillaMusicGems`). Researched `CHORD_VOICINGS`
still win over gem parsing; gems fill generic symbols and analysis.

```sh
cd MASTER && bundle install
bundle exec ruby tools/dilla/dilla.rb debug   # shows gem load status
```

## Tests

`MASTER/test/test_dilla_lab.rb` — table integrity (grade presets ↔ filter
arms, dispatch ↔ COMMANDS), voicing bounds, flag parsing, wrapper→engine
contract, coltrane chord/progression adapter, Camel mode defaults / FlyLo
grid, LA-beat progressions. The whole-pipeline render smoke is opt-in:

```sh
DILLA_SMOKE=1 bundle exec ruby -Itest test/test_dilla_lab.rb
```
