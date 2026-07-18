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

## Tests

```sh
cd MASTER && bundle exec ruby -Itest test/test_dilla.rb
```
