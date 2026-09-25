# Dilla

## Canonical contract

### Purpose

Generate deterministic music from declarative musical material, with synthesis,
sampling, arrangement, mix, master, measurement, and provenance kept behind one
tool boundary.

### Inputs

Ruby/YAML configuration, an optional local sample crate, deterministic seeds,
and explicit command-line or environment overrides.

### Outputs

Audio renders, MIDI/project material, measurements, provenance records, and
diagnostic reports. No output is considered valid merely because a file exists.

### Invocation

Use `ruby MASTER/tools/dilla/dilla.rb <command>`. The entrypoint is
standalone-loadable and does not depend on the MASTER process already being
booted.

### Architecture

`dilla.rb` is the orchestration boundary. `lib/` contains synthesis, groove,
harmony, sampling, rendering, and analysis machinery. `data/` contains the
declarative musical source.

### Data and state

Tracked recipes and measurements are source. Audio/sample crates, temporary
work, and machine-local caches remain untracked unless explicitly promoted as
provenance.

### Security boundary

Treat samples, archives, paths, and media metadata as untrusted. Use argument
arrays for subprocesses, bound resource use, avoid arbitrary deserialization,
and keep network access out of rendering unless an explicitly governed fetcher
is introduced.

### Validation

Run the tool's own audit/measurement commands and MASTER's tool gates. A render
must be reproducible from its declared inputs, and missing material must be
reported rather than silently replaced.

### MASTER integration

Dilla is a canonical MASTER tool. MASTER governs dispatch and lifecycle; Dilla
owns music-specific generation and measurement.


**A beat engine that never phones home.** `dilla.rb` and the helpers under
`lib/` generate harmony, program drums, play sampled loops against them, mix,
master, and write an mp3 or a wav. Every instrument is synthesised by the engine
and shaped through `ffmpeg`; the records it samples and the rap takes it fits are
material, not instruments. Nothing is uploaded, and nothing is fetched at render
time.

The suite is `MASTER/tools/test/test_dilla_*.rb`, which is the glob `rake test:dilla`
expands in `MASTER/tools/Rakefile`; bare `rake` runs the gate and every suite. Check
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
`MASTER/tools/dilla/data/bed.yml` holds every number it uses. `ruby dilla.rb demo-all`
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

Every knob the engine reads, with its current default, comes from
`ruby dilla.rb knobs`, and `config-provenance` after a render names what that
render resolved. There are three ways to hear the engine without rendering a
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
hysteresis, tilt, dropout and mono bass, in that order.

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
- **`GROOVE_FEEL` is the microtiming table, and it defaults to `dilla_drag`**:
  the snare sits behind while the hats hold the grid. `boom_bap` is straight
  ahead and `camel` drags further and pulls the hats early. It defaulted to
  `boom_bap` for months, so a render from before that change was straight
  whether or not anyone meant it.
- **The fugue arranger is gated on the track's *name*.** `arrange_fugue_progression`
  builds exposition / development / recapitulation, and `theory_runtime` only
  reaches for it when `TRACK` matches `/bach|baroque|circle|fugue/i`. Of the
  whole catalogue only `circle_fifths_descent` does, so asking for "a fugue
  concept" on any other track silently gets none.
- **Presence is boosted twice and cut once.** `HARM_PRESENCE_DB` and
  `DRUM_PRESENCE_DB` both push the region `MASTER_SMOOTH_DB` cuts at 3.2 kHz,
  and together they add more than it takes out, so the net is a boost into the
  band `master_smooth!` itself calls "where distortion and harshness actually
  live". If a render is rough on the ears, this arithmetic is the first place to
  look; `ruby dilla.rb knobs` prints the three current values.
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

## Findings that keep recurring

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

## How the environment is layered

One table of Dilla DNA drives several renderers. `comfort`, `camel` and `warp`
are not commands; they are environment overlays on `RENDER_MODE=dilla`. The
genre renderers, `techno`, `hate`, `industrial`, `analog` and `loose_pocket`,
are real dispatch keys with arrangements of their own. There is no product
wrapper: `Shared::DillaProcessor` in `RAILS/shared` shells straight out to
`dilla.rb` with `RENDER_MODE=dilla` and the requested track, and attaches the
file through Active Storage.

Lower layers only soft-fill, setting a knob when it is empty, and later layers
force. A one-shot render takes the caller's environment first, then the engine's
best defaults for the render mode, then the style DNA, and only then renders.
The stream adds its own layer between those: listenability defaults, then the
comfort mix unless `STREAM_PUNCH=1` or `STREAM_COMFORT=0`, then extra stream
defaults for speech, kit gains, vocals and loudness, and finally the style DNA
forced in full. Comfort on top is the sofa mix; punch puts the creative-maximum
kit and vocal layer on instead. `DILLA_COMFORT=1` gives a one-shot the sofa mix,
and `DILLA_RAW=1` skips every soft default so only the operator's environment
applies.

The tables behind those layers are `RENDER_MODE_DEFAULTS` for the sketch,
record, perform, long-soul, golden and warp modes; `DILLA_BEST_DEFAULTS` as the
baseline; `DILLA_DEEP_DEFAULTS` for quality gates and pocket jitter;
`DILLA_STYLE_DEFAULTS` as the one canonical style; `DILLA_COMFORT_DEFAULTS`;
and the stream's extra, soul and fast tables. `RENDER_MODE=warp` switches on
creative knobs that already exist: spectral arps and stacks, drum chops, the
cosmogramma groove, quartal voicing and the dub chamber chain.

Defaults are not restated here, because every table of them this file kept
went stale. `ruby dilla.rb knobs` lists every knob the engine reads with its
current default, `knobs conflicts` names the ones with two defaults, and
`config-provenance` after a render names what that render resolved.

## The knobs, by what they touch

The knobs a session reaches for first choose the material: `TRACK` or
`PROGRESSION` picks the progression, `BARS` or `STREAM_BARS` the length,
`POCKET_SET` the pocket family, `DRUM_PRESET` any drum grid, and `RAP_VOCAL` a
vocal slug or `0`. `RENDER_SEED` pins the whole render, and `DILLA_OVERWRITE`
lets a render replace a named take instead of refusing. `DEMO_TRACKS` names an
explicit catalogue order, `DEMO_CATALOG` chooses the stream rotation or the
wide curated catalogue, and `DEMO_FX=ringtone` puts the catalogue post-chain
on. `RENDER_BEAUTY_MIN` is the harmony floor a render must clear to be kept.

Sample handling has its own family. `HARMONIC_KEEP` moves generated pads onto
the loop's detected key and `HARMONIC_SHUFFLE` orders chords so the top voice
traces one arc. `ORGANIC_VARY` rebuilds the bed as passes that differ, since
looping a file is bit-identical and nothing acoustic is. `LOOP_CHOP_SLICES`
cuts each pass into slices and rotates them, so the loop becomes material rather
than a part. Varispeed makes pitch follow tempo as a record does, while
`SAMPLE_LOOP_SEMITONES` shifts pitch alone. `SAMPLE_FM` adds audio-rate
vibrato floored at 700 Hz so chord tones stay untouched, `SAMPLE_SCALE` layers
the loop at degrees of its own key, `LOOP_WOW_CENTS` puts tape instability on
the loop and never the kit, `LOOP_DELAY_BEATS` adds a tempo-synced echo, and
`SAMPLE_START_MS` moves the loop against the kit without moving the drums. With
`DILLA_XSAMPLE` naming a partner, `DILLA_XCONVOLVE` makes one loop the room the
other plays in and `DILLA_XGATE` drives one loop's harmony with the other's
rhythm.

The drums answer to `NO_QUANTIZE`, `SWING_ROLE_SPREAD` and `SHIFT_TIMING`,
which is the MPC's shift timing, such as `snare:-6,hat:4`, on top of the pocket.
`WONKY_DRUM_OVERLAY` is the Camel dual bus, with `WONKY_TOP_DIRT` putting
phaser, flanger and crush on the cymbals and `WONKY_HAT_DUCK` ducking the top
by the kick. `DRUM_FIELD_LAYER` puts room tone under the kit. `FM_DRUMS` is the
FM kit that replaces the sampled one, and `DFAM=0` turns off the dual-oscillator
percussion voice. `BASS_FEEL` lets the bass take the groove's offset.

The master stages are on by default, because each shipped built and set to
zero and nothing rendered went through them for a long time. `BUS_ANALOG` is
per-channel saturation with small phase offsets so buses do not sum coherently,
`CONSOLE_STRIP` a per-channel desk whose left and right run one seed apart,
`TAPE_HYSTERESIS` the Jiles-Atherton model with `TAPE_BIAS` and `TAPE_LOSS_HZ`
beside it, and `TAPE_WOW_MS` Ornstein-Uhlenbeck flutter. `MASTER_SMOOTH_DB`
answers "harsh", `SMOOTH_ANALOG` drops patches on metallic General MIDI
programs, `MASTER_TILT_DB` darkens as it goes negative, `MONO_BASS_HZ` sums the
low end to mono, and `ORGANIC_BREATH` and `ORGANIC_SWELL` move loudness and
brightness together. `DILLA_DROPOUT_EVERY`, `DILLA_DRONE` and `DILLA_TAPE_STOP`
are effects rather than stages. Set any stage to `0` for the older, drier
render. `SONITEX` and `SONITEX_PRESET` choose the tape character; the six
section names beside them have no reader.

`NO_ARP` holds chords and gives the lead phrases, and it covers three separate
arp paths, `pad_arp_mode`, `lead_true_arp_mode?` and `lead_events_scale_arp`.
It was first written against one of them, so pads went quiet while leads kept
arpeggiating, and the stream set `LEAD_FORCE_ARP` per track and won every time.
`SCALE_LEAD` needs `NO_ARP=0` beside it and says so on stderr when it lacks it.
`LA_BEAT_PROGRESSION` is off on purpose: forced on Camel it injected planing
chords and made streams sound broken, and with the fugue arranger it would be
two arrangers fighting over the same chords.

Vocals snap sung lines to the grid with `RAP_VOCAL_SNAP`, drag each line behind
the beat with `RAP_VOCAL_LEAN_MS`, and swell into each line with
`RAP_VOCAL_SWELL`. Snapping exists because a freely sung take has no tempo to
stretch onto. Against a 92 beat, stretching one take landed between 14 and 31
percent of its onsets on the grid, against a random baseline near 20; placing
lines instead put 87 percent of line starts on the grid at a five millisecond
median.

The timeouts are `DILLA_SH_TIMEOUT` for a render step, `DILLA_TOOL_TIMEOUT`
for measurements and decodes, and `DILLA_PROBE_TIMEOUT` for one ffmpeg probe.
`DILLA_FS_DRY` turns off fluidsynth's own chorus and reverb, which costs the
pad its side channel.

## The stream, the catalogue and old sets

The stream plays the whole progression pack, the priority ones first, and
rotates only through soulful kits. It has no style sequence: one DNA every
slot, with the mix knobs as the only difference, and the creative-maximum
layer only under `STREAM_CREATIVE=1` or `STREAM_PUNCH=1`.

The catalogue is thirty-one rows of `data/pieces.yml`. `module Pieces` in
`dilla.rb` lays a row over `data/bed.yml` before `module Bed` reads a number, so
a row may set anything the bed has: tempo, pad families, the lead rack, the drum
arrangement and samples, the master console and the overtones.
`DILLA_PIECE=<name>` chooses the overlay at load, so anything that boots
`dilla.rb` with it set is that piece. `piece` sets it and re-executes when typed
by hand, because a name that arrives in the arguments arrives after `Bed` has
settled its constants.

`import-als` tries three tempo spellings, because sixteen years of Live sit in
one archive: Live 12 renamed `MasterTrack` to `MainTrack`, and Live 8 and 9 keep
the tempo as an automation event rather than a manual value. With `write` a set
leaves its profile in `project/imported/`, its grids and melodic clips in
`samples/midi/`, and a census of the folder in `project/imported/_census.yml`.

`demo-all` resumes, skipping parts already rendered; `DEMO_FORCE=1` renders
them all again, `DEMO_TRACK_TIMEOUT` bounds one part and `DEMO_ALBUM_NORM=1`
levels the album.

## Provenance

Every run writes a `<file>.provenance.json` beside each audio file it produced,
through `lib/ledger.rb`, hooked at the command entry before anything reads a
seed. It carries the render seed, the arguments, the knobs that change the
output, the engine commit, whether the tree was clean, and a sha256. `replay`
turns one back into the command that makes the take again.

`RENDER_SEED` is drawn and recorded when unset rather than left to chance, so
an unpinned render runs through the pinned code paths and its noise comes from
`seed_for(tag)` rather than ffmpeg's random seed. Two unpinned renders still
differ; each is now a draw that can be replayed. `DILLA_NO_PROVENANCE=1`
restores the old behaviour, seed and all. Nothing before 2026-08-11 is
reproducible: the 616 audio files in the tree then, `su_tunnel_choir.wav` among
them, have no recorded seed.

## Sample acquisition

`ruby dilla.rb slskd "<query>"` can use a local slskd instance as an optional
sample source through its search and transfer API, rather than embedding
Soulseek. It prefers lossless files and peers with a free slot and a short
queue, copies the chosen file into the ignored local cache, and registers it
in the chopped-loop registry, so the renderer sees an ordinary sample loop. The
registry keeps the peer, the filename and size, the query, the audio's sha256,
its duration, rate and channels, the rights state, the verification state and
the download time. The slskd contract is isolated in `lib/slskd_crate.rb`, so a
change there reaches nothing else.

Soulseek availability is not a licence. The default rights state is unknown,
and an unknown result is blocked unless `SLSKD_ALLOW_UNKNOWN=1`, which exists
for private research and is not a copyright bypass. For material whose rights
are established, set `SLSKD_RIGHTS` to owned, public domain, CC0 or CC BY, and
keep the unknown mode off for anything released.

## The records the engine already knows

The operator named three records, and the engine already held them.
`data/dilla_reference.yml` keeps documented progressions for Slum Village's
*Fantastic Vol. 2*, the Intro and Players, and for Flying Lotus's *Los
Angeles*, Beginners Falafel and Camel. `lib/groove.rb` has a `dillatime` pocket
at swing 58, and `DfamEngine` in `lib/sound.rb` is the Moog DFAM's shape: two
oscillators, FM, noise, a resonant decay and an eight-step pitch and velocity
sequencer. Techno pieces point at the industrial kit and the hardgroove feel,
and HATE is a named drum profile in `bed.yml`. The HATE channel itself is a
commercial techno promotion archive; dumping it into the tree would be a
copyrighted mix archive rather than drum analysis, so neither `yt-dlp` nor
`demucs` is run against it from here.

*Fantastic Vol. 2* was finished in 1998 and released in 2000, and Questlove and
Robert Glasper both credit it with changing where a chord sits against the
beat. Its documented flips, from published track analyses rather than stems,
are Little Beaver's "A Tribute To Wes" under Conant Gardens, Baden Powell's "É
Isso Aí" under I Don't Know, the Bill Evans Trio's electric piano under
Jealousy, Gap Mangione's "Diana in the Autumn Wind" under Fall In Love, Herbie
Hancock's "Come Running to Me" under Get Dis Money, the Singers Unlimited's
"Claire" under Untitled, and Roy Ayers Ubiquity's "Love from the Sun" under
World Full of Sadness. The harmonic habit is rootless ninths and thirteenths
that do not cadence, Cm9, Fm9, Bb13, Ebmaj7 for the Intro and Players. The
swing is independent clocks rather than one MPC percentage, and the crackle is
the medium rather than a plugin.

Beginners Falafel and Camel are ii, V, I, IV in C with ninths and a lydian
sharp eleven on the IV, and the engine stores those voicings. The FlyLo feel
here is stagger, FM and the `flylo` drum bank. For techno kicks the useful public
work is TR-909 circuit analysis rather than another lookup table, and no DFAM
emulator on GitHub is worth vendoring.

The last write on the showcase was `grit_catalogue!`: 7.5 ips tape, a mild
triode, an 11-bit crush and a gated chip voice with space echo, after the
pieces join. It made the joined file sound like a cassette; it did not make the
drums more 909, the chords more Dilla or the textures more FlyLo.

## Running it

Run everything from `MASTER/tools/dilla`. `ruby dilla.rb out.wav 18` renders one
track of eighteen bars, and `TRACK=kembara_rindu` in front of it picks the
track. Bare `ruby dilla.rb` renders the ten-piece showcase into `demo.wav`,
`piece <name>` renders one row, `compose` the six-minute piece, `stream` plays
without end, and `help` prints every command from the table the dispatcher
reads.

The crate has its own verbs. `chop` cuts a long recording into beds, reading
`samples/ubrukte_samples.mp3` when given no path, and `chop list` shows the
rack. `crate` synthesises the thirty-eight one-shots and textures the kit is
made of. `export-midi` writes every grid as General MIDI into `samples/midi/`,
and `import-midi` reads drum clips back into sixteen-step grids.

Four verbs only measure. `beauty` scores a file's harmony and says what to try,
`quality` reports loudness, true peak, harshness and the sub against the kick,
`separate` splits a file into four stems with demucs, and `bed check` holds the
bed's band curve against the reference record. `ears` describes a render, two
files as deltas, and with `stems` separates both first.

The commands below, in order: the showcase, the catalogue table, one piece,
the same take again, the six-minute piece, an Ableton set, a folder of them
written out, a render described, two compared, a one-shot through the product
path, the older catalogue, and a replay from a provenance sidecar.

```sh
ruby dilla.rb
ruby dilla.rb pieces-list
ruby dilla.rb piece still_water out.wav
RENDER_SEED=42 ruby dilla.rb
ruby dilla.rb compose
ruby dilla.rb import-als "~/Downloads/kp Project/kp.als"
ruby dilla.rb import-als ~/Downloads/livesets write
ruby dilla.rb ears
ruby dilla.rb ears a.wav b.wav stems
TRACK=pedal_e_descent ruby dilla.rb dilla /tmp/beat.wav 12
SPEAK=0 ruby dilla.rb demo-all 12 demo.wav
ruby dilla.rb replay direction_v4.wav.provenance.json
ruby dilla.rb knobs
```

## Security and trust boundaries

Dilla is an offline-first media tool. Its main security surface is local input, process execution, filesystem state, and imported project data rather than an HTTP API.

The important architectural rules are:

- Treat imported Ableton XML, YAML, JSON, MIDI, audio metadata, and generated manifests as untrusted data. Parse data as data; never turn imported strings into Ruby source, shell fragments, or dynamic constant names.
- Keep external-process arguments structured. ffmpeg, ffprobe, Demucs, and other helpers must receive argument arrays rather than shell-interpolated command strings.
- Treat every path as hostile to the boundary it crosses. Resolve it, constrain it to the intended workspace where appropriate, and do not follow an unexpected symlink between validation and use.
- Make state-changing renders atomic. A render should write a temporary file, validate it, then replace the destination; concurrent renders must not corrupt a catalogue or provenance record.
- Keep network access out of the render path. If a future feature downloads material or metadata, it needs an explicit, bounded fetch boundary with redirect validation and private/link-local destination protection.
- Keep provenance authoritative. A checksum, seed, source path, rights declaration, and resolved configuration describe what was actually rendered; they are evidence, not permission to use material whose rights are unknown.
- Prefer data-only serialization. Never deserialize arbitrary Ruby objects from project files.

The wider MASTER security vocabulary also covers HTTP request framing, SSRF, TOCTOU races, GraphQL query abuse, JWT verification, unsafe deserialization, and abandoned DNS records. Most are not Dilla-specific today; they become relevant if Dilla is exposed through a web service, remote job queue, API, or hosted asset importer.

## MASTER integration

Dilla is a MASTER tool, not a second application framework. Its source of truth remains its own data, code, presets, and provenance files, while MASTER owns governance, invocation, validation, and tool discovery.

Canonical commands:

ruby MASTER/tools/dilla/dilla.rb knobs
ruby MASTER/tools/dilla/dilla.rb ears demo.wav
ruby MASTER/tools/dilla/dilla.rb config-provenance
ruby MASTER/tools/dilla/dilla.rb audit

The canonical path is now MASTER/tools/dilla. Retired MASTER/tools/dilla references should not be copied into new automation.
