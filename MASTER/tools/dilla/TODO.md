# Dilla Lab — TODO

Roadmap for the greatest solutions: what ships today, what to build next in Ruby,
and how the 250+ avant-garde brainstorm maps to this codebase.

**Stack reality:** `dilla.rb` is pure Ruby + ffmpeg synthesis. No Max for Live, no
GPU training loop, no real-time DDSP yet. Ideas are triaged by fit, not hype.

---

## ✅ Shipped (greatest solutions already in tree)

### Harmony & composition
- [x] `DillaHarmony` engine — voicing, validation, voice leading, beauty scoring
- [x] `beautify_pipeline` wired into `render_dilla`
- [x] 37 semantic harmony profiles (no song-title coupling)
- [x] Slash chord parsing (`Dm7/F`, `Cmaj9/E`)
- [x] Soul-profile gating (blocks polytonal / negative / neapolitan / chromatic mediant)
- [x] Breakdown 2-voice strip, chord-tone-only chops, lower chop density on soul tracks
- [x] `Critique` + `Evolution` use real `score_beauty` (not placeholder 72)
- [x] Stream rotation across all curated profiles

### Groove & drums
- [x] RG-69 MPC grids, swing, humanize ticks per drum preset
- [x] DFAM 8-step FM percussion bus (`DFAM=0` to disable)
- [x] Dilla / FlyLo / Madlib timing families
- [x] Polyrhythm ghost layer (3-against-4)
- [x] Per-section arrangement (intro / main / breakdown / build / outro)
- [x] Fugue structure for non-curated progressions (exposition / development / recap)

### Sonic
- [x] Lo-fi overlay (bit crush, vinyl, pad lowpass, attack/release)
- [x] Sonitex + analog chain integration
- [x] Stem rack, demux, quality report with LUFS + spectral bands
- [x] Composition session persistence (`project/session.json`)

---

## 🔥 Tier A — Build next in `dilla.rb` (highest ROI)

These are the **greatest remaining solutions**: maximal beauty per line of Ruby,
aligned with soul-jazz / Dilla / lo-fi identity.

### Harmony beauty (finish the overhaul)
- [ ] Wire `KEY_BORROW` + `SUBSTITUTIONS` into `enrich_progression` / profile selection
- [ ] Call `add_turnaround_tags` at end of `beautify_pipeline` for soul profiles
- [ ] Pad overlap / legato: extend sustain when root motion ≤ 2 semitones
- [ ] Secondary dominants + backdoor inserts on bar 7–8 of 8-bar loops
- [ ] `SOUL_ENRICH=1` flag documented in help (passing clusters on soul tracks)
- [ ] Per-profile voicing override in `producer_dna` (already partial — audit all 37)
- [ ] Modal interchange pool from `KEY_BORROW` keyed by profile `:key`
- [ ] Chord substitution roulette: weighted `SUBSTITUTIONS` on recap bars only
- [ ] Mid-register clash auto-fix in schedule (not just pipeline)
- [ ] Beauty breakdown in `quality` JSON (`extension`, `motion`, `clash` subscores)
- [ ] `ruby dilla.rb harmony` command prints score + recommendations for last render

### Groove engineering (hip-hop ideas #81–100, portable subset)
- [ ] Per-16th-note swing jitter envelope (idea #81) — bounded ±3 MPC ticks
- [ ] Snare slightly early + hats slightly late template (idea #83)
- [ ] Hi-hat 1–2 ms random micro-delay per hit (idea #94) — extend `humanize_ms`
- [ ] Markov chain drum generator trained on `DRUM_PATTERN_SETS` (ideas #26, #87)
- [ ] Kick quantized / melody off-grid mode (idea #92) — `GROOVE_LOCK=kick`
- [ ] Boom-bap → trap morph over N bars (idea #90) — evolve `DRUM_PRESETS` density
- [ ] Tempo ramp +1 BPM / 4 bars (idea #96) — `TEMPO_RAMP=1`
- [ ] Text → sequence: `SEED_TEXT` maps ASCII to chord roots or drum density (ideas #29, #34)
- [ ] Breath / transient-as-percussion mode using existing sample chop path (ideas #93, #99)

### Algorithmic composition (live-coding ideas #21–40, Ruby-native)
- [ ] External seed providers: `DILLA_SEED_URL` → JSON (weather humidity → swing, idea #24)
- [ ] USGS earthquake → velocity map (idea #21) — optional `seismic_seed.rb`
- [ ] Prime polyrhythm tracks: 3/5/7/11 step cycles (ideas #36, #225)
- [ ] Euclidean hat generator per bar (idea #22 analogue)
- [ ] Counter-melody responder on pad events (idea #37) — extend `lead_events_creative`
- [ ] 20-minute element stripdown render mode (idea #38) — macro arrangement curve
- [ ] Spectral-similarity sample chop reorder (idea #31) — ffmpeg `astats` + Ruby sort
- [ ] Hi-hat acceleration to tone (idea #33) — density → filter sweep over 16 bars
- [ ] Drift coding: `sleep` jitter in stream loop (idea #28)

### Mix / master heuristics (ideas #101–120, no ML first)
- [ ] Phone-speaker preview chain: band-limit + mono collapse preset (idea #101)
- [ ] Harshness detector: spectral flux above 3.5 kHz → auto notch (idea #114)
- [ ] Club IR EQ curve slot (idea #108) — load IR from `samples/irs/`
- [ ] Radio ↔ club master morph within track (idea #113) — section-based LUFS targets
- [ ] Perceptual limiter: limit 2–5 kHz band harder (idea #107)
- [ ] Virtual cassette print pass (idea #118) — wow/flutter LFO on mix bus
- [ ] Sub/kick balance heuristic from beauty score + spectrum (ideas #15, #117)
- [ ] Dynamic vocal carve placeholder when stem present (idea #119)

### Spectral & industrial (ideas #61–80, #241–255, subset)
- [ ] IR-from-transient: use spike sample as convolution impulse on kick (idea #61)
- [ ] Layered door-slam kick builder from sample dir (idea #65)
- [ ] Bitcrush sine → saw lead for `industrial` mode (idea #68)
- [ ] Granular wash machine drone layer (idea #71) — ffmpeg `atempo` + overlap
- [ ] Spectral freeze chop: long pad from cymbal attack (idea #250)
- [ ] Phase-vocoder stretch mode for chop source (idea #249) — ffmpeg `rubberband`
- [ ] Spectral arpeggiator: cycle FFT bands of held chord (idea #253)
- [ ] Darkness loop: iterative saturate until HF RMS threshold (idea #12) — `INDUSTRIAL_DARK=1`
- [ ] Single-fundamental harmonic stack mode (idea #242)

### Micro & macro rhythm (ideas #221–240)
- [ ] Subdivision density without BPM change (idea #221)
- [ ] Macro chord change at 50% duration (idea #223)
- [ ] Kick/snare swap with same pocket (idea #237)
- [ ] Per-bar BPM staircase 60→180 (idea #238)
- [ ] One-instrument removed every 10s (idea #239) — arrangement automation
- [ ] Gap-implied rhythm: schedule silence envelopes (ideas #228, #240)
- [ ] Flam offset: snare +1 ms after kick (idea #232)
- [ ] Prime-duration bars (idea #234)

---

## 🧪 Tier B — Sidecar services (Python / optional ML)

Worth doing **adjacent** to dilla, not inside the hot render path.

| Idea # | Concept | Sidecar | Notes |
|--------|---------|---------|-------|
| 1–4, 17–19 | DDSP / vibe-loss EQ / timbre morph | `tools/dilla-ml/ddsp/` | Export stems → optimize → re-import |
| 5, 209 | RAVE latent DJ / snare arithmetic | `rave_latent.rb` wrapper | Pre-compute embeddings offline |
| 13 | DDSP stem regen | demucs + ddsp | Replace masked bins |
| 14 | Groove-synced vinyl GAN | train offline, inference WAV | Or heuristic: vinyl level ∝ ghost density |
| 15, 117 | Sub/bass ML predictor | sklearn on features | Start with rule-based Tier A |
| 31 | Spectral chop rearrange | Python + librosa | ffmpeg-only fallback in Tier A |
| 32, 97 | Infinite lo-fi stream | stream loop + evolution | **`stream` already close** |
| 39 | WhoSampled chain recreate | scraper | Legal/fragile — manual sample map better |
| 39 | WhoSampled | — | Skip automation; use `samples/manifest.json` |
| 102–105 | Differentiable mix console | PyTorch offline | Export `quality` targets |
| 111, 120 | Tape warmth / 1974 style transfer | audio style transfer model | A/B on master only |
| 201–208 | LLM / diffusion / city-GAN pads | separate `generate_pad.wav` | Feed as `SAMPLE_DIR` |
| 211 | De-reverb | demucs-style | Post `separate` |
| 213 | Mood-cluster sample picker | cluster tags in manifest | Ruby k-means on RMS/centroid |
| 214–216 | Voice-as-oscillator / AI harmony | heavy ML | Not core Dilla identity |
| 246 | Spectrogram draw → audio | Python | Fun demo track |

**Verdict:** ~60 ideas from the 250 list are **Tier B**. Build Tier A first; add
`dilla-ml/` only when a heuristic plateaus.

---

## 🎛️ Tier C — Different products (do not cram into `dilla.rb`)

Max for Live, hardware, installations, and performance art belong elsewhere.

| Category | Ideas | Why separate |
|----------|-------|--------------|
| Max for Live (#41–60, #76, #94) | Webcam distortion, Game of Life seq, accelerometer tape-stop | Ableton runtime |
| Unconventional UI (#121–140) | EEG, eye tracking, fruit MIDI, lie-detector master | Hardware + safety |
| Hybrid analog (#141–160) | Tape loops, robotic gong, pendulum clock | Physical I/O |
| Extreme sampling art (#161–180) | Glacier 24h, bullet impacts, heart flatline drone | Installation / field |
| Theoretical music (#181–200) | DNA songs, 100-year stretch, delete-on-play | Concept pieces |
| Full neural live (#204–210, #220) | Real-time style transfer, dancer MIDI | GPU + latency budget |

**Verdict:** ~90 ideas are **inspiring references**, not engine features. Steal the
*semantics* (e.g. #54 melancholic random walk → `tension_curve`; #60 flight paths
→ `DILLA_SEED_URL`).

---

## 📋 Harmony beauty checklist (original ~85 ideas — status)

| Area | Done | Next |
|------|------|------|
| Voicing styles (spread, drop2, quartal, rootless, so_what, kenny, bill, cluster) | ✅ | Profile defaults audit |
| Register clamp MIDI 50–76 | ✅ | — |
| Max 4 pad voices | ✅ | — |
| Voice leading (greedy PC distance) | ✅ | Bass contrary motion rules |
| Passing clusters (dev only, gated on soul) | ✅ | `SOUL_ENRICH` |
| Pedal probability (soul = 0) | ✅ | — |
| Turnaround ii–V tags | coded | Wire into pipeline |
| KEY_BORROW / SUBSTITUTIONS tables | coded | Wire into enrich |
| Beauty score + critique | ✅ | Expose in CLI |
| Block ugly generators on soul | ✅ | — |
| Chop density / chord-tone chops | ✅ | — |
| Breakdown 2-voice strip | ✅ | — |
| Pad sustain / late entry | ✅ | Overlap on smooth motion |
| Secondary dominants / backdoor | — | Tier A |
| Neo-Riemannian / Coltrane cycle | partial | `coltrane` generator exists |
| Slash / planing / modal interchange | partial | Profile chords + generators |
| Reharm every 4th loop | — | Tier A |
| Tritone sub on V | — | Tier A |
| Sus → maj resolution | — | Tier A |
| Pedal + slash combo | — | Tier A |
| Quartal on IV chords | partial | `glasper_quartal` profile |
| Cluster only on passings | ✅ | — |
| FlyLo sidechain on pad | ✅ | `quartal_west_coast` |
| Stereo pan pads by voice | partial | Widen soul profiles |
| Evolution weights harmony | ✅ | Tune weight via `EVOLVE_HARMONY_W` |

---

## 🗺️ Assessment: adding the full 250+ brainstorm

### Summary scorecard

| Tier | Count (approx) | Action |
|------|----------------|--------|
| **A — Ruby in dilla.rb** | ~55 | **Add to sprint backlog above** |
| **B — ML sidecar** | ~60 | `tools/dilla-ml/` when needed |
| **C — Other products** | ~90 | Inspiration only |
| **Already shipped / overlap** | ~45 | Mark done; don't re-build |

### Strongest synergies with current engine

1. **#26 + #81 + #94 + existing humanize** → best-in-class pocket engine
2. **#14 + lo-fi vinyl** → groove-modulated noise floor (no GAN required day 1)
3. **#31 + chop scheduler** → intelligent sample collage mode
4. **#36 + #225 + polyrhythm layer** → generative prime-grid compositions
5. **#38 + #239 + fugue arranger** → long-form evolution performances
6. **#108 + #114 + `quality`** → mastering assistant without neural nets
7. **#253 + pad/chop** → spectral arpeggiator is a natural extension of `chop_hz`
8. **#24 + #236 + `pick_render_seed!`** → external API seeds for infinite stream
9. **#12 + `industrial`** → darkness-seeking saturation loop
10. **Harmony Tier A + ideas #126, #54** → gesture/mood-driven progression (future)

### Weakest fit (defer or reject)

- Anything requiring **Ableton / M4L runtime** (#41–60)
- **BCIs, lie detectors, EEG** (#121, #140, #181) — liability + hardware
- **100-year / 29.5-day / delete-on-play** (#183, #198, #231) — art, not tooling
- **Real-time DDSP inference** (#1–4, #18) — latency + GPU; offline first
- **WhoSampled automation** (#39) — legal fragility
- **π/4 time** (#233) — meme meter; use odd-bar drop (#16-bar drop beat) instead

### Recommended sprint order (next 4 weeks)

1. **Week 1:** Finish harmony wiring (KEY_BORROW, turnarounds, CLI `harmony` score)
2. **Week 2:** Groove depth (Markov drums, snare-early/hats-late, micro-delay)
3. **Week 3:** External seeds + prime polyrhythms + tempo ramp
4. **Week 4:** Master heuristics (harshness, club IR, radio/club morph) + spectral chop

---

## 🚀 Quick commands (reference)

```sh
cd MASTER/tools/dilla

# Soul profile render
TRACK=minor_iv_loop ruby dilla.rb dilla out.wav 16

# Stream rotation
DILLA_FORCE_TERMINAL=1 ruby dilla.rb stream 16

# Evolution with harmony scoring
COMPOSITION=1 ruby dilla.rb evolve 16 5

# Critique last render
COMPOSITION=1 ruby dilla.rb critique

# DFAM preview
ruby dilla.rb dfam 4
```

---

## 📎 Related files

| File | Role |
|------|------|
| `lib/harmony_engine.rb` | Voicing, beautify, beauty score |
| `lib/producer_dna.rb` | Profiles, chords, drums, stream list |
| `lib/composition_engine.rb` | Critique, evolution, arrangement |
| `lib/dfam_engine.rb` | FM percussion bus |
| `dilla.rb` | Render pipeline, schedule, mix |
| `project/session.json` | Composition persistence |

---

*Last updated: 2026-07-16 — post `DillaHarmony` integration (commit `6bb95735d`)*