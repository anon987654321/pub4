# Dilla

Unified audio engine — synthesis, analog pads, vocal mixes, stem rack,
demux, MIDI electronium. Logic lives in `dilla.rb` plus small helpers under
`lib/` (harmony, DNA, gems, groove). Tests: `MASTER/test/test_dilla.rb`.

Two entry points:

- `MASTER/tools/dilla.rb` — chat / RAILS product wrapper (`generate --style …`).
  Applies the same **kit-forward** ENV profile as the engine style table so
  one-shots match stream character (shorter bars by default).
- `MASTER/tools/dilla/dilla.rb` — engine. `ruby dilla.rb help` for commands.

Product path (brgen): `Shared::DillaProcessor` → wrapper → engine → Active Storage.

---

## Styles: `dilla` (punch) vs `comfort` (sofa)

| Profile | Activate | Character |
|---------|----------|-----------|
| **comfort** (stream default) | bare `ruby dilla.rb`, `STREAM_COMFORT=1`, `ruby dilla.rb comfort …` | One pocket kit, held pads, single melodic lead, no rap, LUFS −18, no lead rotation |
| **punch / kit-forward** | `STREAM_PUNCH=1` or `STREAM_COMFORT=0` | Hybrid FlyLo kit, hot vox, multi-lead, creative rotate |

`DILLA_STYLE_DEFAULTS` remains the kit-forward DNA table. Comfort is
`DILLA_COMFORT_DEFAULTS`, forced **after** style on stream so
`STREAM_CREATIVE_MAX` does not re-hot the mix. `RENDER_MODE=camel` is a
compat alias for dilla.

```sh
cd MASTER/tools/dilla

# Continuous comfort stream (default bare invoke) — one supervisor only
ruby dilla.rb
# explicit:
SPEAK=0 STREAM_COMFORT=1 ruby dilla.rb stream 16

# Old punch stream
STREAM_PUNCH=1 SPEAK=0 ruby dilla.rb stream 12

# One-shot comfort
ruby dilla.rb comfort out.wav 16
# One-shot kit-forward
ruby dilla.rb dilla out.wav 12

# Chat / product wrapper
cd MASTER
ruby tools/dilla.rb generate --style comfort --bars 16 --output /tmp/sofa.mp3
ruby tools/dilla.rb generate --comfort --bars 16 --output /tmp/sofa.mp3
DILLA_COMFORT=1 ruby tools/dilla.rb generate --style dilla --bars 16 --output /tmp/sofa.mp3
```

### What you get (code truth — `DILLA_STYLE_DEFAULTS`)

| Layer | Behavior |
|---|---|
| **Harmony** | Curated progressions; stream rotates `STREAM_ROTATION` (~34 tracks) |
| **Pads** | `stack_soul` held pads; **stepped back** so kit/vox read (`PAD_VOL` ~58, lower harm bus) |
| **Leads** | **On** — scale-locked arps (`LEAD_ARP=1`), rotate voice/mode (`STREAM_ROTATE_LEAD`) |
| **Drums** | **Hybrid** pocket + FlyLo overlay (`FLYLO_DRUMS_ONLY=0`, `KICKS=1`, `POCKET_KICKS=1`) |
| **Master** | `donuts_soul` + `broadcast`, loudnorm, `MASTER_HEURISTICS=1` |
| **Vocals** | Default **`RAP_VOCAL=jonas_v`** (isolated stems under `project/learnings/vocals/`); `RAP_VOCAL=0` to mute |
| **Swing** | `56%` (documented MPC 54–58% pocket) |
| **Micro-timing** | Gaussian-clustered jitter + phrase drift + arrangement drop-outs |
| **Stream** | Continuous supervisor, PID temps, single lock, normalize ~−14.5…−16.5 LUFS |

### Signal flow

```
curated progression → pads (held) + bass + scale-locked lead arps
        │
pocket kit + FlyLo overlay (+ optional Jonas V rap stem)
        │
 sidechain amix
        │
 Sonitex donuts_soul → analog broadcast → heuristics → loudnorm
        │
 demo.wav + afplay   ·   or product Active Storage attach
```

### Grid

Pocket / overlay grids (not overlay-only). `DRUM_CHOPS=1` may slice demucs
oneshots under `samples/demux/...` when present.

### ENV resolve

Full layer map + one-shot call path: **`ENV_AND_RENDER.md`**.

`soft_fill_env!` layers best/stream/soul defaults, then `apply_dilla_style!(force: true)`
on stream. `force_env!(STREAM_CREATIVE_MAX)` re-applies kit/vocal/creative after
style force (style force used to wipe stream keys). Each fill/force records
provenance → `ruby dilla.rb config-provenance` (same process after a render path).

| ENV | Role |
|---|---|
| `RENDER_MODE=dilla` | Apply `DILLA_STYLE_DEFAULTS` (`warp` = spectral/IDM bias mode) |
| `STREAM_SOUL=1` | Soul stream soft-fills |
| `STREAM_TRACK=...` | Pin one progression |
| `STREAM_BARS` / `BARS` | Bars per track (stream default often 12) |
| `STREAM_GAP` / `STREAM_CROSSFADE` | Between tracks |
| `POCKET_KICKS` / `KICKS` | Pocket kicks (on by default) |
| `FLYLO_DRUMS_ONLY` | `0` = hybrid kit (default); `1` = overlay-only (can bury kicks) |
| `DRUM_CHOPS` | Demucs-sliced oneshots when available |
| `RAP_VOCAL` | slug (e.g. `jonas_v`) or `0` |
| `SPEAK` | TTS pickup lines over the beat (`0` default in stream extras) |
| `ARP_IDM_BIAS=1` | Prefer euclidean/ratchet/stutter arps (also on via `RENDER_MODE=warp`) |
| `DILLA_RAW=1` | Skip best/style soft defaults |

### Ops notes

- **One stream process only** — lock file rejects a second continuous stream.
- Copy `demo.wav` before analysis if stream may overwrite mid-play.
- Jonas V / ingested vocals: experimental local use; **not rights-cleared** for public ship.

### Optional vocals

```sh
ruby dilla.rb rap-vocal ingest "Artist" "https://..."
RAP_VOCAL=slug ruby dilla.rb dilla out.wav 12
RAP_VOCAL=0 ruby dilla.rb dilla instrumental.wav 12
```

### Critique (MASTER, not inside the engine)

```sh
cd MASTER && bundle exec ruby bin/cli
# after a render:
/dilla metrics
/dilla crit
```

---

## Command taxonomy

| Group | Commands |
|---|---|
| Render | `dilla`/`beat`, `camel`, `hiphop`, `slum`, `industrial`, `techno`, `analog`, `render` |
| Vocal | `mix`, `v7`–`v11`, `rap-vocal` |
| Sample | `prepare`, `sample`, `source`, `separate`, `demux`, `learn`, `learn-flylo`, `clean` |
| Live | `stems`, `liveset`, `live`, `stream`, `live_now`, `livestream` |
| Analysis | `scan`, `ears`, `verify`, `study`, `grade`, `chords`, `rhythm`, `melody`, `harmony`, `quality`, `debug`, `radio-bergen-*` |
| MIDI | `electronium`/`midi` |
| Assets | `fetch-assets`, `use-external-kit` |

`DISPATCH` in `dilla.rb` is the source of truth.

## Gems

coltrane, midilib, wavefile, head_music via `lib/music_gems.rb` (`:dilla` group).

```sh
cd MASTER && bundle install
bundle exec ruby tools/dilla/dilla.rb debug
```

### Known issue: coltrane adapter hangs on some chord symbols

`DillaMusicGems.chord_from_symbol` (the `coltrane` gem path in
`lib/music_gems.rb`, tried before the built-in parser in
`DillaLofiMachine.chord_from_symbol`) hangs indefinitely — not slow, no
timeout, no output — on at least `"Dm7b5"` and `"Cmaj9"`, reproduced cold and
warm. Root cause not chased. Workaround in place: both are precomputed in
`CHORD_VOICINGS` (`lib/producer_dna.rb`) so the fast path resolves them
before the gem ever runs. If a new progression hangs on load, add its chord
symbol to `CHORD_VOICINGS` the same way rather than debugging the gem call.

## Reference material: `dilla_reference.yml`

Sourced Slum Village / Flying Lotus progressions (documented track analysis,
not ear-transcribed) and hard mastering reject-gate thresholds (crest
factor, mud-zone level, kick/bass timing correlation), each with a
`source`/`source_note`. Loaded at boot:

- `documented_progressions` merge additively into `HARMONY_PROFILES`
  (`producer_dna.rb`) — existing named profiles are never overwritten, since
  some (`chromatic_mediant_drift`, `quartal_west_coast`) are original
  Dilla/FlyLo-inspired compositions, not transcriptions.
- `loss_gates` are checked by `DillaMaster.passes_loss_gates?` before a take
  is promoted into `project/promoted_profiles.json` — a high-beauty take
  that's still over-compressed gets rejected regardless of its score. Only
  `crest_factor_db` is currently measured (`analyze_audio`'s `dynamics`
  block); the mud-zone and kick/bass-correlation gates are wired but report
  as `skipped`, not fabricated, until that analysis exists.

Chord symbols are limited to what the engine's own parser understands — a
few entries simplify the historically-documented voicing (e.g. `Bb13` →
`Bb7`) either because that extension isn't in `CHORD_SUFFIXES`, or to avoid
the coltrane hang above. See `source_note` per entry.

## Tests

```sh
cd MASTER && bundle exec ruby -Itest test/test_dilla.rb
```

`eval_in_engine`'s per-test subprocess probe (`Open3.capture3`, no timeout)
can hang independent of the coltrane issue above — a stuck `dilla_test_probe`
process pegged near 100% CPU with no output is that, not a real test
failure. Verify a change directly instead:
`ruby -e '$PROGRAM_NAME = "dilla_test_probe"; load "dilla.rb"; ...'` with a
shell `timeout` wrapper.
