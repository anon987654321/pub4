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

## Gems

```sh
cd MASTER && bundle install
cd ../studio/dilla && bundle exec ruby dilla.rb debug
```

## Tests

```sh
cd MASTER && bundle exec ruby -Itest test/test_dilla.rb
```
