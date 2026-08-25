# Dilla

A beat engine in Ruby. One file, `dilla.rb`, with helpers under `lib/`. It
generates harmony, programs drums, plays sampled loops against them, mixes,
masters, and writes an mp3 or wav. Everything runs locally through `ffmpeg` and
`fluidsynth` — nothing is uploaded and nothing is fetched at render time.

Tests: `cd STUDIO && rake test:dilla` (or bare `rake` for the gate and every
suite). The line here named `MASTER/test/test_dilla.rb`, which has not existed
since the suite moved to `STUDIO/test/dilla/` — so it sent an operator to
validate nothing and read the result as passing.

ENV knobs and the render path in detail: `ENV_AND_RENDER.md`. Operator scripts,
including `redo_nine.sh`, live under `scripts/`.

```sh
cd STUDIO/dilla
ruby dilla.rb out.wav 18                 # one render, 18 bars
TRACK=kembara_rindu ruby dilla.rb out.wav 18
ruby dilla.rb                            # showcase_demo! → demo.wav
ruby dilla.rb stream                     # continuous stream
ruby dilla.rb help
```

---

## What happens during a render

```
progression  ──►  theory refine  ──►  pads · bass · leads ──┐
                                                            │
sampled loop ──►  varispeed · chop · vary · EQ ─────────────┤
                                                            ├──►  bus analog
drum grid    ──►  microtiming · swing · dirt · duck ────────┘      (saturation
                                                                    per channel)
                                                                        │
        sonitex tape ──► analog chain ──► loudnorm ──► tape hysteresis
                                       ──► tilt ──► dropout ──► mono bass
```

Four things are worth knowing about that order.

**Per-channel saturation happens before summing.** A desk saturates every
channel on the way in, so each source makes its own harmonics and those
harmonics then intermodulate in the bus. A single saturator on the master can
never do that, because by the time it runs the sources no longer exist
separately. `BUS_ANALOG` drives each bus into a limiter and takes the level back
out, hardest on drums, lightest on bass.

**Tape hysteresis runs on the finished master**, because it is per-sample DSP in
Ruby and is by a wide margin the slowest stage here. It is opt-in and reports
its own cost.

**Swell, tilt, dropout and mono-bass run after loudness normalisation.** Applied
before it, loudnorm simply removes them — a 3 dB musical swell is exactly what a
normaliser exists to flatten.

**The harmonic guard runs before arrangement**, so if it mutes the tonal layers
nothing downstream has to be unpicked.

---

## Samples

`TRACK_SAMPLE_LOOPS` holds the loops. Each carries its own tempo and its own
low-end and top-end correction, because the loops differ and one global value is
wrong for whichever loop it was not tuned against.

| track | source | tempo | key (fit) | hp / shelf / lp |
|---|---|---|---|---|
| `kembara_rindu` | 4-bar Ableton loop | 92 | C minor (0.71) | 90 / −7 / 5600 |
| `semua_untuk_mu` | 0:36–0:46 of the source | 96 | G minor (0.836) | 45 / 0 / 5200 |
| `lo_borges` | first 4 bars | 114 | D major (0.697) | 60 / −3 / 6000 |
| `rauingar` | own recording, 2 bars | 92 | C♯ minor (0.70) | 60 / −3 / 6200 |

Older ingest names (`four_seven`, `nightbus`, `dmaj_open`) still resolve through
`TRACK_SAMPLE_LOOP_ALIASES`, including for layer-profile lookup.

### Restoring a loop

`samples/` and `crate/` are gitignored, so a lost checkout loses the audio and
keeps every decision made about it. Drop the file back at the path the table's
track name gives and nothing else is needed — `demo_sampled_order` reads the
disk, so a restored loop rejoins the demo on the next run:

| track | file |
|---|---|
| `kembara_rindu` | `samples/kembara_rindu/loop.wav` |
| `semua_untuk_mu` | `samples/semua_untuk_mu/loop.wav` |
| `lo_borges` | `samples/lo_borges/loop.wav` |
| `rauingar` | `samples/rauingar/loop.wav` |
| `arat_swost_wolet` | `samples/arat_swost_wolet/loop.wav` |

`crate/` is what makes a restore cheap, and it is worth keeping whole. For
`semua_untuk_mu` it holds `sources/` (the fetched `source.wav` plus a `fetch.txt`
naming the artist, duration and URL), `stems/` (a six-stem `htdemucs_6s` pass over
the whole record and a second pass over the sampled window), and `loops/` (the
cut itself and its variants). Restoring from that is a copy, with no re-fetch and
no re-separation — and `fetch.txt`'s duration is what proves the source is the
same upload the cut was measured against, which a fresh search cannot promise.

Verify a restore by rendering it: the loop should report the tempo and key this
table gives. `semua_untuk_mu` reads Eb major at fit 0.82 against the 0.79 in
`sample_loops.rb`, and 96 BPM, which is close enough to identify the passage and
not close enough to be a coincidence.

### Finding a loop's boundaries is a manual job

Onset and energy detection finds where something *changes*, which is not where a
musical phrase *starts*. It put `semua_untuk_mu` 22 seconds early, on the end of
a spoken intro. Given a boundary the analysis is reliable and will confirm or
refute it — key fit 0.27 for the detector's cut against 0.836 for the operator's.
Asked to find one, it is not.

Where two analyses disagree on tempo, loop the candidates and measure the seam:
a correct length rejoins itself quietly. On `lo_borges`, 8.421s (114 BPM)
rejoins at −1.1 dB and 8.000s (120) at −8.6 dB. That settled a disagreement
between the onset sweep and a self-similarity peak — self-similarity finds the
shortest thing that repeats, which is not necessarily the bar.

### `chop` — a long recording into a rack of beds

    ruby dilla.rb chop [path]     # default samples/ubrukte_samples.mp3
    ruby dilla.rb chop list

Scan the whole recording, propose windows that are loud, steady and carrying
more energy outside the speech band than inside it, run **demucs `htdemucs_6s`**
over those windows, keep `bass + guitar + piano + other` and drop `drums` and
`vocals`, then find each loop's length and cut it. Results land in
`samples/chopped/<slug>/loop.wav` with a row in `samples/chopped/loops.json`,
and `TRACK_SAMPLE_LOOPS` merges that registry over the hand-cut literal — a
chopped loop is `TRACK=<slug>`-selectable like any other. `CHOP_BED=1` lets the
engine pick one for any track that has no bed of its own, matched to the
`KEY_LOCK` tonic. Off by default: switching a bed on under every track in the
rotation changes the whole catalogue.

Knobs: `CHOP_CANDIDATES` (16), `CHOP_KEEP` (8), `CHOP_SPAN` (30s),
`CHOP_FRESH=1` to discard cached separation. Separation is keyed by source
window, so re-running to re-tune the scoring reuses it.

**This does not overturn the section above.** Picking the *window* is still the
weak step and its output is a proposal — the section above is why the scan
proposes sixteen and keeps eight rather than trusting one. What *is* now
automatic is the part that was always measurable: the **length**. Correlating a
candidate length against the material that follows it recovers all four hand-cut
loops when each is looped three times (10.43 → 10.44, 10.00 → 10.00, 5.22 →
5.22, 8.42 → 8.42), including the ×2 correction `kembara_rindu` needs for
exactly the reason stated above.

Tempo then follows from length rather than the other way round — `bpm = 240 ×
bars ÷ seconds` returns all four declared tempos exactly (92, 96, 92, 114).
That direction matters: onset-based tempo detection has nothing to work with on
a sustained passage, and `RadioBergenStudy::DeepAudio.estimate_bpm` reports the
median onset gap, which on this broadcast returned 66.7 BPM for four unrelated
passages — 66.7 being 18 frames of 0.05s, not a tempo. When no bar count puts a
length in 70–140 BPM the row carries `bpm 0`, which the loop filter already
reads as "play at native speed".

Off-air radio is **not licensed material**, and chopping it does not clear it.
Every row carries `rights: unlicensed`, so a beat built on one can be identified
before release rather than after. `lib/crate_dig.rb` is the route that clears.

---

## Drums

~60 presets in `lib/producer_dna.rb`, in categories that are deliberately
kept apart. Being able to say which a grid is matters more than having more.

| category | examples | what it means |
|---|---|---|
| transcribed | `four_seven`, `transcribed_soul_nine` | measured off a recording |
| constructed | `dilla_donuts`, `flylo_zodiac`, `boom_bap`, `soul_shuffle` | built to a described feel |
| pack import | `pack_729_1..6` | extracted from licensed MIDI |
| push pads | `push_four`, `push_sparse` | straight and sparse on purpose |
| expansion | `afro_clave`, `euclid_five`, `ghost_cloud`, … | more pockets, same backbeat rule |

Export every grid as GM MIDI clips: `ruby dilla.rb export-midi` → `samples/midi/`.
Re-import a pack folder: `ruby dilla.rb import-midi samples/midi/boom_bap`.

**The backbeat stays on 4 and 12.** Every transcription in the file says so.
What makes these records sound the way they do is `MICROTIMING_MS` — snare
10–28 ms early, hats 12–32 ms late, kick near the grid — measured in
milliseconds, not in 16ths. Moving the backbeat does not produce a drunk
hip-hop beat, it produces a beat that is not hip-hop. Snare on 8 is the one
legitimate exception: that is the backbeat when the bar is felt half-time.

**Swing is 53–56%, on eighth notes.** The off-kilter quality comes from
`NO_QUANTIZE=1` and per-voice lean, not from a large swing number. A forum
claim of "about 70%" sent this the wrong way once; better sources are specific
and lower.

**`SWING_ROLE_SCALE` leans each voice differently** — kick at 0, locked to the
grid, everything else against it, percussion furthest back. At SWING=54 and 82
BPM: kick 0.0, snare +12.4, hat +16.1, ghost +17.6, perc +21.2 ms. Take the
locked kick away and it stops reading as feel and starts reading as unsteady
tempo.

---

## Switches

Sample handling:

| switch | what |
|---|---|
| `HARMONIC_KEEP=1` | transpose generated pads onto the loop's detected key |
| `HARMONIC_SHUFFLE=1` | order chords so the top voice traces one arc |
| `ORGANIC_VARY=1` | rebuild the bed as N differing passes — `-stream_loop` is bit-identical, and nothing acoustic is |
| `LOOP_CHOP_SLICES=8` | cut each pass into slices and rotate them; the loop becomes material rather than a part |
| `SAMPLE_LOOP_VARISPEED` | pitch follows tempo, as a record does (default on) |
| `SAMPLE_LOOP_SEMITONES` | pitch **without** changing tempo |
| `SAMPLE_FM=1` | audio-rate vibrato = real FM sidebands, floored at 700 Hz so chord tones are untouched |
| `SAMPLE_SCALE=1` | layer the loop at degrees of its own key |
| `LOOP_WOW_CENTS` | tape instability on the loop only, never the kit |
| `LOOP_DELAY_BEATS` | tempo-synced echo (1.5 = dotted-8th) |

Two loops as one instrument — `DILLA_XSAMPLE` names the partner:

| switch | what |
|---|---|
| `DILLA_XCONVOLVE=1` | one loop becomes the room the other plays in |
| `DILLA_XGATE=1` | one loop's harmony driven by the other's rhythm (`amultiply`, not a gate) |

Drums:

| switch | what |
|---|---|
| `DRUM_PRESET` | any drum preset key (`ruby -e` / `DRUM_PRESET=boom_bap`) |
| `NO_QUANTIZE=1` | quantise off entirely |
| `SWING_ROLE_SPREAD` | how far the per-voice lean spreads |
| `FLYLO_DRUM_OVERLAY=1` | Camel dual-bus: sub at 55/110/180, top at 3.5k/6.5k/9k |
| `FLYLO_TOP_DIRT` | phaser/flanger/crush on cymbals, kick untouched |
| `FLYLO_HAT_DUCK` | duck the top bus by the kick bus |
| `DRUM_FIELD_LAYER` | room tone under the kit, ducked by it |

Movement and master. The analog stages are **on by default** as of 2026-07-31 —
every one of them shipped built and set to `0`, so nothing this engine rendered
had ever been through them. Set a switch to `0` to get the old behaviour back.

| switch | default | what |
|---|---|---|
| `BUS_ANALOG` | `0.3` | per-channel saturation plus small phase offsets, so buses don't sum coherently |
| `CONSOLE_STRIP` | `0.35` | per-channel desk model; L and R run one seed apart, which is the point |
| `TAPE_HYSTERESIS` | `0.25` | Jiles-Atherton, RK4 — path-dependent, unlike every other stage |
| `TAPE_BIAS` | `1.0` | 1 = original loop; lower = less bias, wider hysteresis (ChowTape) |
| `TAPE_LOSS_HZ` | `0` | spacing/loss lowpass into JA; 0 is off, 14000 is the analog start |
| `TAPE_WOW_MS` | `0.6` | Ornstein-Uhlenbeck flutter |
| `SONITEX_MIX` / `_DISTORTION` / `_VINYL` / `_TONE` / `_NOISE` / `_SAMPLING` | `1` | STX-1260 section wet amount; `SONITEX_SAMPLING=0` is crush off, tone stays |
| `MASTER_SMOOTH_DB` | `2.0` | takes 2 dB out of the presence band; the stage that answers "harsh" |
| `SMOOTH_ANALOG` | `1` | drop patches on metallic GM programs (chromatic percussion, 94, 98, 99, 103) |
| `MASTER_TILT_DB` | `0` | negative = darker; lows up as highs come down |
| `MONO_BASS_HZ` | — | sum below N to mono |
| `ORGANIC_BREATH` / `ORGANIC_SWELL` | `0` | correlated loudness+brightness; phrase swell |
| `DILLA_DROPOUT_EVERY` | — | silence just before every Nth downbeat |
| `DILLA_DRONE` / `DILLA_TAPE_STOP` | `0` | stretched bed; platter brake |

Arps and groove:

| switch | default | what |
|---|---|---|
| `NO_ARP` | `1` | held chords and melodic lead phrases; covers **three** separate arp paths |
| `GROOVE_FEEL` | `boom_bap` | `boom_bap` / `dilla_drag` / `camel` — per-voice tick offsets at 96 PPQ |
| `BASS_FEEL` | `1` | let the bass take the feel's offset instead of sitting on the grid |

`NO_ARP` reaches `pad_arp_mode`, `lead_true_arp_mode?` and `lead_events_scale_arp`.
It was added covering only the first, which meant pads went quiet and the leads
kept arpeggiating — and `STREAM_STYLE_SAFE` and `stream_iterate` both set
`LEAD_FORCE_ARP=1` per track, so the forced flag won every time.

Vocals (`RAP_VOCAL=<slug>`, `0` to disable):

| switch | what |
|---|---|
| `RAP_VOCAL_SNAP` | place sung lines on the grid instead of stretching |
| `RAP_VOCAL_LEAN_MS` | drag each line behind the beat, plus a fixed walk |
| `RAP_VOCAL_SWELL` | reverse pre-swell arriving on each line's downbeat |

Snapping exists because a freely-sung take has no tempo to stretch onto. Across
source BPMs 96–128 against a 92 beat, one take landed 31/20/19/18/25/14% of its
onsets on the grid against a ~20% random baseline — slowing it made alignment
*worse*. Placing lines instead took line starts to 87% on grid at a 5 ms median.

---

## Other commands

```sh
ruby dilla.rb crate                    # 38 synthesised one-shots and textures
ruby dilla.rb import-midi <dir>        # MIDI drum clips -> 16-step grids
ruby dilla.rb beauty <file>            # harmony score and recommendations
ruby dilla.rb quality <file>           # LUFS, true peak, harshness, sub/kick
ruby dilla.rb separate <file>          # demucs 4-stem
```

---

## Controls that are not what they look like

Each of these cost real debugging time. They are listed because the failures
were all silent — the code ran, returned success, and did nothing.

- **`DRUM_VOL` is an alias for `DRUM_MIX_WEIGHT` on the main render.** Stream
  iterate and the composition loop used to mutate `DRUM_VOL` and move nothing.
  `resolved_drum_mix_weight` reads a pinned `DRUM_VOL` when `DRUM_MIX_WEIGHT`
  was not pinned. Prefer `DRUM_MIX_WEIGHT` / `DRUM_BUS_VOL` / `DRUM_BUS_GAIN`
  in new recipes.
- **`KICK_GAIN` will not fix a loud low end** if the loop is making it. Muting
  the kick moved the 40–100 Hz band by 0.0 dB; muting the loop moved it 4.0 dB.
  Reach for `SAMPLE_LOOP_HP` first.
- **`asoftclip` needs `oversample`.** Without it the harmonics it makes above
  Nyquist fold back as inharmonic aliasing, which is the "digital" harshness it
  was supposed to remove. With `oversample=4` it measurably saturates — an
  earlier note here said it did not saturate at any threshold, which was
  measured before the oversampling was there.
- **A symmetric transfer function cannot make even harmonics.** `tanh` and
  `atan` are both odd-symmetric, so f(−x) = −f(x) and only odd orders exist. On
  a 220 Hz sine the 2nd harmonic came back at −131 dB — the numerical floor —
  against a 3rd at −81. That is the Crane Song triode/pentode split: 2nd reads
  as warmth, 3rd as edge, and no amount of tuning a symmetric clipper reaches
  the first. A DC bias into the non-linearity (then high-passed off) flips it
  even-dominant. Adjusting the threshold was never going to work.
- **Level staged before a clipper is not loudness, it is distortion.** The
  master chain had 15.6 dB of cumulative makeup gain ending in +6.4 dB into a
  limiter set 0.7 dB from full scale. It measured "clean" on flat factor and
  still sounded overdriven, because flat factor only catches flat-topping.
  Total harmonic distortion was the measurement that showed it: 0.166%, down to
  0.057% once the gain came out.
- **`equalizer` is a peaking filter, always.** Its `t` parameter sets the *unit*
  of the width, not the shape. Shelves are `bass` and `treble`.
- **Track profiles beat the command line** unless pinned; `USER_PINNED_ENV` is
  what lets a caller win.
- **`RAP_VOCAL=0` must be explicit** — `DILLA_STYLE_DEFAULTS` soft-fills it.
- **Measure with `STREAM_NORMALIZE=0`.** With normalisation on, removing a layer
  makes the rest *louder* and the measurement describes the normaliser.
- **Concat lists need absolute paths.** The demuxer resolves relative entries
  against the list file's directory, so a relative output path silently produced
  no effect at all.
- **`GROOVE_FEEL` defaults to `boom_bap`.** The Dilla microtiming this engine is
  named for is off unless asked. `dilla_drag` puts the snare behind while the
  hats hold the grid; `camel` drags further and pulls the hats early. Every
  render that never set it got straight-ahead timing.
- **The fugue arranger is gated on the track's *name*.** `arrange_fugue_progression`
  builds exposition / development / recapitulation, and `theory_runtime` only
  reaches for it when `TRACK` matches `/bach|baroque|circle|fugue/i`. Of the
  whole catalogue only `circle_fifths_descent` does, so asking for "a fugue
  concept" on any other track silently gets none.
- **Presence is boosted twice and cut once.** `HARM_PRESENCE_DB` (+1.6) and
  `DRUM_PRESENCE_DB` (+1.5) both push the same region that `MASTER_SMOOTH_DB`
  takes 2 dB out of at 3.2 kHz. Net is still a boost into the band
  `master_smooth!` itself calls "where distortion and harshness actually live".
  The de-harsher is no longer switched off, but it is outnumbered.
- **`analyze_harshness` is a three-band meter.** Presence (2–4 kHz) minus body
  (180 Hz–2 kHz). The old two-band split at 3.5 kHz put the roughness people
  complain about inside `mid`, where it cancelled — a render measured −24.5
  (very un-harsh) while sounding rough. `low`/`mid`/`high` stay at their
  historical edges so `sub_kick_balance` and old sidecars keep the same
  numbers. Callers that still pass only mid/high get the old ratio.
- **Sonitex sections are independently wet.** `SONITEX_SAMPLING=0` turns the
  crush off without touching vinyl tone. Amount 1 (the default) is the preset
  unchanged. The six names are MIX, DISTORTION, VINYL, TONE, NOISE, SAMPLING.
- **One console strip is not a console.** `console_strip.rb`'s own header argues
  that the sound people mean by "console" is the sum of thirty slightly
  different channels, and then runs one pass. NastyVCS gets its character from
  transformer circuitry at *both* input and output plus a phase-alignment stage
  used for colouring — which is why several instances in series sound like
  something one instance does not.

  There is an instance count now: `RACK=summed` with `CONSOLE_STACK=1..4`, and it
  is a *warmth* control rather than a drive one, which is the opposite of what a
  number that high usually means. Matched to the same 1.5% THD, one hard stage
  puts the 3rd harmonic at −51.9 dB and three gentle ones at −74.7 — same amount
  of distortion, 23 dB less of it odd. The 2nd holds steady because the THD match
  pins it there. Even harmonics are octaves and read as tone; the 3rd is a
  twelfth and is what "harsh" means on a mix bus. Each depth carries a measured
  makeup, because `asoftclip`'s `oversample=4` is not gain-compensated in ffmpeg
  8.1.1 and an uncalibrated stack measured 10 dB down at four instances.
- **`donuts_warm` decides whether a kit entry is audible as one.** The default
  preset stacks `hf_rolloff: 7000`, `groove_wear_lp: 9500` and
  `crush_post_lp: 6000`, so the snare crack and hat shimmer are gone before any
  arrangement happens. Measured across a section boundary where the kit enters,
  the 5–12 kHz band moves **0.0 dB** under `donuts_warm` and **+6.8 dB** under
  `donuts_soul`, against **+9.2 dB** for a real record at the same kind of
  boundary. Whole-file, the two presets differ by −8.0 dB in that band.

  Neither is wrong — `donuts_warm` is the Donuts sound and that is the point of
  it. But on a track whose arrangement depends on the drums arriving, the darker
  preset removes the thing that makes the arrival legible. `dilla ab
  SONITEX=donuts_soul bars=8` measures the swap in one command.

## Five findings that keep recurring

**When you find a bug here, count the other sites before fixing the one in front
of you.** This engine's characteristic failure is a correct diagnosis applied
once. `aecho`'s in_gain scaling the dry signal was written up accurately in the
comment on `fm_bowed_pad` — and 78 of 133 uses still had it. `NO_ARP` was
written against one of three arp paths. Five analog stages shipped built,
documented and set to `0`. `CHOIR_VOX` read as a sparsity control and turned the
choir on in both branches. In each case the author understood the problem; the
fix just didn't travel. So: grep the shape, then fix at a choke point —
`synth_patch` for patch fx, `pick_patch_from_pool` plus `weighted_patch_pick`
for selection — not at the call sites.

*Measured again 2026-08-13.* "`asoftclip` needs `oversample`" is written down
and now applied to every real `asoftclip=type=` filter string, including the
eight inside `render_hate_techno` and `flylo_top_dirt`. A bare `asoftclip`
scan still hits comments that describe the old miss — count filter strings.

Count when grepping, too: a bare `asoftclip` scan returns 28 hits and 18
"without oversample", because prose in the comments is describing the bug. Only
19 are `asoftclip=type=` filter strings on non-comment lines. A finding stated
to one significant figure of wrongness is still a wrong finding.

**A feature can be fully built, correct, documented — and switched off.** Five
analog stages defaulted to `0`: a Jiles-Atherton magnetisation model, an
Ornstein-Uhlenbeck wow generator, a per-channel console strip, per-bus
saturation, and the presence-band de-harsher. Tape character was being asked of
an EQ curve while the tape model sat unused beside it. Grepping for a feature
proves it exists; only its default proves it runs. The same failure produced
three live arpeggiators after arps had been "turned off", and left two patches
named `analog_pad2` and `warm_analog_duo` sitting on GM program 94, *metallic
pad* — one of them weighted 2.0, so it came up twice as often as its neighbours.

**Making room beats adding gain.** Drums that seem absent are usually masked;
most of a 9 dB drum improvement came from lowering other buses, not raising the
drums. A loop with crowded mids cannot be beaten by pushing drums into them.

**A filter can be wired correctly, run without error, and be transparent.** Only
measuring the output catches it, and adjusting parameters never will, because
the parameters were never the problem.

**Sections were unreachable, not missing.** The arrangement cycle was floored at
16 bars while a 16-bar render has a 9-bar body, so breakdown and build never
fired below about 21 bars — every short render was intro, main, outro. The
machinery had been there all along.
