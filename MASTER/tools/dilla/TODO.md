# Dilla Lab — TODO

**Status: Tier A implemented** (2026-07-16). Tier B stubs in `lib/dilla_ml.rb` + `tools/dilla-ml/`.
Tier C (M4L, hardware, installations) remains out of scope by design.

---

## ✅ Shipped

### Harmony (`lib/harmony_engine.rb`)
- [x] DillaHarmony voicing, beautify_pipeline, beauty scoring
- [x] KEY_BORROW + SUBSTITUTIONS wired into enrich / recap
- [x] Turnaround ii–V tags in pipeline
- [x] Pad overlap legato (smooth motion sustain boost)
- [x] Secondary dominants + backdoor inserts
- [x] Reharm every 4th loop (`REHARM_LOOP=1`)
- [x] Mid-register clash fix in schedule
- [x] `ruby dilla.rb beauty` CLI
- [x] Harmony breakdown in `quality` JSON
- [x] 37 semantic profiles + stream rotation

### Groove (`lib/groove_engine.rb`, `lib/groove_score.rb`)
- [x] Per-16th swing jitter (`SWING_JITTER_TICKS`)
- [x] Snare early / hats late / hi-hat micro-delay
- [x] Markov drum steps (`MARKOV_DRUMS=1` default on)
- [x] Kick/snare swap (`KICK_SNARE_SWAP=1`)
- [x] Groove-lock melody off-grid (`GROOVE_LOCK=kick`)
- [x] Trap morph hat density (`TRAP_MORPH=1`)
- [x] Euclidean hats (`EUCLIDEAN_HATS=1`)
- [x] Prime grid (`PRIME_GRID=1`)
- [x] Flam offset (`FLAM=1` default)
- [x] Transient-aware groove score (ghost velocity spread, snare early / hat late bias)
- [x] Role-based drum velocity (`dilla_role_velocity` + `velocity_curve`)
- [x] Dilla sidechain preset (`SIDECHAIN_STYLE=dilla` — fast kick duck)
- [x] Chop-aware drums (`SPECTRAL_ARP=1` thins hats, doubles kicks on chop bars)
- [x] Evolve pocket weighting (`EVOLVE_GROOVE_W=0.22` for Dilla tracks)
- [x] Stream pocket rotation (`stream_evolve_pocket!` — swing/groove DNA nudges)
- [x] Phone-preview gate in stream iterate (`PHONE_PREVIEW_GATE=1`)

### Seeds (`lib/seed_providers.rb`)
- [x] `SEED_TEXT` → swing/BPM/seed
- [x] `DILLA_SEED_URL` JSON provider
- [x] `SEISMIC_SEED=1` / `WEATHER_SEED=1` stubs
- [x] Stream drift sleep (`DRIFT_SLEEP`)

### Rhythm macros (`lib/rhythm_macros.rb`)
- [x] `TEMPO_RAMP=1` / `BPM_STAIRCASE=1` / `TEMPO_ACCEL=1`
- [x] Stripdown + element strip gains
- [x] Subdivision density (`SUB_DENSITY=1`)
- [x] `LONG_STRIPDOWN=1` flag

### Master (`lib/master_heuristics.rb`) — opt-in `MASTER_HEURISTICS=1`
- [x] Harshness notch, perceptual limiter, cassette wow
- [x] Radio/club morph (`RADIO_CLUB_MORPH=1`)
- [x] Club IR slot (`samples/irs/club.wav`)
- [x] `ruby dilla.rb phone-preview`
- [x] Sub/kick balance + harshness in quality JSON

### Spectral (`lib/spectral_engine.rb`)
- [x] Spectral arpeggiator chops (`SPECTRAL_ARP=1`)
- [x] Harmonic stack (`HARMONIC_STACK=1`)
- [x] Industrial darkness chain (`INDUSTRIAL_DARK=1`)
- [x] Breath percussion (`BREATH_PERC=1`)
- [x] Groove-synced vinyl via `DillaMl`

### ML stubs (`lib/dilla_ml.rb`, `tools/dilla-ml/`)
- [x] Groove vinyl, sub predictor, mood cluster heuristics
- [x] DDSP/RAVE stub notes (`DILLA_ML=1`)

### Composition
- [x] `EVOLVE_HARMONY_W` tuning
- [x] Counter-melody offset via groove lock + conversation
- [x] Arp on lead layer only — `PAD_ARP_MODE` presets drive `lead_arp.wav`; EP/warm pads held

---

## 🎛️ Tier C — not in engine (by design)

Max for Live, EEG/VR, hybrid analog hardware, installation art, real-time DDSP —
see original brainstorm; steal semantics via seeds/tension only.

---

## 🚀 Commands

```sh
cd MASTER/tools/dilla

TRACK=minor_iv_loop ruby dilla.rb dilla out.wav 16
ruby dilla.rb beauty out.wav
MASTER_HEURISTICS=1 ruby dilla.rb dilla out.wav 16
SEED_TEXT="soul jazz" MARKOV_DRUMS=1 ruby dilla.rb dilla out.wav 8
ruby dilla.rb phone-preview out.wav
SPECTRAL_ARP=1 TRACK=glasper_quartal ruby dilla.rb dilla out.wav 8
```

### Key ENV flags

| ENV | Effect |
|-----|--------|
| `SOUL_ENRICH=1` | Passing clusters on soul profiles |
| `REHARM_LOOP=1` | Tritone/alt reharm every 4th bar |
| `TEMPO_RAMP=1` | +1 BPM per 4 bars |
| `PRIME_GRID=1` | Prime polyrhythm hat layer |
| `MASTER_HEURISTICS=1` | Harshness/cassette/club morph on master |
| `INDUSTRIAL_DARK=1` | Darkness saturation chain |
| `DILLA_SEED_URL` | External JSON seed provider |

---

## 📎 Modules

| File | Role |
|------|------|
| `lib/harmony_engine.rb` | Voicing, beautify, beauty score |
| `lib/groove_engine.rb` | Pocket, Markov, jitter |
| `lib/seed_providers.rb` | Text/API/seismic/weather seeds |
| `lib/rhythm_macros.rb` | Tempo ramps, stripdown |
| `lib/master_heuristics.rb` | Master assistant (opt-in) |
| `lib/spectral_engine.rb` | Spectral chop modes |
| `lib/dilla_ml.rb` | ML heuristic stubs |
| `lib/producer_dna.rb` | Profiles, drums |
| `lib/composition_engine.rb` | Critique, evolution |
| `dilla.rb` | Render pipeline |

*Last updated: 2026-07-16 — full Tier A implementation*