# Dilla

**A beat engine that never phones home.** `dilla.rb` and the helpers under
`lib/` generate harmony, program drums, play sampled loops against them, mix,
master, and write an mp3 or a wav. Every instrument is synthesised by the engine
and shaped through `ffmpeg`; the records it samples and the rap takes it fits are
material, not instruments. Nothing is uploaded, and nothing is fetched at render
time.

The suite is `STUDIO/test/test_dilla_*.rb`, which is the glob `rake test:dilla`
expands in `STUDIO/Rakefile`; bare `rake` runs the gate and every suite. Check
the path you are given before you trust a green run. This line has been wrong
twice — once naming a file that had not existed for months, once naming a
directory that has never existed — and both times it sent an operator to
validate nothing and read the result as passing.

Bare `ruby dilla.rb` writes `demo.wav` beside it: ten short pieces that are not
each other, about ninety seconds in all, hip hop through techno into ambient.
Each one is a row of `data/pieces.yml`, and a row names everything the bed knows
how to be — its tempo, which oscillator family plays the chords, which drum
grids and which crate the kit comes from, how loud and how treated the lead is,
and which console the master bus leaves through. The row is laid over
`data/bed.yml` before the bed reads a single number, so a piece renders in a
process of its own and keeps its own clock. The showcase is ninety seconds
because thirty-one pieces at length is eighteen minutes and nobody listens to
a demo that long; `ruby dilla.rb catalogue-full` is the whole table. An existing
`demo.wav` is a named take. The engine refuses to overwrite it unless
`DILLA_OVERWRITE=1`. Under every held chord
runs its own harmonic series, whole multiples of its lowest note, which is in
tune by construction and is what makes a sustained chord lush rather than merely
long.

`ruby dilla.rb compose` writes the other demo: one piece of about six minutes in
which every part of the engine plays and answers the others. The bass states the
key, one verified progression follows it and later comes back mirrored about that
key, the lead's motif is read from the chords, percussion answers each lead note,
and filter and gain lanes carry the form. The drums play every bar. A dilla kit
and a HATE layer drawn from `DillaSemantics` run under lanes of their own, so the
heavy section pushes one over the other rather than switching records, and the
kick drops out for a bar or two at most before a return. Every note is an event
before it sounds, and the swing, ratchets, stutters and reversals are transforms
that `data/bed.yml` names under `composition`.

`ruby dilla.rb catalogue` plays the older catalogue through one unchanged bed:
the seven verified recordings and the twelve improvisations, voiced on one
instrument each, voice-led, with the drums on top, a lead and a bass under it,
and every piece set to the same loudness under a true-peak ceiling. The bed began
as the pad under MASTER's narration and became the engine's render because it
sounded better than the engine's own catalogue; `ruby dilla.rb bed` still plays
it under the narration, ducking while a line is spoken, and
`STUDIO/dilla/data/bed.yml` holds every number it uses. `ruby dilla.rb demo-all`
renders the older engine's catalogue.

Old work comes back whole. An Ableton set is a gzipped XML document, so
`ruby dilla.rb import-als <file.als>` reads a set that no longer opens in Live —
wrong version, missing plugin, sample long gone — and gives back its tempo,
every track's device chain with the parameters each device was set to, the
plugin names and the paths they were loaded from, the fader, the pan and the
sends, every note, the harmony of every track that plays chords, the grid of
every track that plays drums, and the name of every sample it pointed at. A
parameter is read as any element carrying a manual value, which is why a device
nobody here has heard of still comes back with its settings.

Point it at a folder and it reads the lot. With `write` each set leaves a
profile in `project/imported`, its drum grids in `samples/midi` under the names
the banks glob for, and every melodic clip beside them as MIDI. Over a folder
it also writes a census: which devices and which plugins were used how often,
in what order they sat on a chain, at what tempos, and which samples were
reached for — the habits of whoever made the archive, counted rather than
remembered. The audio is not in the file and the samples usually are not on the
disk; what comes back is the writing and the decisions, and this engine
synthesises the sound itself.

`ruby dilla.rb ears` describes a render to somebody who cannot hear it. It
prints the nine octave bands, the loudness, the crest, the stereo width, how
much of the record sits below twenty-five hertz where nothing is heard and how
much sits above thirteen kilohertz where the air is, and it writes a
spectrogram. Given two files it prints the deltas between them, and with
`stems` it separates both first so a kick is compared with a kick rather than
a mix with a mix. The picture is the half that matters: nine octave bands put
eight to sixteen kilohertz in one number, and a record with no air at all can
pass every band and still be dull.
Bare `ruby dilla.rb` does not open by asking what you want, as postpro and
preprompt do: a render is reproduced from its knobs and its seed, and a question
at the start is a step a script cannot answer.

The instruments are recipes, not recordings. `AnalogSynth::PATCHES` in
`lib/sound.rb` builds each one from oscillators, a filter and two envelopes, and
its comments say what every setting is for: the Minimoog bass is three saws into
a filter that shuts within a fifth of a second, the Prophet pad a saw with a
triangle an octave above and a little resonance, the electric piano a triangle
and a square, struck and never held. The bed plays its own oscillator families,
declared in `data/bed.yml`.

ENV knobs, the switch reference and the render path in detail are in
`ENV_AND_RENDER.md`. There are three ways to hear the engine without rendering a
file: the Dilla Lab page brgen serves from `RAILS/brgen/public/dilla/dilla.html`,
`ruby dilla.rb live`, which plays the catalogue and, as `live set`, the livesets
in `lib/livesets.rb`, and `ruby dilla.rb sines`, which runs the sine stream.

A liveset take is not a wav. Every pass writes one line to
`project/liveset.jsonl` naming its seed and every choice it made, and keeping a
take renders it to `demo.wav` and adds that line, titled, to
`project/liveset_catalogue.json`. The next render replaces the audio; the line,
which is tracked, rebuilds the take on any machine that has the crate.

Renders sit beside `dilla.rb`, never in a folder of their own. `samples/` is the
one directory named for material: it is the crate, gitignored, and holds the
records, the grids and the synthesised kit. Nothing new is named `renders`,
`crate` or `samples`, because those words were read as three places for one
thing, and the gate refuses the retired directories.

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
114, D major at 0.697, corrected 60 / −3 / 6000.

Older ingest names (`four_seven`, `nightbus`, `dmaj_open`) still resolve through
`TRACK_SAMPLE_LOOP_ALIASES`, including for layer-profile lookup.

### Restoring a loop

`samples/` is gitignored, so a checkout without it loses the audio and keeps
every decision made about it. A fresh worktree has no crate at all, and the
tests that need a loop rack skip there with a sentence saying so rather than
fail; run the suite from the checkout that holds the crate before trusting a
green result about samples. Drop a loop back at `samples/<track>/loop.wav` and
nothing else is needed: `demo_sampled_order` reads the disk, so a restored loop
rejoins the demo on the next run, and `ruby dilla.rb assets` stops reporting it
missing.

The fetched sources and their stems are not kept beside the engine, so a
restore starts from the record itself, cut at the window named above. Verify it
by rendering: the loop should report the tempo and key named above.
`semua_untuk_mu` reads Eb major at fit 0.82 against the 0.79 in the note beside
its `TRACK_SAMPLE_LOOPS` entry, and 96 BPM, which is close enough to identify
the passage and not close enough to be a coincidence.

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
`vocals`, then find each loop's length and cut it. Each run writes
`samples/chopped/<slug>/loop.wav` with a row in `samples/chopped/loops.json`.
The rack is empty until a chop fills it: the earlier racks were deleted because
nothing reached them, and a row whose wav is gone drops out of the registry.
`TRACK_SAMPLE_LOOPS` reads the registry beside the hand-cut literal, and the
hand-cut entry wins where a slug is in both, so a chopped loop is
`TRACK=<slug>`-selectable like any other. `CHOP_BED=1` lets the
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
before release rather than after. `lib/sampling.rb` is the route that clears.

## Drums

The drum grids are `DRUM_PRESETS` in `lib/groove.rb`, in categories that are
deliberately kept apart; `ruby dilla.rb audit` counts them and names any that no
rotation reaches. Being able to say which a grid is matters more than having
more.

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
- **Sonitex sections are documented but unread.** `SONITEX_MIX`,
  `_DISTORTION`, `_VINYL`, `_TONE`, `_NOISE` and `_SAMPLING` are reserved
  names with no reader: setting any of them changes no sound. `SONITEX` and
  `SONITEX_PRESET` are the two that work. The six were documented before the
  per-section wet controls existed, and the controls never followed.
- **One console strip is not a console.** `sound.rb`'s own header argues
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

**A claim about the mix needs a render long enough to contain its evidence.** The
kit does not enter below 16 bars and the arrangement does not breathe below about
48, so an 8-bar A/B comparing "the drums sit better" compares two drumless takes
and hears a difference that is not there. State the bar count with the claim, and
pick it from what the claim depends on rather than from patience.

**A probe that reads a global must fail loudly when the global is absent.** An
absent reading is not a valid state and must never be scored as one. A census
elsewhere in this repo reported a live renderer dead because it read a global
under a name the page does not use, and the empty answer it got back — no
renderer, no frames — is exactly what a healthy fallback path reports too.
Separate "it said no" from "it did not answer", here as well: a knob probe that
finds no value must say the knob is unreadable, not that it is off.

**PRNG draw order is an interface.** Adding a `rand` above an existing one shifts
every draw after it, so a seed journalled last week reproduces a different take
and the journal quietly stops meaning anything. Append draws at the end of a
path, or accept that the old seeds are gone and say so where they are recorded.

## Running it

Run everything from `STUDIO/dilla`. `ruby dilla.rb out.wav 18` renders one
track of eighteen bars, and naming `TRACK=kembara_rindu` in front of it picks
the track. Bare `ruby dilla.rb` renders the sixteen-piece catalogue into `demo.wav`,
`ruby dilla.rb piece <name>` renders one of them, `ruby dilla.rb compose` renders
the six-minute piece, `ruby dilla.rb stream` plays without end, and `ruby dilla.rb help`
prints every command from the table the dispatcher reads.

The crate has its own verbs. `chop` cuts a long recording into beds, reading
`samples/ubrukte_samples.mp3` when given no path, and `chop list` shows the
rack. `crate` synthesises the thirty-eight one-shots and textures the kit is
made of. `export-midi` writes every grid as General MIDI into `samples/midi/`,
and `import-midi` reads drum clips back into sixteen-step grids.

Four verbs only measure. `beauty` scores a file's harmony and says what to try,
`quality` reports loudness, true peak, harshness and the sub against the kick,
`separate` splits a file into four stems with demucs, and `bed check` holds the
bed's band curve against the reference record.

## Environment and rendering

**One DNA table, several renderers.** Command aliases (`comfort`, `camel`, `warp`)
are gone — those are ENV overlays on `RENDER_MODE=dilla`. Genre *renderers*
(`techno`, `hate`, `industrial`, `analog`, `loose_pocket`) are real DISPATCH
keys with their own arrangement. Optional ENV knobs only; `config-provenance`
after a render beats memorizing the table.

Sources of truth:

| Path | Role |
|------|------|
| `dilla.rb` | Engine: `DILLA_STYLE_DEFAULTS`, `DILLA_BEST_DEFAULTS`, stream tables, render, DISPATCH |
| `lib/harmony.rb` | Bach + Dilla voicing operators (not styles) |
| `lib/groove.rb` | Sparse pocket phrases + micro-timing |

There is no separate product wrapper — `RAILS/shared/app/services/shared/dilla_processor.rb`
shells straight out to this file with `RENDER_MODE=dilla` and `TRACK`/`PROGRESSION`
set from the requested style (see `Shared::DillaProcessor#run_script`).

Inspect after a path that records provenance:

```sh
ruby dilla.rb config-provenance
```

## ENV layer order

Lower layers only **soft-fill** (set if empty). Later **force** overwrites.

### Product one-shot (`Shared::DillaProcessor` → `ruby dilla.rb dilla <out> <bars>`)

```
1. process ENV overrides     DillaProcessor sets RENDER_MODE=dilla, TRACK/PROGRESSION, RAP_VOCAL, …
2. engine boot
3. apply_best_defaults!      soft: RENDER_MODE table → DILLA_BEST → optional DILLA_DEEP
4. apply_dilla_style!        soft STYLE DNA
5. render_dilla
```

### Stream (`ruby dilla.rb` / `ruby dilla.rb stream`)

```
1. apply_stream_listenability_defaults!
     apply_best_defaults!              soft best (+ deep if STREAM deep)
     STREAM_COMFORT soft default         unless STREAM_PUNCH=1 or STREAM_COMFORT=0
     STREAM_EXTRA_DEFAULTS             soft (SPEAK, kit gains, RAP_VOCAL, LUFS, …)
     STREAM_FAST or DILLA_DEEP         soft
     STREAM_SOUL_DEFAULTS              soft when STREAM_SOUL≠0 or comfort
     apply_dilla_style!(force:true)    force full STYLE DNA
     if comfort_mode?
       DILLA_COMFORT_DEFAULTS          force sofa mix (SPEAK excluded from wipe)
     else
       STREAM_CREATIVE_MAX             force kit/vox layer after style
2. stream_rotate_drums! + track order  progressions + DRUM_PRESET/POCKET_SET
3. play("dilla", bars) → render_dilla
```

**Comfort vs punch:** stream defaults to sofa when comfort is on. Opt out with
`STREAM_PUNCH=1` or `STREAM_COMFORT=0`. One-shot comfort: `DILLA_COMFORT=1`.

**`DILLA_RAW=1`:** skip `apply_best_defaults!` soft fills — operator ENV only.

## Table map

| Table | Verb | Role |
|-------|------|------|
| `RENDER_MODE_DEFAULTS` | soft | sketch/record/perform/long_soul/golden/**warp** |
| `DILLA_BEST_DEFAULTS` | soft | Baseline knobs aligned with STYLE (no soft-fill conflicts) |
| `DILLA_DEEP_DEFAULTS` | soft | Quality gates + pocket jitter when deep |
| `DILLA_STYLE_DEFAULTS` | fill/force | **Canonical dilla DNA** (the only style) |
| `DILLA_COMFORT_DEFAULTS` | force when comfort | Sofa: calmer mix, no SPEAK wipe of user SPEAK |
| `STREAM_EXTRA_DEFAULTS` | soft then force as creative max (punch) | Stream kit/vox/normalize |
| `STREAM_SOUL_DEFAULTS` / `STREAM_FAST_DEFAULTS` | soft | Soul vs fast tradeoffs |

### `RENDER_MODE=warp` (opt-in knob, not a style)

Turns on already-built creative knobs: spectral arp/stack, `ARP_IDM_BIAS`,
drum chops, `GROOVE_DNA=cosmogramma`, quartal voicing, dub_chamber chain.

### Operator knobs (common)

| ENV | Role |
|-----|------|
| `TRACK` / `PROGRESSION` | Progression id (e.g. `pedal_e_descent`, `neo_soul`) |
| `BARS` / `STREAM_BARS` | Length |
| `STREAM_COMFORT` / `STREAM_PUNCH` | Sofa vs kit-forward stream |
| `DILLA_COMFORT` | Sofa overlay on one-shot |
| `RENDER_MODE` | `dilla` (default) or `warp` / sketch modes |
| `POCKET_SET` | `neo_soul` (default), `classic`, `dusty`, `industrial` |
| `KICK_GAIN` / `DRUM_BUS_VOL` | Kit bus (`0.88` / `0.95` in `DILLA_STYLE_DEFAULTS`) |
| `CHOIR_VOX` / `CHOIR_VOX_GAIN` | Soft ooh/aah (`0` / `0.16` default; `CHOIR_VOX=1` re-enables) |
| `STREAM_CREATIVE` / `STREAM_PUNCH` | Opt-in wild layer (LA_BEAT/vinyl/hot LUFS) — **off** by default |
| `DILLA_SH_TIMEOUT` | Kill a hung render step run through `sh!` (default 900s) |
| `DILLA_TOOL_TIMEOUT` | Kill a hung tool run through `ToolRun`: measurements, decodes, quiet conversions (default 900s) |
| `DILLA_PROBE_TIMEOUT` | Deadline for one `FfmpegProbe` measurement (default 300s) |
| `DILLA_FS_DRY` | Fluidsynth with its own chorus/reverb off — **off** by default; costs 12.6 dB of pad side-channel |
| `THEORY_RUNTIME` / `THEORY_DILLA` / `THEORY_BACH` | Voicing operators |
| `PAD_VOICE` / `PAD_VOL` / `PAD_LAYERS` | Pad bed |
| `LEAD_ARP` / `HARMONY_LEAD` / `SCALE_LEAD` | Lead layers — `SCALE_LEAD=1` needs `NO_ARP=0` beside it, and says so on stderr when it does not have it |
| `RAP_VOCAL` | Vocal slug or `0` |
| `SONITEX` / `ANALOG_CHAIN` | Master character |
| `STREAM_NORMALIZE` / `STREAM_LUFS` | Loudnorm target |
| `SPEAK` | TTS over beat (`0` product default) |
| `STREAM_DRUM_ROTATE` | Cycle drum preset/pocket each stream slot |
| `WONKY_DRUM_OVERLAY` / `DRUM_CHOPS` | Off by default (sparse soul kit) |
| `FM_DRUMS` | On (`1`) — FM kit is the default replacement |
| `DILLA_RAW` | Skip best soft defaults |
| `GROOVE_ENGINE` / `POCKET_DNA` | Pocket humanize (default on) |
| `GROOVE_FEEL` | `boom_bap` (**default**), `dilla_drag`, `camel` — the microtiming table |
| `LA_BEAT_PROGRESSION` | LA-beat arranger — **off**; see the Camel warning below |
| `MASTER_SMOOTH_DB` / `MASTER_SMOOTH_HZ` | De-harsher: 2 dB out at 3200 Hz by default |
| `HARM_PRESENCE_DB` / `DRUM_PRESENCE_DB` | Presence boosts, +1.6 and +1.5 — same band the de-harsher cuts |
| `RENDER_SEED` | Pins the whole render. Drawn and recorded when unset — see Provenance |
| `DILLA_OVERWRITE` | Replace an existing named take. Unset, `render_dilla` refuses rather than overwrite |
| `DEMO_TRACKS` | Explicit comma-separated order; beats every other rule in `demo_all_order` |
| `DEMO_CATALOG` | `stream` plays the stream rotation; `curated` plays the wide catalogue — records on disk, the stream rotation, the generated styles and the artist-verified progressions |
| `DEMO_FX` | Catalogue post-chain, off by default; `ringtone` adds tremolo, chorus, crusher and stereo widening, and the phaser and echo under `HATE_TUNNEL=1` |
| `RENDER_BEAUTY_MIN` | Harmony floor before a render is kept (55–78 across profiles) |

Three of these are worth stating outright because each one is a documented
capability that is off, or a default that surprises:

- **`GROOVE_FEEL` defaults to `boom_bap`**, so the Dilla microtiming this engine
  is named for is not applied unless asked. `dilla_drag` is the snare-behind
  table; `camel` drags further and pulls the hats early, which is what reads as
  broken rather than swung.
- **`LA_BEAT_PROGRESSION` is off on purpose**, and the reason is specific:
  forcing it on Camel injected random planing-style chords and made streams
  sound broken. It and the fugue arranger both rewrite the progression, so
  running both means two arrangers fighting over the same chords.
- **Presence is boosted twice and cut once.** `HARM_PRESENCE_DB` adds 1.6 dB
  and `DRUM_PRESENCE_DB` 1.5 dB around the presence band; `MASTER_SMOOTH_DB`
  takes 2 dB back out at 3.2 kHz. Net is still a boost into the band the comment
  at `master_smooth!` calls "where distortion and harshness actually live". If a
  render is rough on the ears, this arithmetic is the first place to look, not
  the tape stage.

Full DNA is large (mix bus dB, harmonic stem weights). Prefer
`config-provenance` after a render over memorizing every key.

## Switches, by what they touch

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
| `SAMPLE_START_MS` | the loop lands this many ms behind the kit, or ahead of it when negative; the drums do not move |

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
| `SHIFT_TIMING=snare:-6,hat:4` | the MPC's shift timing: one role early or late by a fixed ms, on top of the pocket (`kick` and `hat` name both their roles) |
| `WONKY_DRUM_OVERLAY=1` | Camel dual-bus: sub at 55/110/180, top at 3.5k/6.5k/9k |
| `WONKY_TOP_DIRT` | phaser/flanger/crush on cymbals, kick untouched |
| `WONKY_HAT_DUCK` | duck the top bus by the kick bus |
| `DRUM_FIELD_LAYER` | room tone under the kit, ducked by it |

Movement and master. The analog stages are **on by default**. Every one of them
shipped built and set to `0`, so for a long time nothing this engine rendered had
ever been through them. Set a switch to `0` for that older, drier behaviour.

| switch | default | what |
|---|---|---|
| `BUS_ANALOG` | `0.3` | per-channel saturation plus small phase offsets, so buses don't sum coherently |
| `CONSOLE_STRIP` | `0.35` | per-channel desk model; L and R run one seed apart, which is the point |
| `TAPE_HYSTERESIS` | `0.25` | Jiles-Atherton, RK4 — path-dependent, unlike every other stage |
| `TAPE_BIAS` | `1.0` | 1 = original loop; lower = less bias, wider hysteresis (ChowTape) |
| `TAPE_LOSS_HZ` | `0` | spacing/loss lowpass into JA; 0 is off, 14000 is the analog start |
| `TAPE_WOW_MS` | `0.6` | Ornstein-Uhlenbeck flutter |
| `SONITEX_MIX` / `_DISTORTION` / `_VINYL` / `_TONE` / `_NOISE` / `_SAMPLING` | — | Documented but unread. Setting these changes nothing; use `SONITEX` / `SONITEX_PRESET` |
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

## One-shot render path

```sh
cd STUDIO/dilla
TRACK=pedal_e_descent PROGRESSION=pedal_e_descent ruby dilla.rb dilla /tmp/beat.wav 12
```

### 1. Engine CLI (`DISPATCH["dilla"]`)

1. Destination + bars
2. Best defaults (unless `DILLA_RAW`) + style DNA
3. `render_dilla(dest, bars)`

### The shape of a render

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

### 2. `render_dilla` (core)

```
require ffmpeg · cleanup · pick_render_seed!
ensure_drum_kit!
cfg = dilla_resolve_config
composition_session! if COMPOSITION=1
pick_synth_patches!
pads = dilla_progression(cfg)
arrange + beautify (harmony)
theory_runtime refine (Bach/Dilla operators)
events = dilla_schedule(...)   # sparse pocket + groove_engine
render_sample_bus_wav → drums
render_harmonic_wav:
  pads (stack_soul layers)
  + CHOIR_VOX chord-tone ooh/aah (soft)
  + tones / leads / pluck
sidechain amix → sonitex → analog → heuristics → loudnorm
```

### 3. Product attach (RAILS)

`Shared::DillaProcessor.render_to_file!` → engine → Active Storage.

## Stream rotation

- **Progressions:** full pack (priority first: `pedal_e_descent`, neo-soul, untitled, …)
- **Drums:** `STREAM_DRUM_ROTATION` — soulful kits only (`dilla_slight`, `mpc3000`, …)
- **No style sequence** — one DNA every slot; mix knobs only (`STREAM_COMFORT`, etc.)
- **Style DNA wins** after force; `STREAM_CREATIVE_MAX` only when `STREAM_CREATIVE=1` or `STREAM_PUNCH=1`

## The catalogue demo.wav plays

Sixteen rows in `data/pieces.yml`. Each is laid over `data/bed.yml` by
`lib/pieces.rb` before `module Bed` reads a number, so a row may set anything
the bed has — tempo, `pad_families`, `lead.rack_names`, `drums.arrangement`,
`drums.samples`, `master_bus.console`, `overtones`.

```sh
cd STUDIO/dilla
ruby dilla.rb                      # the catalogue -> demo.wav + demo.mp3
ruby dilla.rb pieces-list          # the table, one line each
ruby dilla.rb piece still_water out.wav
RENDER_SEED=42 ruby dilla.rb       # the same take again
ruby dilla.rb compose              # the six-minute piece instead
```

`DILLA_PIECE=<name>` is the knob under all of it: it chooses the overlay at
load, so anything that boots `dilla.rb` with it set is that piece. `piece`
sets it and re-execs when it was typed by hand, because a name that arrives in
`ARGV` arrives after `Bed` has already settled its constants.

## Reading old Ableton sets

```sh
ruby dilla.rb import-als "~/Downloads/kp Project/kp.als"   # one set
ruby dilla.rb import-als ~/Downloads/livesets              # every set under it
ruby dilla.rb import-als ~/Downloads/livesets write        # and write it all out
```

Reads tempo, every track's devices with their parameters, plugin names and
paths, fader/pan/sends, all notes, harmony per chord track, grid per drum
track, and every sample reference. `write` puts a profile per set in
`project/imported/<slug>.yml`, drum grids and melodic clips in
`samples/midi/<slug>/`, and `project/imported/_census.yml` across the folder.

Three tempo spellings are tried, because sixteen years of Live are in one
archive: Live 12 renamed `MasterTrack` to `MainTrack`, and Live 8 and 9 keep
the tempo as an automation event rather than a manual value.

## What a render measures like

```sh
ruby dilla.rb ears                        # demo.wav
ruby dilla.rb ears a.wav b.wav            # both, with band deltas
ruby dilla.rb ears a.wav b.wav stems      # demucs first
ruby dilla.rb ears a.wav --json           # the old metadata report
```

Octave bands, LUFS, LRA, true peak, crest, stereo width, sub energy below
25 Hz and air above 13 kHz, plus a spectrogram per file under `<output>/ears`.

## Full playlist demo

```sh
cd STUDIO/dilla
SPEAK=0 ruby dilla.rb demo-all 12 demo.wav
# resume skips existing parts; DEMO_FORCE=1 re-renders all
# DEMO_TRACK_TIMEOUT=150 DEMO_ALBUM_NORM=1
```

## Provenance debugging

Every run writes a `<file>.provenance.json` beside each audio file it produced —
`lib/ledger.rb`, hooked at the CLI entry before anything reads a seed. It
carries the render seed, argv, the env knobs that change the output, the engine
commit, whether the working tree was clean, and a sha256.

```sh
ruby dilla.rb replay direction_v4.wav.provenance.json
# RENDER_SEED=1505395575 TRACK=circle_fifths_descent … ruby dilla.rb dilla …
```

`RENDER_SEED` is drawn and recorded when unset rather than left to chance. The
consequence is worth knowing: an unpinned render now runs through the *pinned*
code paths, so noise comes from `seed_for(tag)` rather than ffmpeg's `seed=-1`.
Two unpinned renders still differ from each other exactly as before; each is now
a draw that can be replayed instead of one that cannot. `DILLA_NO_PROVENANCE=1`
restores the old behaviour, seed and all.

Nothing before 2026-08-11 is reproducible. The 616 audio files in the tree at
that point, `su_tunnel_choir.wav` among them, have no recorded seed and cannot
be made again.

For the resolved ENV rather than the render:

```sh
cd STUDIO/dilla
SPEAK=0 BARS=4 ruby -e '
  load "dilla.rb"
  apply_best_defaults!
  apply_dilla_style!(force: true)
  print_config_provenance
'
```

## Related files

| Path | Role |
|------|------|
| `dilla.rb` | Monolith + DISPATCH + ENV tables |
| `lib/groove.rb` | Chords, timing DNA |
| `lib/groove.rb` | Pocket phrases, Gaussian jitter, phrase drift |
| `lib/harmony.rb` | Beautify / insight |
| `lib/harmony.rb` | Bach + Dilla voicing refine |
| `lib/harmony.rb` | Form, performers |
| `lib/listen.rb` | Master FX + loss gates |
| `lib/music_gems.rb` | coltrane / head_music / midilib / wavefile |
| `README.md` | Usage summary |

## Sample acquisition

`ruby dilla.rb slskd "<query>"` can use a local
[slskd](https://github.com/slskd/slskd) instance as an optional sample source.
slskd exposes search and transfer APIs under `/api/v0`; the adapter uses those
APIs rather than embedding Soulseek in Dilla.

Run:

`SLSKD_API_KEY=... SLSKD_DOWNLOAD_DIR=/path/to/slskd/completed ruby dilla.rb slskd "j dilla break"`

The adapter prefers FLAC/WAV/AIFF over lossy formats and prefers peers with an
available upload slot and shorter queues. It copies the selected file into
Dilla's ignored local cache and registers it in the existing chopped-loop
registry, so the ordinary renderer sees it as a normal sample loop.

Soulseek availability is not a licence. The default rights state is `unknown`,
and an unknown result is blocked unless `SLSKD_ALLOW_UNKNOWN=1` is set. For
material whose rights you have actually established, set
`SLSKD_RIGHTS=owned`, `public_domain`, `cc0`, or `cc_by`.

The registry preserves the Soulseek peer, exact filename and byte size, search
query, SHA-256 of the downloaded audio, duration, sample rate, channel count,
rights state, verification state and download timestamp.

For production/release work, keep `SLSKD_ALLOW_UNKNOWN` off. The explicit
unknown mode exists for private experimentation and research; it is not a
copyright bypass.

The slskd API contract is isolated in `lib/slskd_crate.rb`. If slskd changes,
the renderer and the existing Dilla sample registry do not need to know.

## Reverse engineering notes

This folder is for local analysis only. Audio, stems, and YouTube dumps stay
gitignored. They are not the catalogue.

## What demo.wav actually carries

The last write on the take was `grit_catalogue!`: 7.5 ips tape, a mild triode,
11-bit crush, and a gated square/noise chip with space echo, applied after the
pieces join. That is dirt on the showcase, not a new arrangement.

The engine already knew the three records the operator named. `data/dilla_reference.yml`
holds documented progressions for Slum Village *Fantastic Vol. 2* (Players,
Intro) and Flying Lotus *Los Angeles* (Beginners Falafel, Camel). `lib/groove.rb`
has a `dillatime` pocket at swing 58. `DfamEngine` is the dual-osc FM percussion
voice, on unless `DFAM=0`. Techno pieces already point at `*kit_industrial` and
`feel_hardgroove`. HATE is a named drum profile in `bed.yml`.

The grit chain did not make the drums more 909, the chords more Dilla, or the
textures more FlyLo. It made the joined file sound like a cassette.

## HATE channel

https://www.youtube.com/channel/UC6qQOTx9LuKMC5p2dbjmSRg is HATE, a commercial
techno promotion channel (hour-long mixes: Ben Klock Podcast 500, Marie
Montexier 499). Dumping that catalogue into the tree is a copyrighted mix
archive, not a drum analysis. `yt-dlp` and `demucs` are on the machine. They
are not run against the whole channel from here.

## Dilla, Fantastic Vol. 2, neo-soul Detroit

James Yancey, Conant Gardens. Slum Village with T3 and Baatin. *Fantastic Vol. 2*
finished 1998, released 2000. Questlove and Robert Glasper both credit it with
changing where a chord sits relative to the beat.

Documented flips on that record (from published track analyses, not from
stems we do not have):

- Conant Gardens — Little Beaver "A Tribute To Wes"; Tribe "Award Tour" vocal
- I Don't Know — Baden Powell "É Isso Aí"; James Brown chops
- Jealousy — Bill Evans Trio electric piano, last minute of the cut
- Fall In Love — Gap Mangione "Diana in the Autumn Wind" (1976)
- Get Dis Money — Herbie Hancock "Come Running to Me" (1978) Rhodes
- Untitled/Fantastic — Singers Unlimited "Claire" (the one people still argue)
- World Full of Sadness — Roy Ayers Ubiquity "Love from the Sun"

The people behind those records: Gap Mangione (Chuck's brother, jazz fusion),
Herbie Hancock (Head Hunters / Sunlight vocoder era), Bill Evans, Baden
Powell, Roy Ayers, Motown bass (Jamerson) as the city's low-end grammar, Amp
Fiddler as the Detroit neo-soul hinge Dilla actually sat with.

The harmonic habit is rootless ninths and thirteenths that do not cadence:
Cm9–Fm9–Bb13–Ebmaj7 is the Intro/Players colour. Swing is independent clocks,
not a single MPC percentage. Vinyl crackle is the medium, not a plugin.

## Flying Lotus, Los Angeles

Steven Ellison, 2008, Warp. Beginners Falafel and Camel are ii–V–I–IV in C
with ninths and a lydian #11 on the IV. The engine already stores those
voicings. The FlyLo feel in this tree is stagger, FM, and the `flylo` drum
bank, not a new sample pack.

## DFAM and 909

`lib/sound.rb` `DfamEngine`: two oscillators, FM, noise, resonant decay, an
8-step pitch/velocity sequencer. That is the Moog DFAM shape already. GitHub
does not have a DFAM emulator worth vendoring; what exists is Arduino MIDI
sync for the hardware (`dllmkdir/Moog-DFAM-MIDI-sync`) and Minimoog clones
(`t2techno/Faug`, `giorgiogamba/MinimoogEmulator`). For techno kicks the
useful public circuit work is TR-909 firmware analysis (`Jacquot-SFE/tr-909-analysis`)
and analog 909 kick studies, not another LUT.

## What would actually move the take

Point the showcase at Fall In Love first (done). Re-render `demo.wav` so the
file matches the table. Keep DFAM on. Do not ingest HATE.
