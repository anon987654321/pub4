# Dilla

The default Blue Hour showcase uses a restrained `dilla_bed` bus rig and a leaner arrangement; `dilla_night` remains available for deliberately exaggerated effect experiments.

**A small room that plays a chord progression soft and a little late, with drums that
lean on the beat and a rack of analogue colour.** The complete live engine is the single
Ruby file `dilla.rb`: composition, music theory, synthesis, sequencing, instruments, effects,
mixing/mastering, reference analysis and output all live there. The versioned musical data
remains separate: `data/dilla.json` holds patches and grooves, `data/showcase.json` holds
the default arrangement, and `data/music_theory.json` holds harmonic references.
Research recovered from pub3 is preserved in `data/recovered_music.json`; it is not a verified
transcription set and does not enter the default render rotation.

A bare `ruby dilla.rb` needs no configuration. It renders the finite Blue Hour suite to a stereo
WAV and a matching MP4 visualizer, mastered once as a whole: seven slow progressions in the
minor and major keys a tone or a third apart, each played twice, a chord to the bar, with a
stepwise Rhodes melody on top, a warm pad and strings beneath and soft drums. `--arrangement`
plays any other file of sections in the same form. Each section declares its own tempo, and a
section marked `"engine": "stream"` runs through the same streamer as `--play`, so its groove
profile's voices, effect stages, noise, drums and echo all sound.

The default exporter writes `dilla.wav` and `dilla.mp4` beside `dilla.rb` and replaces that
pair on every run, since a render is replaceable and no new file or folder appears. Set
`DILLA_OUTPUT_DIR` to choose another default output directory, and pass `--out` to keep a
take, which then refuses to overwrite.

The MP4 is made offline by FFmpeg from the rendered audio, an architectural
grid/waveform scene, and the selected recipe in `STUDIO/postpro/video.yml` (default
`dilla_heavy`). FFmpeg with the `libx264` encoder is required for video. Export is bounded
to 900 seconds by default; set `DILLA_FFMPEG_TIMEOUT` to an integer from 1 to 3600 seconds
to override the deadline. A timed-out encoder is terminated as a process group. If FFmpeg is
unavailable or export fails, the WAV remains intact and the command reports an explicit
MP4 failure. Use `--no-video` for an audio-only render, `--video PATH` to choose the MP4
path, or `--video-preset NAME` to choose a recipe. `DILLA_VIDEO_POSTPRO=0` bypasses the
video-grade filters.

`ruby dilla.rb live` loops the same curated arrangement through the system player,
rendered into a disposable temporary WAV so it never overwrites the tracked reference.
Endless random playback remains available with `--play`; a random finite take remains
explicit with `--render`. Named options such as `--progression`, `--arp`, `--voice` or
`--drums` continue to choose exactly what they name.

Bare MASTER `/play` renders and plays this same showcase arrangement,
without encoding a video. This keeps the interactive audition and `ruby dilla.rb` on the
same musical arrangement and the same section-level drum and instrument effects.
A named `/play progression N` request remains a single progression, at 92 BPM unless
an explicit tempo or an available hip-hop reference supplies another value. Dilla-pocket
progressions use the full drum pattern, Rhodes, and the `dilla_night` bus-effects rig.

The rig is defined once in `data/dilla.json`: cassette colour, heavy drum tape, drum-bus
dub echo and crystallizer, with a quieter instrument echo/crystallizer send. The
`--effect-rig NAME` option applies this complete per-bus chain to standalone progression
renders too. Explicit effect flags remain authoritative over the rig defaults.

The harmony is written as well as quoted. Seventeen rule-made progressions sit beside the catalogue and are listed by `--list`: the original twelve plus five recovered grammars (`j5_donut_loop`, `relative_answer`, `dorian_four`, `flexible_sixth` and `mediant_lift`). Render one directly with `--language NAME`; they are generated from chord symbols at runtime and do not mutate the 506-record catalogue. `--voicing` lays any chord out as drop-2, drop-3, spread, cluster, quartal or so-what; `--key-lock Bb` brings a progression to rest on one tonic; and `--improvise` adds a lead and a bass worked out from the chords. `--takes N` renders each showcase section N times from different seeds and keeps the
take whose spectrum, dynamics and peaks fall nearest the warm target the critic measures, and every
showcase run ends with the critic's reading of the whole programme.

Four guitar voices (nylon, steel, muted and clean electric) are plucked strings: a burst of noise circulates in a tuned delay line and loses its highs on each trip, as a real string does. They hold pitch to within a cent, take any of the repeat and strum styles, and sound in the showcase section called Nylon Room.



### Recovered harmonic grammars

The five restored grammars are playable, transposable rule sets rather than fixed recordings: `j5_donut_loop` (IVmaj7–iii7–vi7–ii7), `relative_answer` (Imaj7–vi7–IVmaj7–ii7), `dorian_four` (i9–IV9), `flexible_sixth` (i9–vm11–Vmaj9) and `mediant_lift` (Imaj7–iii7–IIImaj7). They are generated in the chosen tonic, passed through the same chord parser and voice-leading search as every other progression, and can be rendered with the normal voice, groove, drum, MIDI and mastering options. The research notes identify these as harmonic movement grammars; they are not claims that any named recording uses this exact generated sequence.


The ten named chord/tempo presets from the earlier consolidated generator are also preserved in `data/recovered_music.json`. `--list` exposes them and `--heritage NAME` renders one through today's synthesizer, voicer, groove, effect and mastering path. Their original SoX effect labels remain provenance only; they are not silently translated into different current effect rigs. These are historical style presets, not verified transcriptions of recordings. The same archive retains the full earlier chord-type table, all jazz/neo-soul/funk progression groups, the 15 analog pad recipes, the 11 vintage FX-chain descriptions and the complete earlier drum-pattern/swing/synthesis database. The drum data and chord vocabulary were checked against the current recovery; the two pad/FX groups that were not represented in the current archive have now been carried forward intact.

## Engine notes

The detailed composition/groove, voice/instrument and effects/mastering rationale is kept in
[ENGINE_NOTES.md](ENGINE_NOTES.md), leaving this file focused on operating the renderer and
verifying its outputs.

## Rendering and live playback

`--transpose` moves every note by that many semitones before synthesis, and `--octaves`
is sugar for twelve times that. Nothing is resampled, and tempo and echo timing do not
change. A note whose fundamental lies above forty-five hundredths of the sample rate is
dropped rather than folded back down, and a warning says how many were lost. Twelve
octaves up puts every chord far past the limit, so the honest result is silence.
`--transpose-wrap` instead folds each note down by octaves until it is under fourteen
kilohertz, the highest audible register.

`--play`, also spelled `--endless`, never stops, and it streams. Each pass is rendered a
block at a time and written as raw 16-bit mono PCM to the standard input of the player,
`ffplay` or sox's `play` unless `--player` names another command, which then reads raw
PCM on its standard input.

The first block is one beat, so the music starts before a bar is ready, and after that a
bar at a time, with two blocks rendered ahead of the one playing.

Every filter, effect
and note keeps its state from one block to the next: a note is read a block at a time,
so its oscillators and filters carry on where they stopped, and the echo, the colour,
the room, the spring, the sidechain and the tape stack are objects with memory. A pass
cut into blocks of any size gives the same samples as the pass in one block, which the
tests hold to float rounding.

The next pass is built on a thread while this one plays and begins under the end of it,
the source of the one fading out and the other in at equal power, while the echo and the
room of the old pass ring on beneath. The tape stack and its ceiling run once over the
sum, so a join does not restart them. A quit player ends the show quietly, and SIGINT or
SIGTERM stops it and takes the player with it.

At the end it prints how long it took to render what it played, and how many blocks
arrived late. Every kind of choice comes out of its own shuffle bag: the progression,
the mode, the arp or repeat style, the patch and the profile. The patch bag holds every
voice: a patch comes back only after all the others have played, and a group never
follows itself. A bag plays everything once before anything repeats and never opens with
the last item of the one before. The bags are saved in `out/play/` between runs, so a
restart goes on with the cycle.

Each pass prints its progression and position in the
bag, mode, style, voice with its place in the patch bag, and profile. A pad plays its
voice like any other; the plain sine pad is the old pad. `--patch-per-chord` gives every
chord of a pad its own patch, drawn in turn from the same bag, so a progression of four
chords uses four places in the cycle.

Dub-style bus effects that only the showcase uses
are not in the stream, and the rumble under the techno profiles is scaled by a fixed
gain found from one kick, where a whole render scales by its own peak.

Play has two decks by default, and `--decks 1` gives one. Deck B is built, with its
first bars already rendered, while deck A plays, so a crossfade costs no more than a
pass alone. Each pass lasts eight to sixteen bars, whatever its progression, which is
cycled or cut to fit. When A has played them, B comes in under it over two to four bars
that begin on A's bar line, equal power, with B's tempo held within six beats a minute
of A's. The drums keep running: A's go on to the end of its last bar and B's come in
with the crossfade.

A few times a minute, three on average and `--moves N` to change it,
a live move is made at a bar by a hand with a seeded stream of its own: the echo is
thrown for a bar, a filter sweeps down to 700 hertz and back, the tape is driven twice
as hard and back, the Sonitex climbs from one pass to three and down, the room swells,
or the drums drop out for a bar.

A move is an event with a start and a length, never an
oscillator. Moves are logged as they begin, none begins while two decks cross, no kind
comes twice running, and each puts back exactly the parameter it moved. With one deck
the crossfade is a single beat and nothing moves unless `--moves` asks.

The engine is small on purpose, and its limits are plain. The moog and dfam waves are
naive and alias at very high pitch. A render takes about a fifth to a third of its own
length to compute, more with the echo and the colour chains on. The old engine, which
was far larger, is not lost. The tag `dilla-engine-final` marks the last commit that
carried all of it, `git checkout dilla-engine-final -- STUDIO/dilla` brings it back, and
`git show dilla-engine-final:STUDIO/dilla/lib/sound.rb` reads one file from it. The tag also preserves the earlier browser/Three.js `RadioVideo` and `LiveAudiovisual` implementation. Those renderers depend on their historical bundle and output contract, so they are deliberately not copied into this engine's FFmpeg video path.

## One Ruby source, explicit data

`dilla.rb` is the single authoritative Ruby implementation: chord parsing and voicing,
progression selection, groove timing, arpeggiation, generative melody, organ, instrument and
drum synthesis, soundfont bridging, effects, tape, mixing and mastering, reference analysis,
industrial-techno generation, playback, and WAV/MIDI/MP4 output all live in labelled
sections of this file. There are no parallel per-subsystem Ruby implementations to keep in
sync.

The data stays separate because it is music, not executable logic. `data/dilla.json` is the
validated runtime pool of progressions, patches, groove profiles, drum patterns, stages,
noise layers, stereo placement, mastering parameters and shared bus-effect rigs.
`data/music_theory.json` holds interval, chord and harmonic-motion references plus curated
two- and three-bar progressions. `data/showcase.json` is the Blue Hour suite.
`data/recovered_music.json` preserves 42 named historical progression profiles, three
legacy progression groups, drum/swing studies, synthesis notes and five sample-study leads.
Artist and track labels remain unverified research leads; this archive is not loaded into the
runtime progression pool.

To hear it, `ruby dilla.rb --play` streams without end,
`ruby dilla.rb --progression 3 --seed 5 --out take.wav` renders one pass,
`ruby dilla.rb --mode organ --seed 3 --out organ.wav` improvises for the organ, and
`ruby dilla.rb --arp list` names the arpeggios.

The theory catalogue is explanatory source material; runtime choices still come from the
validated data pools. Curated compositions list suggested voice patches and intent so they
can be auditioned as distinct arrangements.

## Audio-reference analysis and style learning

The canonical hip-hop reference should be studied for pocket, swing, microtiming, sample-to-drum relationship, phrase density, arrangement changes and broad tonal balance. An orchestral tribute is useful evidence of musical influence, but it is not the target sound for a beat engine. Learn measurable production traits and musical principles, not source melodies or note-for-note arrangements.

Explicitly describing a source as an album lets MASTER use the analyzer's existing hard two-hour ceiling. Ordinary track references retain the shorter default cap. This enables full-album uploads without silently making every pasted link an expensive long-form Demucs job.

The reference workflow analyzes the **music only**; it never inspects or downloads video
frames. It imports a YouTube audio stream with yt-dlp, measures duration, format,
loudness, coarse spectral bands, a low-rate temporal energy map and an estimated tempo
with FFmpeg, then optionally runs Demucs and Essentia when their command-line tools are
installed. The FFmpeg tempo estimator preserves genuine low-tempo estimates instead of automatically doubling any result below 80 BPM,
and reports one-minute local tempo windows plus median/range; rhythm features are measured
within those windows for long references, reducing tempo-change bias. Analysis subprocess timeouts scale with the requested input duration but
remain capped at one hour per pass. Tools run in isolated process groups; a timeout terminates the child
and lingering descendants rather than only interrupting the waiting Ruby call. When Essentia is present,
the report surfaces independent BPM candidates,
onset-rate and selected tonal/spectral summaries alongside the local tempo estimate.
Agreement and half/double-time ambiguity are reported rather than silently blended. The
rhythm summary also names its evidence source: a Demucs drums stem when available, or an
explicitly labelled full-mix proxy when separation is unavailable or disabled. Where a drums
stem exists, its broad 25–120 Hz and 4 kHz-plus energy bands are also reported beside the mix.
Those are stem-level frequency summaries, not isolated kick or hi-hat measurements.

MASTER can infer a broad style from the instruction accompanying the link, so a boom-bap reference and an industrial-techno reference stay separate. In chat, say
something like “learn this track's hip-hop production style” and paste the link; later,
“make a beat like that” uses the learned profile. For techno, say “study this
industrial-techno track” and paste the link, then ask for a track in that style. A
pasted YouTube link by itself is also treated as a reference, although without any style
cue MASTER cannot infer the genre from audio measurements alone. Direct CLI use can name
the style explicitly:

~~~sh
ruby dilla.rb reference 'https://youtu.be/VIDEO_ID' --style j_dilla
ruby dilla.rb reference 'https://youtu.be/ALBUM_VIDEO_ID' --style j_dilla --max-duration 7200
ruby dilla.rb reference 'https://youtu.be/VIDEO_ID' --style industrial_techno
ruby dilla.rb reference 'https://youtu.be/VIDEO_ID' --no-stems
ruby dilla.rb reference /absolute/path/to/audio.wav
ruby dilla.rb industrial-techno
~~~

A hip-hop profile supplies an averaged target tempo, the dedicated Dilla shadow pocket,
a Rhodes voice, dusty kit, and cassette-coloured drums to later Dilla beat renders; a
matching industrial-techno profile steers the separate techno renderer. Each new link
adds a compact measurement record to that style's learned profile, averaging tempo and
numeric production features across references of the same style. The audio envelope also
provides broad onset density, offbeat-share, and sixteenth-grid timing-spread estimates;
these can choose among Dilla's existing dusty/syncopated patterns and slightly adjust
its groove amount, rather than forcing every reference through one preset.

When Demucs stems are available, their relative drum/bass/vocal/other energy shares are
recorded too: bass and drum balance gently steers industrial rumble and kick ducking,
while hip-hop renders use a bounded (at most 2 dB) drum/chord mix adjustment. Missing
stems or unusable measurements leave Dilla's normal mix defaults intact. Rhythm features
describe the measured envelope and do not claim exact kick/snare note transcription.

General references remain general and do not silently become techno. Style profiles and
the active style are saved separately, so a general link or a techno reference does not
erase the accumulated hip-hop profile, and vice versa. Dilla chooses arrangement length
and an internal seed itself; `--bars` and `--seed` remain optional expert overrides.

Install yt-dlp and FFmpeg for URL import and measurement. To use source separation,
install Demucs in a dedicated environment and make its demucs executable available on
PATH, or set DEMUCS_BIN. Essentia's `streaming_extractor_music` is optional.

For a second independent estimate of tempo, meter, beats and downbeats, key, chords,
sections, timbre, dynamics and rhythm, optionally install libsonare in the environment
used by STUDIO/dilla (`pip install libsonare`). Its command-line entry point is
`sonare`; set `LIBSONARE_BIN` if it lives outside `PATH`. Dilla calls
`sonare analyze FILE --json` using an argument vector, stores the raw result in
`libsonare_features.json`, and surfaces a compact summary plus a separate tempo
cross-check in `analysis.json` and `report.md`. On inputs other than WAV/MP3, FFmpeg
creates a temporary mono WAV that is removed after analysis. The optional pass is
skipped above 900 seconds because the Python CLI loads the decoded recording in memory;
the existing FFmpeg/Essentia workflow still handles longer references. Use
`--no-libsonare` to disable the pass for a run. Dilla never installs tools or downloads
models automatically, and missing or failed optional engines are reported instead of
being represented as successful measurements. Unavailable tools do not become required
just to render Dilla's existing showcase.

Reference output, reports, JSON profiles and stems default to
`${XDG_DATA_HOME:-~/Downloads}/dilla-references`. Relative or checkout-local
`XDG_DATA_HOME` values are ignored for output safety when they are relative or point
inside the checkout. If `~/Downloads` itself resolves inside the checkout, STUDIO refuses
the fallback rather than writing media there. With an absolute data home outside the checkout,
Dilla and MASTER share the learned-profile store.
Each profile records the user's style hint separately from measured traits: tempo estimates,
spectral bands and 15-second energy windows are measurements, while an artist/genre label
comes from the request, not an automatic genre classifier. The temporal map describes broad
arrangement energy, not note transcription; independent tempo estimates may disagree or
choose half/double time, and all conclusions retain those limitations. The JSON and Markdown
reports include source title, channel, canonical URL and duration when available; local
audio reports record only the filename, never the absolute path.

The industrial-techno command makes a new four-on-the-floor composition with distorted
sub/rumble, dissonant drones, metallic hits and evolving density with a breakdown. It
uses broad audio characteristics and never loads reference audio or separated stems into
the generated composition. Tempo estimates can be ambiguous between half-time and
double-time, and Demucs stems can contain bleed and artifacts.

## Rhythmic reference study

The evidence-based research notes, provenance warnings, and measurement plan for the two current
reference mixes are in [REFERENCE_STUDY.md](REFERENCE_STUDY.md). That document distinguishes
published production history and tracklist metadata from measurements that still require bounded
audio excerpts; it does not invent BPM or microtiming data for audio the analyzer has not processed.


## Lifecycle sound cues (Claude Code / OpenCode compatible)

The lifecycle vocabulary and manifest concept are inspired by [claude-sound-fx](https://github.com/6m1w/claude-sound-fx); Dilla does not bundle that project's source code, character-voice assets, or HTTP relay.

Dilla can generate its own short synthetic lifecycle cues without importing third-party voice clips or requiring another sound-effects engine:

```sh
ruby dilla.rb sound-fx list
ruby dilla.rb sound-fx complete --play
ruby dilla.rb sound-fx error --play --volume 35
ruby dilla.rb sound-fx complete --seed 112 --out /tmp/dilla-complete.wav
```

The event names mirror common Claude Code / OpenCode sound-hook vocabulary: `start`, `submit`, `complete`, `error`, `notification`, `precompact` and `session_end`. They are backed by `data/sound_fx.json`, then rendered through Dilla's existing colour, dub-echo, plate and mastering chain. The cues are original synthesis, not downloaded speech samples. `--play` uses an already-installed local player and writes only a temporary WAV; it never installs software or starts a network relay. Without a player, use `--out` to render a file for another local workflow.

For Claude Code, a configured command hook may invoke `sound_fx_hook.sh` with no argument: the adapter reads the JSON on stdin and maps only a known `hook_event_name` to the seven-event allowlist. You can also call `sound_fx_hook.sh complete` directly with an explicit event. The parser recognises selected OpenCode-style `event.type` values when a lifecycle wrapper passes that JSON to stdin; it does not register or install itself as an OpenCode plugin. Unknown events and malformed payloads are quiet no-ops. The adapter never evaluates payload contents, installs software, or forwards audio over a network. Permission approval popups are not part of this event contract and cannot be represented as hook events.

Each render reports the seed, event, duration, integrated loudness and true-peak measurement as JSON. The regression test enforces exact event coverage, deterministic rendering for a fixed seed, bounded duration and the configured sample-peak ceiling. These are local signal checks, not subjective listening approval.
