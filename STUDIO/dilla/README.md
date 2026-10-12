# Dilla

**A beat engine that never phones home.** Dilla writes the harmony, programs the drums, plays
sampled loops against them, mixes, masters and plays or renders the result, and every
instrument in it is synthesised on the spot. The records it samples and the rap takes it fits
are material and not instruments. Nothing is uploaded, nothing is fetched at render time, and
every take can be asked how it was made.

The entry point is `dilla.rb`, a single large file that loads the helpers under `lib/` and
declares every command in one dispatch table. Run `ruby dilla.rb help` and the command list is
printed from that table, so it cannot drift from what the code answers to; `help render`,
`help play` and the other topic names print one section. The helpers are grouped by what they
touch. The file `lib/sound.rb` holds instruments and signal: the oscillators, the device rack,
the mixer and the outboard chains. The file `lib/harmony.rb` holds pitch, `lib/groove.rb` holds
time and the drum presets, and `lib/listen.rb` holds measurement. The file `lib/sampling.rb`
handles the records the engine is fed, and `lib/slskd_crate.rb` is the optional Soulseek
source. Livesets and takes live in `lib/livesets.rb`, the composer's memory in
`lib/composer_mind.rb`, and the MIDI transformation chain in `lib/midi_effects.rb`. The scene
object that carries tension, density and material to both the sound and the picture is
`lib/scene.rb`, and `lib/radio_video.rb` and `lib/live_audiovisual.rb` build the video side.
The file `lib/ledger.rb` writes the knob census and the provenance sidecars. The data that
declares the music lives in `data/`: the bed in `bed.yml`, the thirty-one catalogue rows in
`pieces.yml`, documented progressions in `dilla_reference.yml`, and MIDI chains and live
settings in their own files.

## What bare invocation does

Bare `ruby dilla.rb` renders the finished showcase once and leaves the mix beside the script as
`dilla.wav`, then builds a video from that exact audio. The video is a Three.js architectural
score and not a spectrum display, and it passes through the shared postpro video recipe. The
default recipe is `dmt_bled`; `DILLA_VIDEO_POSTPRO` selects `architectural_clean`,
`dilla_heavy`, or `0` for an untreated export. Bare `ruby dilla.rb` asks no question, because
a render is reproduced from its knobs and its seed, and a question at the start is a step a
script cannot answer. The dispatcher at the bottom of `dilla.rb` defines runtime behavior.
Keep the command-help summary aligned with this bare-invocation contract.

The command `live` is the endless performance mode. It enters the same showcase engine, with
the same synths, effects, drum grids and source-backed progressions, and opens the local
Three.js visualizer. The picture is driven by the same scene and the same random stream as the
sound, so there is one musical source of truth. `DILLA_LIVE_VISUAL=0` plays sound only.
`DILLA_CURATED_HARMONY=1` selects original eight-chord arcs with deliberate voice-leading,
`DILLA_COMPOSED_MELODY=1` makes the lead carry a motif across chord changes, and `DILLA_FUGUE=1`
adds an original two-voice fugue, kept separate from `play bach`, which plays the exact BWV 565
MIDI. Live playback needs ffmpeg and either SoX or ffplay, and the player search checks the
Homebrew locations before PATH so a terminal launched from the desktop still finds them.

The command `compose` writes the other demonstration: one piece of about six minutes in which
every part answers the others. The bass states the key, a verified progression follows and later
returns mirrored about that key, the lead's motif is read from the chords, and percussion
answers each lead note. The drums play every bar, and filter and gain lanes carry the form.
Every note is an event before it sounds, and the swing, ratchets, stutters and reversals are
transforms named in `data/bed.yml`.

The command `catalogue` plays the older catalogue through one unchanged bed, each piece voiced
on one instrument, with every piece set to the same loudness under a true-peak ceiling. The bed
began as the pad under MASTER's narration and became the engine's render because it sounded
better than the engine's own catalogue. The command `bed` still plays it under the narration
and ducks it while a line is spoken. The command `pieces` renders the thirty-one rows of
`data/pieces.yml`, one process each, and `piece NAME` renders one. A row overlays `bed.yml`
before the bed reads a number, so it may set tempo, pad families, the lead rack, the drum
arrangement and samples; `DILLA_PIECE` chooses the overlay at load. The command `demo-all`
renders the older engine's catalogue and resumes, skipping parts already rendered.

## Where the sound comes from

The instruments are recipes and not recordings. The patch table `AnalogSynth::PATCHES` in
`lib/sound.rb` builds each voice from oscillators, a filter and two envelopes, and its comments
say what every setting is for. `DfamEngine` is the shape of a Moog DFAM: two oscillators, FM,
noise, a resonant decay and an eight-step pitch and velocity sequencer. The bed plays its own
oscillator families, declared in `data/bed.yml`. Every live voice also passes through a
physicality layer of tape wear, phase memory, sampler smear and deterministic drift;
`DILLA_PHYSICS=0` gives a clean A/B without it.

During a render, harmony comes first: a progression is refined by the theory operators and
becomes pads, bass and leads. A sampled loop is varispeeded, chopped and equalised beside it.
The drum grid receives its microtiming, swing, dirt and ducking. These meet at the analog bus,
which saturates each channel separately before the sum, because a desk makes harmonics per
channel and a single saturator on the master cannot. The sum then goes through the tape and
analog chains and loudness normalisation. Swell, tilt, dropout and mono bass run after
normalisation, since applied before it the normaliser would flatten them, and the slow tape
hysteresis model runs on the finished master because it is per-sample Ruby.

## Drums, swing and the pocket

The drum grids are `DRUM_PRESETS` in `lib/groove.rb`, in categories deliberately kept apart,
and `ruby dilla.rb audit` counts them and names any that no rotation reaches. Some grids were
transcribed from a recording, some were constructed to a described feel, and some were extracted
from licensed MIDI. The backbeat stays where the transcriptions put it. What makes the records
feel the way they do is `MICROTIMING_MS`, which holds the snare early and the hats late by a
few milliseconds, with the kick near the grid, and not a large swing percentage. The role scale
`SWING_ROLE_SCALE` leans each voice differently and locks the kick, since a pocket needs one
voice that does not move. `NO_QUANTIZE`, `SHIFT_TIMING` and `GROOVE_FEEL` shape the rest.

## Samples and the crate

The crate is the directory `samples/`, which git ignores. It holds the records, the grids and
the synthesised kit, and the repository tracks every decision made about them. `TRACK_SAMPLE_LOOPS`
in `dilla.rb` names each loop with its own tempo and its own low-end and top-end correction,
because one global value is wrong for whichever loop it was not tuned against; older ingest
names resolve through `TRACK_SAMPLE_LOOP_ALIASES`. A fresh worktree has no crate, and the tests
that need a loop skip there and say so. Dropping a loop back at `samples/<track>/loop.wav` is
enough to restore it, and `ruby dilla.rb assets` reports what the recipes name and the disk
lacks. Finding where a phrase begins is a human job; analysis confirms or refutes a boundary
you give it far better than it finds one.

The command `chop` cuts a long recording into bar-aligned beds. It scans for loud, steady
windows, separates them with demucs, keeps the bass, guitar, piano and other stems, drops drums
and vocals, finds each loop's length by correlation, and derives the tempo from the length and
the bar count. Each loop lands in `samples/chopped/` with a row in `loops.json`, and
`CHOP_BED=1` lets the engine pick one for a track that has no bed of its own. Off-air radio is
not licensed material, so every such row carries `rights: unlicensed`. The route that clears is
`lib/sampling.rb`, which digs public-domain and Creative Commons material with `dig` and
`dig-cc`, and `credits` lists the attribution owed.

The command `slskd` uses a local slskd instance as an optional source. It prefers lossless files
and peers with a free slot, copies the chosen file into the ignored local cache, and records the
peer, filename, query, checksum and rights state in the loop registry. Soulseek availability is
not a licence. The default rights state is unknown, and an unknown result is blocked unless
`SLSKD_ALLOW_UNKNOWN=1`, which exists for private research; set `SLSKD_RIGHTS` for material
whose rights are established.

Old work comes back whole. An Ableton set is a gzipped XML document, so `import-als` reads a set
that no longer opens in Live and returns its tempo, every track's device chain with parameters,
the notes, the chord harmony, the drum grids and the names of the samples it pointed at. Given a
folder and the word `write`, it leaves a profile per set in `project/imported/`, grids and clips
as MIDI in `samples/midi/`, and a census of the whole archive. It reads three tempo spellings,
because Live 12 renamed the master track and Live 8 and 9 store tempo as automation. Only the
writing and the decisions return; the audio is not in the file, and the engine synthesises the
sound itself. Related commands are `extract-als`, which writes MIDI of every key track, and
`play-liveset`.

## Controls that are not what they look like

Each of these failures was silent: the code ran, returned success, and did nothing. The alias
`DRUM_VOL` stands for `DRUM_MIX_WEIGHT` on the main render, and new recipes should use the
latter. The knob `KICK_GAIN` does not fix a loud low end that the loop is making; reach for
`SAMPLE_LOOP_HP` first. The filter `asoftclip` needs oversampling, or the harmonics it makes
above Nyquist fold back as aliasing. A symmetric transfer function such as `tanh` can make only
odd harmonics, and even harmonics need a bias. The `equalizer` filter is always a peaking
filter, and shelves are `bass` and `treble`. Track profiles beat the command line unless a
caller pins the value in `USER_PINNED_ENV`. `RAP_VOCAL=0` must be explicit, since the style
defaults soft-fill it. Measure with `STREAM_NORMALIZE=0`, because with normalisation on,
removing a layer makes the rest louder and the measurement describes the normaliser. The six
`SONITEX_*` section names are reserved and unread; only `SONITEX` and `SONITEX_PRESET` work.
Concat lists need absolute paths, because the demuxer resolves relative entries against the
list file's directory.

The same lessons recur, and they are worth stating as habits. When you find a bug here, count the
other sites before fixing the one in front of you, and fix at a choke point and not at the call
sites. A feature can be built, correct, documented and switched off, so grepping for it proves it
exists and only its default proves it runs. Making room beats adding gain. A claim about a mix
needs a render long enough to contain its evidence, because the kit does not enter below sixteen
bars and an eight-bar comparison of drums compares two drumless takes. A probe that reads a
global must fail loudly when the global is absent. The order of random draws is an interface:
adding one above an existing draw changes every take after it.

## How the environment is layered

One table of dilla DNA drives several renderers. The words `comfort`, `camel` and `warp` are
environment overlays on `RENDER_MODE=dilla` and not commands. The genre renderers `techno`,
`hate`, `industrial`, `analog` and `loose_pocket` are real dispatch keys with arrangements of
their own. The product path is `Shared::DillaProcessor` in `RAILS/__shared`, which shells out to
`dilla.rb` and attaches the file through Active Storage.

Lower layers only soft-fill, setting a knob when it is empty, and later layers force. A one-shot
render takes the caller's environment first, then `DILLA_BEST_DEFAULTS` and the render-mode table
`RENDER_MODE_DEFAULTS`, then `DILLA_STYLE_DEFAULTS`, and only then renders. The stream adds its own
layer, with the comfort mix unless `STREAM_PUNCH=1`. The variable `DILLA_COMFORT=1` gives a
one-shot the sofa mix, and `DILLA_RAW=1` skips every soft default so only the operator's
environment applies. Defaults are not restated here, because every table of them this file kept
went stale. The command `knobs` lists every knob the engine reads with its current default,
`knobs conflicts` names the ones with two defaults, `knobs check` says what is wrong now, and
`config-provenance` after a render names what that render resolved.

## Measuring a render

The measuring commands need no ear. The command `ears` describes a render to somebody who cannot
hear it: octave bands, loudness, crest, stereo width, how much of the record sits below
twenty-five hertz and above thirteen kilohertz, and a spectrogram. Given two files it prints the
deltas, and with `stems` it separates both first. The commands `quality`, `verify`, `timing`,
`beauty`, `mix-score`, `phone-preview` and `ab` each answer one narrower question, and `bed check`
holds the bed's band curve against the reference record. The three-band harshness meter compares
presence against body, because the old two-band split hid the roughness listeners complain about.

## Provenance

Every run writes a `<file>.provenance.json` beside each audio file it produces, through
`lib/ledger.rb`, hooked at the command entry before anything reads a seed. It carries the seed,
the arguments, the knobs that change the output, the engine commit, whether the tree was clean
and a checksum. The command `replay` turns a sidecar back into the command that makes the take
again. `RENDER_SEED` is drawn and recorded when unset, so two unpinned renders still differ but
each is a draw that can be replayed. `DILLA_NO_PROVENANCE=1` restores the unrecorded behaviour,
and renders from before provenance existed have no recorded seed. A liveset take is one line in
`project/liveset.jsonl` naming its seed and every choice, and the line rebuilds the take on any
machine that has the crate.

Renders land in a dated folder outside the repository, `~/Documents/dilla-renders/<date>` or
the same folder under `XDG_DATA_HOME` when that is set, and the engine prints the path it
chose. Only `dilla.wav` and `dilla.mp4`, the finished showcase, sit beside `dilla.rb`. The
words `renders`, `crate` and `samples` were once read as three places for one thing, so no
folder of renders lives in the tree. `DILLA_OUTPUT_DIR` chooses another place. A render may
not replace a named take unless `DILLA_OVERWRITE` says so. Before a render starts, the asset
check refuses to proceed if a named sample or kit is missing, since the failure is a
good-sounding beat that is not the one the recipe asked for; `DILLA_ASSET_CHECK=0` proceeds
anyway.

## The postpro bridge

Postpro's image vocabulary has audio counterparts in `Outboard.postpro_chain` in `lib/sound.rb`.
The three named racks are `postpro_transfer`, `postpro_wear` and `postpro_space`, and they map
image processes onto analogous tape, drift and echo devices. The bridge is conceptual and makes
no claim that an image process and an audio process are physically identical. In the other
direction, dilla's video renderer reads postpro's `video.yml` recipes.

## Trust

Imported Ableton XML, YAML, JSON, MIDI and audio metadata are untrusted data, parsed as data and
never turned into Ruby source, shell fragments or constant names. External processes such as
ffmpeg and demucs receive argument arrays and never shell strings. Paths are resolved before use,
state-changing renders write atomically, and network access stays out of the render path.
Provenance records evidence of what was rendered, and it is not permission to use material whose
rights are unknown.

The suites are `STUDIO/test/test_dilla_*.rb`, run one process each by `rake test:dilla` from
`STUDIO`. `MASTER/tools/dilla` is a compatibility symlink to this folder.

## Commands

Run these from `STUDIO/dilla`.

```sh
ruby dilla.rb help
ruby dilla.rb
ruby dilla.rb out.wav 18
TRACK=pedal_e_descent ruby dilla.rb dilla beat.wav 12
ruby dilla.rb pieces-list
ruby dilla.rb piece still_water out.wav
ruby dilla.rb compose
ruby dilla.rb import-als ~/Downloads/livesets write
ruby dilla.rb ears a.wav b.wav stems
ruby dilla.rb replay direction_v4.wav.provenance.json
ruby dilla.rb knobs
```


## Learning drum feel from sources

The `hear_drums` skill contract is owned at the MASTER/STUDIO boundary: MASTER governs and dispatches; this tree performs ingest, stem separation, analysis, hashing, and groove-hint generation. See [`../../../MASTER/docs/hear_drums_skill_contract.md`](../../../MASTER/docs/hear_drums_skill_contract.md) for the structured dossier and fail-closed requirements. The pipeline now exists as the `hear-drums` command and is tested with fake adapters; a real Demucs run has not been proven yet. Its hints are suggestions and never change a preset.

The implementation guide [`docs/dilla-time.md`](docs/dilla-time.md) maps publicly described themes of Dan Charnas's *Dilla Time* onto the existing role-aware microtiming, sampling, phrase development, provenance, and A/B workflow. Prefer extending existing timing primitives and source-learning paths over adding a second groove engine. The guide distinguishes sourced book framing from engineering interpretation; it is not a claim that the book's full text was consulted.
