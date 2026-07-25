# Dilla

Unified audio engine — one DNA: `dilla.rb`. Progressions, pocket drums, theory
runtime (Bach + J Dilla), analog/sonitex master. Helpers under `lib/`.
Tests: `MASTER/test/test_dilla.rb`.

## Entry points

- `MASTER/tools/dilla/dilla.rb` — engine (`ruby dilla.rb help`)
- `MASTER/tools/dilla.rb` — product wrapper (`generate --track …`)

Product path (brgen): `Shared::DillaProcessor` → wrapper → engine → Active Storage.

**No styles. No command aliases.** Optional ENV knobs only
(`STREAM_COMFORT`, `RENDER_MODE=warp`, `THEORY_BACH=1`, …).

## Usage

```sh
cd MASTER/tools/dilla

# Continuous stream (rotates progressions + drums)
ruby dilla.rb
SPEAK=1 ruby dilla.rb stream 16

# One-shot
ruby dilla.rb dilla out.wav 12
TRACK=neo_soul THEORY_BACH=1 ruby dilla.rb dilla out.wav 16

# Product
cd MASTER
ruby tools/dilla.rb generate --track get_dis_money --bars 12 --output /tmp/beat.mp3
```

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
bundle exec ruby tools/dilla/dilla.rb debug
```

## Tests

```sh
cd MASTER && bundle exec ruby -Itest test/test_dilla.rb
```
