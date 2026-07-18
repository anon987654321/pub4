# Dilla

Unified audio engine — synthesis, analog pads, vocal mixes, stem rack,
demux, MIDI electronium. Core logic lives in `dilla.rb` plus focused libs
under `lib/` (`producer_modes`, `stream_env`, `camel_chops`, harmony, DNA).
Tests: `MASTER/test/test_dilla.rb`.

Two entry points:

- `MASTER/tools/dilla.rb` — chat wrapper (`generate --style …`). **Not** the
  Camel/Afta stream defaults (older sonitex/cassette maps).
- `MASTER/tools/dilla/dilla.rb` — engine. `ruby dilla.rb help` for commands.

---

## Producer modes (research-backed)

Forum / Reddit / KVR consensus distilled into **one mode at a time**
(`lib/producer_modes.rb`). Do not stack all four.

| Mode | Seat | Hallmarks (from production communities) |
|---|---|---|
| **`afta`** (default) | Afta-1 / post-Dilla beat tape | Patient chords, warm EP/Rhodes wash, kit supports the loop, restraint over maximalism |
| **`dilla`** | J Dilla | Unquantized / light quant feel, early snare–late hat pocket, soul extensions (m7/m9/maj7), shorter dusty loops, light vinyl |
| **`flylo`** | Flying Lotus | Off-grid Dilla-inspired kit + denser perc, **overt sidechain** pump, abstract keys optional, Camel-grid + demucs **stem chops** |
| **`madlib`** | Madlib | Sample/dust bias, SP-303-ish color (`donuts_warm` + acetate), higher vinyl, short loops, imperfect glue |
| **`camel`** | alias of **afta** | Compatibility for `RENDER_MODE=camel` |

```sh
cd MASTER/tools/dilla

# Default stream = afta (pad-first, curated progressions, FlyLo grid only)
PRODUCER_MODE=afta ruby dilla.rb stream 32
# or bare:
ruby dilla.rb

# Explicit seats
PRODUCER_MODE=dilla  ruby dilla.rb stream 16
PRODUCER_MODE=flylo  ruby dilla.rb stream 32   # Camel chops when source wav present
PRODUCER_MODE=madlib ruby dilla.rb stream 16
```

Flags: `--mode=afta` / `--producer-mode=flylo` (see `FLAG_ENV`).

### Current afta / camel “full sound” (truth)

- **Harmony:** curated `CHORD_PROGRESSIONS` only — **no** random `planing*` LA-beat
- **Pads:** blend/wash, long attack/release, high harm bus
- **Leads:** off (`LEAD_ARP=0` wins even when pad arp is wash)
- **Drums:** FlyLo-only grid (`FLYLO_DRUMS_ONLY=1`); pocket kicks via `POCKET_KICKS` in dilla/madlib modes
- **Master:** `donuts_soul` + `broadcast` (not summing_phasy)
- **Vocals:** off by default (`RAP_VOCAL=0`); opt-in slug with isolation + blocklist
- **Iterate / dry-kit re-amp / vinyl bed:** off

### Signal flow (afta)

```
curated progression → pad wash + bass
        │
FlyLo 16-step grid (locked Camel steps)
        │
 sidechain amix (musical duck)
        │
 Sonitex donuts_soul → analog broadcast → loudnorm
        │
 demo.wav + afplay
```

### FlyLo Camel grid (baked)

Kicks `[0, 3, 7, 10, 11, 14]`, snares `[4, 12]`, 8th hats.
JSON cannot re-poison in camel/flylo drum lock.
With `CAMEL_CHOPS=1` (flylo mode), one-shots are sliced from
`samples/demux/htdemucs_6s/flylo_camel_source/drums.wav` when present.

### Vocals (optional)

```sh
ruby dilla.rb rap-vocal ingest "Slum Village" "https://www.youtube.com/watch?v=tah5UC2hdrk"
RAP_VOCAL=slum_village ruby dilla.rb camel out.wav 32
```

Never Timeless/Microphone Master (empty demucs vocals). `sirkel_sag` blocklisted.

### ENV resolve (B14)

`DillaStreamEnv.resolve_stream_env!` soft-fills layers then **force-applies**
`PRODUCER_MODE` table so iterate/soul defaults cannot clobber the seat.

Beauty locks: `reassert_camel_beauty_locks!` after track soul on afta/camel/flylo.

### Bars / kicks (B12–B13)

| Concept | ENV |
|---|---|
| Stream length | `BARS` / `STREAM_BARS` (default **32** for afta/flylo; **16** for dilla/madlib) |
| Pocket kit kicks | `POCKET_KICKS=1` (dilla/madlib). `KICKS` alone does not force pocket under FlyLo-only |
| Stream gap | `STREAM_GAP` + `STREAM_CROSSFADE` (soft silence between tracks) |

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

`DISPATCH` at the bottom of `dilla.rb` is the source of truth.

---

## Gems

| Gem | Used for |
|---|---|
| [coltrane](https://github.com/pedrozath/coltrane) | Chords / progressions |
| [midilib](https://github.com/jimm/midilib) | MIDI export |
| [wavefile](https://github.com/jstrait/wavefile) | WAV load |
| [head_music](https://github.com/roberthead/head_music) | Pitch-class study |

```sh
cd MASTER && bundle install
bundle exec ruby tools/dilla/dilla.rb debug
```

## Tests

```sh
cd MASTER && bundle exec ruby -Itest test/test_dilla.rb
DILLA_SMOKE=1 bundle exec ruby -Itest test/test_dilla.rb -n test_smoke
```

Covers dispatch, voicing, Camel/afta locks, producer modes, lead-off,
no-planing progressions, soft-fill iterate, FlyLo schedule, rap blocklist.
