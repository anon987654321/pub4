# Dilla

**A beat engine that never phones home.** `dilla.rb` and the helpers under
`lib/` generate harmony, program drums, play sampled loops against them, mix,
master, and write an mp3 or a wav. Everything runs locally through `ffmpeg` and
`fluidsynth`: nothing is uploaded, and nothing is fetched at render time.

The suite is `STUDIO/test/test_dilla_*.rb`, which is the glob `rake test:dilla`
expands in `STUDIO/Rakefile`; bare `rake` runs the gate and every suite. Check
the path you are given before you trust a green run. This line has been wrong
twice — once naming a file that had not existed for months, once naming a
directory that has never existed — and both times it sent an operator to
validate nothing and read the result as passing.

ENV knobs, the switch reference and the render path in detail are in
`ENV_AND_RENDER.md`. Operator scripts, `redo_nine.sh` among them, live under
`scripts/`.

## What happens during a render

Harmony comes first: a progression is refined by the theory operators and
becomes pads, bass and leads. A sampled loop is varispeeded, chopped, varied and
EQd alongside it. The drum grid gets its microtiming, swing, dirt and ducking.
Those three meet at the analog bus, which saturates each channel separately, and
the sum goes through sonitex tape, the analog chain, loudness normalisation, tape
hysteresis, tilt, dropout and mono bass, in that order. `ENV_AND_RENDER.md` draws
it.

Four things about that order are worth knowing.

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
before it, loudnorm removes them — a 3 dB musical swell is exactly what a
normaliser exists to flatten.

**The harmonic guard runs before arrangement**, so if it mutes the tonal layers
nothing downstream has to be unpicked.

## Samples

`TRACK_SAMPLE_LOOPS` holds the loops. Each carries its own tempo and its own
low-end and top-end correction, because the loops differ and one global value is
wrong for whichever loop it was not tuned against.

`kembara_rindu` is a four-bar Ableton loop at 92 BPM, C minor at fit 0.71,
corrected 90 / −7 / 5600. `semua_untuk_mu` is 0:36–0:46 of its source at 96, G
minor at 0.836, corrected 45 / 0 / 5200. `lo_borges` is the first four bars at
114, D major at 0.697, corrected 60 / −3 / 6000. `rauingar` is an own recording,
two bars at 92, C♯ minor at 0.70, corrected 60 / −3 / 6200.

Older ingest names (`four_seven`, `nightbus`, `dmaj_open`) still resolve through
`TRACK_SAMPLE_LOOP_ALIASES`, including for layer-profile lookup.

### Restoring a loop

`samples/` and `crate/` are gitignored, so a lost checkout loses the audio and
keeps every decision made about it. Drop the file back at
`samples/<track>/loop.wav` and nothing else is needed: `demo_sampled_order` reads
the disk, so a restored loop rejoins the demo on the next run.

`crate/` is what makes a restore cheap, and it is worth keeping whole. For
`semua_untuk_mu` it holds `sources/` (the fetched `source.wav` plus a `fetch.txt`
naming the artist, duration and URL), `stems/` (a six-stem `htdemucs_6s` pass over
the whole record and a second pass over the sampled window), and `loops/` (the
cut itself and its variants). Restoring from that is a copy, with no re-fetch and
no re-separation — and `fetch.txt`'s duration is what proves the source is the
same upload the cut was measured against, which a fresh search cannot promise.

Verify a restore by rendering it: the loop should report the tempo and key
named above. `semua_untuk_mu` reads Eb major at fit 0.82 against the 0.79 in
`sample_loops.rb`, and 96 BPM, which is close enough to identify the passage and
not close enough to be a coincidence.

### Finding a loop's boundaries is a manual job

Onset and energy detection finds where something *changes*, which is not where a
musical phrase *starts*. It put `semua_untuk_mu` 22 seconds early, on the end of
a spoken intro. Given a boundary the analysis is reliable and confirms or refutes
it — key fit 0.27 for the detector's cut against 0.836 for the operator's.
Asked to find one, it is not.

Where two analyses disagree on tempo, loop the candidates and measure the seam:
a correct length rejoins itself quietly. On `lo_borges`, 8.421s (114 BPM)
rejoins at −1.1 dB and 8.000s (120) at −8.6 dB. That settled a disagreement
between the onset sweep and a self-similarity peak — self-similarity finds the
shortest thing that repeats, which is not necessarily the bar.

### `chop` — a long recording into a rack of beds

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

## Drums

~60 presets in `lib/producer_dna.rb`, in categories that are deliberately
kept apart. Being able to say which a grid is matters more than having more.

A transcribed grid — `four_seven`, `transcribed_soul_nine` — was measured off a
recording. A constructed one — `dilla_donuts`, `flylo_zodiac`, `boom_bap`,
`soul_shuffle` — was built to a described feel. `pack_729_1` through `_6` were
extracted from licensed MIDI. `push_four` and `push_sparse` are straight and
sparse on purpose. The expansion set — `afro_clave`, `euclid_five`,
`ghost_cloud` and the rest — adds pockets under the same backbeat rule.

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

## Controls that are not what they look like

Each of these cost real debugging time. They are listed because the failures
were all silent — the code ran, returned success, and did nothing.

- **`DRUM_VOL` is an alias for `DRUM_MIX_WEIGHT` on the main render.** Stream
  iterate and the composition loop used to mutate `DRUM_VOL` and move nothing.
  `resolved_drum_mix_weight` reads a pinned `DRUM_VOL` when `DRUM_MIX_WEIGHT`
  was not pinned. Prefer `DRUM_MIX_WEIGHT` / `DRUM_BUS_VOL` / `DRUM_BUS_GAIN`
  in new recipes.
- **`KICK_GAIN` does not fix a loud low end** the loop is making. Muting
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
- **Sonitex sections are not independently wet.** `SONITEX_MIX`,
  `_DISTORTION`, `_VINYL`, `_TONE`, `_NOISE` and `_SAMPLING` are read by
  nothing: setting any of them changes no sound. `SONITEX` and `SONITEX_PRESET`
  are the two that work. The six were documented before the per-section wet
  controls existed, and the controls never followed.
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
measuring the output catches it, and adjusting parameters never does, because the
parameters were never the problem.

**Sections were unreachable, not missing.** The arrangement cycle was floored at
16 bars while a 16-bar render has a 9-bar body, so breakdown and build never
fired below about 21 bars — every short render was intro, main, outro. The
machinery had been there all along.

## Running it

```sh
cd STUDIO/dilla
ruby dilla.rb out.wav 18                 # one render, 18 bars
TRACK=kembara_rindu ruby dilla.rb out.wav 18
ruby dilla.rb                            # showcase_demo! → demo.wav
ruby dilla.rb stream                     # continuous stream
ruby dilla.rb help

ruby dilla.rb chop [path]                # default samples/ubrukte_samples.mp3
ruby dilla.rb chop list
ruby dilla.rb crate                      # 38 synthesised one-shots and textures
ruby dilla.rb export-midi                # every grid as GM MIDI, to samples/midi/
ruby dilla.rb import-midi <dir>          # MIDI drum clips back into 16-step grids
ruby dilla.rb beauty <file>              # harmony score and recommendations
ruby dilla.rb quality <file>             # LUFS, true peak, harshness, sub/kick
ruby dilla.rb separate <file>            # demucs 4-stem
```
