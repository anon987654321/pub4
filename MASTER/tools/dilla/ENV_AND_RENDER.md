# Dilla — ENV layers + one-shot render path

Source of truth for tables: `dilla.rb` (`DILLA_*`, `STREAM_*`, `RENDER_MODE_DEFAULTS`)
and product wrapper `MASTER/tools/dilla.rb` (`PRODUCT_KIT_ENV`).

Inspect after a render: `ruby dilla.rb config-provenance` (keys → which table filled/forced them).

---

## ENV layer order

Lower layers only **soft-fill** (set if empty). Later **force** overwrites.

### Product one-shot (`tools/dilla.rb generate`)

```
1. PRODUCT_KIT_ENV          force via system(env, …)  — kit-forward, RAP_VOCAL, loudnorm
2. process ENV overrides    operator shell keys win over PRODUCT_KIT_ENV for those keys
3. engine boot
4. apply_best_defaults!     soft: RENDER_MODE table → DILLA_BEST → optional DILLA_DEEP
5. apply_dilla_style!       soft or force STYLE (product usually soft; RENDER_MODE=dilla)
6. CLI flags / TRACK        --track= etc. on engine argv
7. render_dilla
```

`PRODUCT_KIT_ENV` (~43 keys) mirrors kit/vox/mix from `DILLA_STYLE_DEFAULTS` so
chat/RAILS one-shots match stream character without going through stream force.

### Stream (`ruby dilla.rb stream` / bare invoke)

```
1. apply_stream_listenability_defaults!
     apply_best_defaults!           soft best (+ deep if STREAM deep)
     STREAM_COMFORT=1 soft default   unless STREAM_PUNCH=1 or STREAM_COMFORT=0
     STREAM_EXTRA_DEFAULTS          soft (SPEAK, kit gains, RAP_VOCAL, LUFS, …)
     STREAM_FAST or DILLA_DEEP      soft
     STREAM_ITERATE_TUNING          soft iterate (if enabled and not comfort)
     STREAM_SOUL_DEFAULTS           soft (STREAM_SOUL≠0 or comfort)
     apply_dilla_style!(force:true) force full STYLE table (+ comfort soft if on)
     if comfort_mode?
       DILLA_COMFORT_DEFAULTS       force  (no STREAM_CREATIVE_MAX — keeps sofa mix)
     else
       STREAM_CREATIVE_MAX          force  (= STREAM_EXTRA — re-assert after style wipe)
       STREAM_ITERATE_TUNING        force  (if iterate)
2. per-track voice rotation (only if STREAM_ROTATE_*=1; comfort sets 0)
3. play("dilla", bars) → render_dilla
```

**Why force twice (punch):** `apply_dilla_style!(force: true)` used to wipe stream
creativity. `STREAM_CREATIVE_MAX` re-applies the creative kit layer.

**Comfort:** stream defaults to sofa mix. Opt out with `STREAM_PUNCH=1` or
`STREAM_COMFORT=0`. One-shot: `ruby dilla.rb comfort out.wav 16`.

### `DILLA_RAW=1`

Skips `apply_best_defaults!` soft fills — operator ENV only (+ style if still applied by path).

---

## Table map

| Table | Verb | Role | ~keys |
|-------|------|------|-------|
| `PRODUCT_KIT_ENV` | force (spawn env) | Chat/RAILS kit-forward profile | 43 |
| `RENDER_MODE_DEFAULTS` | soft | Mode sketch/record/perform/long_soul/golden/**warp**/camel/dilla | mode-specific |
| `DILLA_BEST_DEFAULTS` | soft | Baseline soulful production knobs | 36 |
| `DILLA_DEEP_DEFAULTS` | soft | Quality gates, pad envelope, retries when deep | 14 |
| `DILLA_STYLE_DEFAULTS` | fill/force | Canonical **dilla** kit-forward DNA | 135 |
| `DILLA_COMFORT_DEFAULTS` | force when comfort | Sofa: one kit, held pads, no vox, −18 LUFS | ~90 |
| `STREAM_EXTRA_DEFAULTS` | soft then force as `STREAM_CREATIVE_MAX` (punch only) | Stream kit/vox/normalize/speak | 81 |
| `STREAM_ITERATE_TUNING` | soft/force | Auto beauty/evolve during stream | 20 |
| `STREAM_SOUL_DEFAULTS` / `STREAM_FAST_DEFAULTS` | soft | Soul vs fast stream tradeoffs | varies |

### `RENDER_MODE=warp` (opt-in)

Turns on already-built knobs: spectral arp/stack, `ARP_IDM_BIAS`, drum chops,
`GROOVE_DNA=cosmogramma`, `PERFORMER=thundercat`, quartal voicing, dub_chamber chain.

### Operator knobs (common)

| ENV | Layer | Role |
|-----|-------|------|
| `RENDER_MODE` | mode/style | `dilla` (default), `comfort`→dilla+comfort, `warp`, `sketch`, …; `camel`→dilla |
| `STREAM_COMFORT` | stream | `1` sofa (stream default); `0` off |
| `STREAM_PUNCH` | stream | `1` force kit-forward creative stream |
| `DILLA_COMFORT` | any | `1` apply comfort on one-shot / product |
| `TRACK` / `STREAM_TRACK` | style/stream | Progression lock |
| `BARS` / `STREAM_BARS` | style/stream | Length |
| `KICKS` / `POCKET_KICKS` | kit | Pocket kicks on |
| `FLYLO_DRUMS_ONLY` | kit | `0` hybrid (default); `1` overlay-only |
| `DRUM_CHOPS` | kit | Demucs one-shots |
| `RAP_VOCAL` | vox | slug or `0` |
| `PAD_VOL` | mix | Pad level (product ~58) |
| `LEAD_ARP` / `HARMONY_LEAD` | lead | Arp layers |
| `SONITEX` / `ANALOG_CHAIN` | master | Character + analog path |
| `MASTER_HEURISTICS` | master | Mix heuristics + loss-gate hooks |
| `STREAM_NORMALIZE` / `STREAM_LUFS` | master | Loudnorm target |
| `SPEAK` | stream | TTS over beat (`0` default product) |
| `ARP_IDM_BIAS` | warp/creative | Euclidean/ratchet/stutter arp styles |
| `DILLA_RAW` | meta | Skip best soft defaults |
| `GROOVE_ENGINE` / `POCKET_DNA` | groove | Pocket humanize (default on) |

Full style list is large (mix bus dB, FlyLo gains, harmonic stem weights, camel locks).
Prefer `config-provenance` after a render over memorizing every key.

---

## One-shot render path (end-to-end)

Example:

```sh
cd MASTER
ruby tools/dilla.rb generate --style dilla --bars 12 --output /tmp/beat.wav
# equivalent engine:
# PRODUCT_KIT_* env + ruby tools/dilla/dilla.rb dilla /tmp/beat.wav --track=get_dis_money ... 12
```

### 1. Wrapper (`tools/dilla.rb`)

1. Parse `--style`, `--bars`, `--output`
2. `product_env` = `PRODUCT_KIT_ENV` + shell overrides for those keys
3. `engine_args` → `dilla.rb dilla <out> --sonitex=… --analog-chain=… --track=get_dis_money [bars]`
4. `system(env, ruby, *args)`

### 2. Engine CLI (`DISPATCH["dilla"]`)

1. Set destination + bars
2. Boot path applies best defaults (unless `DILLA_RAW`) + style for `RENDER_MODE=dilla`
3. `render_dilla(dest, bars)`

### 3. `render_dilla` (core)

```
require ffmpeg · cleanup scratch · pick_render_seed!
ensure_drum_kit!
cfg = dilla_resolve_config  → TRACK, BPM, swing, timing, sonic, chord_bars, feel
cfg = DillaSeeds.apply_to_cfg!(cfg)
DillaRhythm.configure!
composition_session! (arrangement form / performers if COMPOSITION=1)
pick_synth_patches!
pads = dilla_progression(cfg)     # producer_dna + reference YAML profiles
arrange_*_progression             # loop / LA-beat / camel / fugue
beautify_*_pipeline               # DillaHarmony
events = dilla_schedule(...)      # pocket + groove_engine jitter + poly/shaker
kit + optional DRUM_CHOPS
render_sample_bus_wav → drums
optional FlyLo dual-bus merge + peak lift
render_harmonic_wav OR loop stem mids/highs
ffmpeg graph: drums + harm + stems + self_sample + IR + vinyl noise
  → sidechain / sonitex / analog / heuristics
  → loudnorm (STREAM_NORMALIZE)
  → destination (+ demo.wav when streaming)
quality / promote hooks when enabled
```

### 4. Product attach (RAILS)

`Shared::DillaProcessor.render_to_file!` → same wrapper → Active Storage.

### 5. Critique (MASTER, outside engine)

`/dilla metrics` · `/dilla crit` — council reviews mix; do not reimplement inside tools/dilla.

---

## Provenance debugging

```sh
cd MASTER/tools/dilla
# after any render that called soft_fill/force with labels:
SPEAK=0 BARS=4 ruby -e '
  load "dilla.rb"
  apply_best_defaults!
  apply_dilla_style!(force: true)
  force_env!(STREAM_CREATIVE_MAX, label: "STREAM_CREATIVE_MAX")
  print_config_provenance
'
# or CLI after stream/render paths that leave process state:
# ruby dilla.rb config-provenance
```

Note: CLI `config-provenance` alone in a fresh process is empty until a path that records provenance runs in the same process.

---

## Related files

| Path | Role |
|------|------|
| `dilla.rb` | Monolith + DISPATCH + ENV tables |
| `lib/producer_dna.rb` | Chords, timing DNA, harmony profiles |
| `lib/groove_engine.rb` | Pocket, Gaussian jitter, phrase drift |
| `lib/harmony_engine.rb` | Beautify / insight |
| `lib/composition_engine.rb` | Form, performers, session |
| `lib/master_heuristics.rb` | Master FX + loss gates |
| `dilla_reference.yml` | Documented progressions + gate thresholds |
| `../dilla.rb` | Product/chat entry + PRODUCT_KIT_ENV |
