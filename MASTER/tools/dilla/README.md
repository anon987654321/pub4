# Dilla

Unified audio engine — synthesis, analog pads, vocal mixes, stem rack,
demux, MIDI electronium. Logic lives in `dilla.rb` plus small helpers under
`lib/` (harmony, DNA, gems, groove). Tests: `MASTER/test/test_dilla.rb`.

Two entry points:

- `MASTER/tools/dilla.rb` — chat wrapper (`generate --style …`). Older
  style maps for one-shot exports; not the live stream defaults.
- `MASTER/tools/dilla/dilla.rb` — engine. `ruby dilla.rb help` for commands.

---

## Single style: `dilla`

One stream/render profile (`DILLA_STYLE_DEFAULTS`). `RENDER_MODE=camel` is a
compat alias for the same table.

```sh
cd MASTER/tools/dilla

# Continuous stream (default bare invoke)
ruby dilla.rb
# same:
RENDER_MODE=dilla STREAM_SOUL=1 SPEAK=0 ruby dilla.rb stream 32

# One-shot
ruby dilla.rb dilla out.wav 32
# or: ruby dilla.rb camel out.wav 32
```

### What you get

| Layer | Behavior |
|---|---|
| **Harmony** | Curated progressions only (`LA_BEAT_PROGRESSION=0`) |
| **Pads** | Blend/wash, long attack/release, high harm bus |
| **Leads** | Off (`LEAD_ARP=0` wins even if pad arp is wash) |
| **Drums** | 16-step overlay kit only (`FLYLO_DRUMS_ONLY=1`); pocket kicks need `POCKET_KICKS=1` |
| **Master** | `donuts_soul` + `broadcast` |
| **Vocals** | Off by default (`RAP_VOCAL=0`); opt-in with isolation + blocklist |
| **Iterate / vinyl bed** | Off |
| **Swing** | `56%` (Dilla's documented 54-58% MPC sweet spot; was 60%) |
| **Micro-timing** | Gaussian-clustered jitter (`DillaGroove.gaussian_jitter`), not uniform random |
| **Phrase drift** | Slow tempo/timing breathe over a 6-bar sine LFO (`PHRASE_DRIFT=1`) |
| **Arrangement** | Full-layer drop-out every 8 bars for contrast (`ARRANGEMENT_VARIATION=1`) |
| **Mastering heuristics** | On (`MASTER_HEURISTICS=1`) — harshness notch, sub/kick balance, perceptual limiter |

### Signal flow

```
curated progression → pad wash + bass
        │
16-step drum grid (locked baked steps)
        │
 sidechain amix
        │
 Sonitex donuts_soul → analog broadcast → loudnorm
        │
 demo.wav + afplay
```

### Grid

Baked steps: kicks `[0, 3, 7, 10, 11, 14]`, snares `[4, 12]`, 8th hats.
`DRUM_CHOPS=1` optionally replaces kit oneshots with slices from demucs
drums under `samples/demux/...` when that file exists.

### ENV resolve

`soft_fill_env!` layers best/stream/soul defaults, then `apply_dilla_style!(force: true)`
locks the single style. `reassert_dilla_style_locks!` after track soul.

| ENV | Role |
|---|---|
| `RENDER_MODE=dilla` | Apply `DILLA_STYLE_DEFAULTS` |
| `STREAM_SOUL=1` | Soul stream soft-fills |
| `STREAM_TRACK=...` | Pin one progression |
| `STREAM_GAP` / `STREAM_CROSSFADE` | Silence between tracks |
| `POCKET_KICKS` | Pocket kit kicks (default off under overlay-only) |
| `DRUM_CHOPS` | Use demucs-sliced oneshots when available |
| `RAP_VOCAL` | slug or `0` |
| `BARS` | Default 32 |

### Optional vocals

```sh
ruby dilla.rb rap-vocal ingest "Artist" "https://..."
RAP_VOCAL=slug ruby dilla.rb dilla out.wav 32
```

---

## Command taxonomy

| Group | Commands |
|---|---|
| Render | `dilla`/`beat`, `camel`, `hiphop`, `slum`, `industrial`, `techno`, `analog`, `render` |
| Vocal | `mix`, `v7`–`v11`, `rap-vocal` |
| Sample | `prepare`, `sample`, `source`, `separate`, `demux`, `learn`, `learn-flylo`, `clean` |
| Live | `stems`, `liveset`, `live`, `stream`, `live_now`, `livestream` |
| Analysis | `scan`, `ears`, `verify`, `study`, `grade`, `chords`, `rhythm`, `melody`, `harmony`, `quality`, `debug` |
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
